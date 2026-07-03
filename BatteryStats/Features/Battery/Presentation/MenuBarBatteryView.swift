import AppKit
import Observation
import SwiftUI

struct MenuBarBatteryView: View {
    @Bindable var monitor: BatteryMonitor
    @Bindable var preferences: PreferencesStore
    let historyStore: BatteryHistoryStore
    private let prepareForSettingsAction: @MainActor () -> Void
    private let openSettingsAction: @MainActor () -> Void

    init(
        monitor: BatteryMonitor,
        preferences: PreferencesStore,
        historyStore: BatteryHistoryStore,
        prepareForSettingsAction: @escaping @MainActor () -> Void = {},
        openSettingsAction: @escaping @MainActor () -> Void = {
            NotificationCenter.default.post(name: .showBatteryStatsSettingsWindow, object: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.monitor = monitor
        self.preferences = preferences
        self.historyStore = historyStore
        self.prepareForSettingsAction = prepareForSettingsAction
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        VStack(spacing: 0) {
            BatterySurfaceView(
                monitor: monitor,
                preferences: preferences,
                isLightningRefreshEnabled: .constant(false)
            )
                .frame(minWidth: BatterySurfaceLayout.minimumWidth, alignment: .topLeading)

            Divider()

            HStack(spacing: 10) {
                Button {
                    monitor.refresh()
                } label: {
                    if monitor.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.62)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(monitor.isRefreshing)
                .help("Refresh")

                Button {
                    monitor.copyParsedSnapshot()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(monitor.canCopyParsedSnapshot == false)
                .help("Copy Snapshot")

                Button {
                    historyStore.copyCSV()
                } label: {
                    Image(systemName: "tablecells")
                }
                .disabled(historyStore.entries.isEmpty)
                .help("Copy History CSV")

                Spacer(minLength: 16)

                Button {
                    prepareForSettingsAction()
                    openSettingsAction()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .containerBackground(.thinMaterial, for: .window)
    }
}

@MainActor
final class MenuBarStatusItemController: NSObject {
    private static let panelGlobalDismissalGrace: TimeInterval = 1.25

    private let monitor: BatteryMonitor
    private let preferences: PreferencesStore
    private let historyStore: BatteryHistoryStore
    private let statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var panel: NSPanel?
    private var appliedIdentity: String?
    private var installedDisplayPreferences: MenuBarDisplayPreferences?
    private var displayPreferenceObserver: NSObjectProtocol?
    private var deferredDisplayPreferenceRefreshTask: Task<Void, Never>?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var activeSpaceObserver: NSObjectProtocol?
    private var lastPanelShowDate: Date?
    private var deferredPanelPresentationTask: Task<Void, Never>?
    private var deferredPanelDismissalTask: Task<Void, Never>?
    private var isStarted = false

    init(
        monitor: BatteryMonitor,
        preferences: PreferencesStore,
        historyStore: BatteryHistoryStore,
        statusBar: NSStatusBar = .system
    ) {
        self.monitor = monitor
        self.preferences = preferences
        self.historyStore = historyStore
        self.statusBar = statusBar
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    isolated deinit {
        deferredDisplayPreferenceRefreshTask?.cancel()
        closePanel()

        if let displayPreferenceObserver {
            NotificationCenter.default.removeObserver(displayPreferenceObserver)
        }

        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }

        statusBar.removeStatusItem(statusItem)
    }

    func start() {
        guard isStarted == false else {
            return
        }

        isStarted = true
        configureButton()
        installedDisplayPreferences = currentDisplayPreferences
        applyCurrentStatusItemState()
        observeStatusItemInputs()
        observeDisplayPreferenceNotifications()
        observeActiveSpaceChanges()
    }

    #if DEBUG
    func currentButtonSnapshot() -> MenuBarStatusItemButtonSnapshot {
        MenuBarStatusItemButtonSnapshot(statusItem: statusItem)
    }

    func overwriteButtonTitleForTesting(_ title: String) {
        statusItem.button?.title = title
    }

    func currentStatusItemIdentityForTesting() -> ObjectIdentifier {
        ObjectIdentifier(statusItem)
    }

    func showPanelForTesting() {
        guard let button = statusItem.button else {
            return
        }

        showPanel(relativeTo: button)
    }

    func closePanelForTesting() {
        closePanel()
    }

    func overwriteLastPanelShowDateForTesting(_ date: Date) {
        lastPanelShowDate = date
    }

    func closePanelFromGlobalEventForTesting(now: Date) {
        closePanelFromGlobalEventIfNeeded(now: now)
    }

    func cancelDeferredPanelDismissalForTesting() {
        cancelDeferredPanelDismissal()
    }

    func currentPanelSnapshotForTesting() -> MenuBarPanelPresentationSnapshot? {
        panel.map(MenuBarPanelPresentationSnapshot.init(panel:))
    }
    #endif

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.imageScaling = .scaleProportionallyDown
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private func apply(_ state: MenuBarBatteryLabelState, force: Bool = false) {
        guard force || state.identity != appliedIdentity else {
            return
        }

        if MenuBarStatusItemRenderer.apply(state, to: statusItem) {
            appliedIdentity = state.identity
        }
    }

    private func observeStatusItemInputs() {
        withObservationTracking {
            _ = monitor.snapshot
            _ = preferences.menuBarDisplayMode
            _ = preferences.temperatureUnitPreference
            _ = preferences.temperatureUnitResolutionToken
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                applyCurrentStatusItemState()
                observeStatusItemInputs()
            }
        }
    }

    private func observeDisplayPreferenceNotifications() {
        guard displayPreferenceObserver == nil else {
            return
        }

        displayPreferenceObserver = NotificationCenter.default.addObserver(
            forName: .menuBarDisplayPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let invalidation = MenuBarDisplayPreferencesInvalidation(notification: notification)
            MainActor.assumeIsolated {
                self?.refreshFromDisplayPreferenceInvalidation(invalidation)
            }
        }
    }

    private func observeActiveSpaceChanges() {
        guard activeSpaceObserver == nil else {
            return
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionPanelForActiveSpaceChangeIfNeeded()
            }
        }
    }

    private func refreshFromDisplayPreferenceInvalidation(_ invalidation: MenuBarDisplayPreferencesInvalidation) {
        guard preferences.shouldAcceptMenuBarDisplayPreferencesInvalidation(invalidation) else {
            return
        }

        let didChangeDisplayPreferences = preferences.refreshMenuBarDisplayPreferences(from: invalidation.displayPreferences)
        if didChangeDisplayPreferences || currentDisplayPreferences != installedDisplayPreferences {
            reinstallStatusItemForDisplayPreferenceChange()
        }
        applyCurrentStatusItemState(force: true)
        scheduleDeferredDisplayPreferenceRefresh()
    }

    private func reinstallStatusItemForDisplayPreferenceChange() {
        closePanel()
        statusBar.removeStatusItem(statusItem)
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        appliedIdentity = nil
        configureButton()
        installedDisplayPreferences = currentDisplayPreferences
    }

    private var currentDisplayPreferences: MenuBarDisplayPreferences {
        MenuBarDisplayPreferences(
            displayMode: preferences.menuBarDisplayMode,
            temperatureUnitPreference: preferences.temperatureUnitPreference
        )
    }

    private func scheduleDeferredDisplayPreferenceRefresh() {
        deferredDisplayPreferenceRefreshTask?.cancel()
        deferredDisplayPreferenceRefreshTask = Task { @MainActor [weak self] in
            for delay in [20_000_000, 120_000_000, 320_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))

                guard Task.isCancelled == false else {
                    return
                }

                self?.applyCurrentStatusItemState(force: true)
            }
        }
    }

    private func applyCurrentStatusItemState(force: Bool = false) {
        apply(
            MenuBarBatteryLabelState(snapshot: monitor.snapshot, preferences: preferences),
            force: force
        )
    }

    @objc
    private func togglePanel(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel(relativeTo: button)
        }
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        closePanel()

        let panel = makePanel()
        self.panel = panel

        layoutPanel(panel, relativeTo: button)
        lastPanelShowDate = Date()

        presentPanel(panel)
        scheduleDeferredPanelPresentationRetries(for: panel, relativeTo: button)
        installDismissalMonitors()
    }

    private func presentPanel(_ panel: NSPanel) {
        panel.parent?.removeChildWindow(panel)
        panel.collectionBehavior = BatteryWindowSpaceBehavior.menuBarPanelPresentation
        panel.level = .popUpMenu
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
    }

    private func scheduleDeferredPanelPresentationRetries(for panel: NSPanel, relativeTo button: NSStatusBarButton) {
        deferredPanelPresentationTask?.cancel()
        deferredPanelPresentationTask = Task { @MainActor [weak self, weak panel, weak button] in
            for delay in [50_000_000, 180_000_000, 450_000_000, 900_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))

                guard Task.isCancelled == false,
                      let self,
                      let panel,
                      self.panel === panel,
                      let button else {
                    return
                }

                self.layoutPanel(panel, relativeTo: button)
                self.presentPanel(panel)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let rootView = MenuBarBatteryView(
            monitor: monitor,
            preferences: preferences,
            historyStore: historyStore,
            prepareForSettingsAction: { [weak self] in
                self?.closePanel()
            }
        )
        .environment(monitor)
        .environment(preferences)
        .monitorConfiguration(
            monitor: monitor,
            preferences: preferences,
            historyStore: historyStore,
            startsMonitor: true
        )

        let contentView = makePanelContentView(rootView: rootView)
        let panel = MenuBarStatusPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: BatterySurfaceLayout.minimumWidth,
                height: BatterySurfaceLayout.menuBarPanelMinimumHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.canHide = false
        panel.isMovable = false
        panel.worksWhenModal = true
        panel.level = .popUpMenu
        return panel
    }

    private func makePanelContentView<Content: View>(rootView: Content) -> NSView {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let backgroundView = NSVisualEffectView()
        backgroundView.material = .popover
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = BatterySurfaceLayout.menuBarPanelCornerRadius
        backgroundView.layer?.masksToBounds = true
        backgroundView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        ])

        return backgroundView
    }

    private func layoutPanel(_ panel: NSPanel, relativeTo button: NSStatusBarButton) {
        let size = panelContentSize(panel)
        panel.setContentSize(size)

        guard let frame = panelFrame(size: size, anchoredTo: button) else {
            panel.center()
            return
        }

        panel.setFrame(frame, display: true)
    }

    private func panelContentSize(_ panel: NSPanel) -> NSSize {
        guard let contentView = panel.contentView else {
            return NSSize(
                width: BatterySurfaceLayout.minimumWidth,
                height: BatterySurfaceLayout.menuBarPanelMinimumHeight
            )
        }

        contentView.setFrameSize(NSSize(
            width: BatterySurfaceLayout.minimumWidth,
            height: BatterySurfaceLayout.menuBarPanelMinimumHeight
        ))
        let fittingSize = contentView.fittingSize

        return NSSize(
            width: max(BatterySurfaceLayout.minimumWidth, fittingSize.width),
            height: max(BatterySurfaceLayout.menuBarPanelMinimumHeight, fittingSize.height)
        )
    }

    private func panelFrame(size: NSSize, anchoredTo button: NSStatusBarButton) -> NSRect? {
        guard let buttonWindow = button.window else {
            return MenuBarPanelLayout.fallbackFrame(size: size, near: NSEvent.mouseLocation)
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectInScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let screenFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? buttonRectInScreen
        return MenuBarPanelLayout.frame(
            size: size,
            anchoredTo: buttonRectInScreen,
            screenFrame: screenFrame
        )
    }

    private func installDismissalMonitors() {
        removeDismissalMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else {
                return event
            }

            if event.type == .keyDown, event.keyCode == 53 {
                self.closePanel()
                return nil
            }

            if event.type != .keyDown {
                if event.window === self.panel || self.isEventInsideStatusButton(event) {
                    self.cancelDeferredPanelDismissal()
                    return event
                }

                self.closePanel()
            }

            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePanelFromGlobalEventIfNeeded()
            }
        }
    }

    private func removeDismissalMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func isEventInsideStatusButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button,
              event.window === button.window else {
            return false
        }

        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    private func closePanel() {
        deferredPanelPresentationTask?.cancel()
        deferredPanelPresentationTask = nil
        cancelDeferredPanelDismissal()
        lastPanelShowDate = nil
        removeDismissalMonitors()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
    }

    private func repositionPanelForActiveSpaceChangeIfNeeded() {
        guard panel?.isVisible == true else {
            return
        }

        guard let panel,
              let button = statusItem.button else {
            closePanel()
            return
        }

        layoutPanel(panel, relativeTo: button)
        presentPanel(panel)
    }

    private func closePanelFromGlobalEventIfNeeded(now: Date = Date()) {
        guard panel?.isVisible == true else {
            return
        }

        if let lastPanelShowDate,
           now.timeIntervalSince(lastPanelShowDate) < Self.panelGlobalDismissalGrace {
            let remainingDelay = Self.panelGlobalDismissalGrace - max(0, now.timeIntervalSince(lastPanelShowDate))
            scheduleDeferredPanelDismissal(remainingDelay: remainingDelay)
            return
        }

        closePanel()
    }

    private func scheduleDeferredPanelDismissal(remainingDelay: TimeInterval) {
        guard deferredPanelDismissalTask == nil else {
            return
        }

        let delayNanoseconds = UInt64(max(0, remainingDelay) * 1_000_000_000)
        deferredPanelDismissalTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }

            guard Task.isCancelled == false,
                  let self else {
                return
            }

            deferredPanelDismissalTask = nil
            closePanel()
        }
    }

    private func cancelDeferredPanelDismissal() {
        deferredPanelDismissalTask?.cancel()
        deferredPanelDismissalTask = nil
    }

}

@MainActor
private final class MenuBarStatusPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

#if DEBUG
struct MenuBarPanelPresentationSnapshot {
    let isVisible: Bool
    let level: NSWindow.Level
    let collectionBehavior: NSWindow.CollectionBehavior
    let styleMask: NSWindow.StyleMask
    let canBecomeKey: Bool
    let canBecomeMain: Bool
    let becomesKeyOnlyIfNeeded: Bool
    let isFloatingPanel: Bool
    let hidesOnDeactivate: Bool
    let isOpaque: Bool
    let backgroundAlpha: CGFloat
    let contentViewClassName: String
    let contentViewCornerRadius: CGFloat?

    @MainActor
    init(panel: NSPanel) {
        isVisible = panel.isVisible
        level = panel.level
        collectionBehavior = panel.collectionBehavior
        styleMask = panel.styleMask
        canBecomeKey = panel.canBecomeKey
        canBecomeMain = panel.canBecomeMain
        becomesKeyOnlyIfNeeded = panel.becomesKeyOnlyIfNeeded
        isFloatingPanel = panel.isFloatingPanel
        hidesOnDeactivate = panel.hidesOnDeactivate
        isOpaque = panel.isOpaque
        backgroundAlpha = panel.backgroundColor?.alphaComponent ?? 1
        contentViewClassName = panel.contentView.map { String(describing: type(of: $0)) } ?? ""
        contentViewCornerRadius = panel.contentView?.layer?.cornerRadius
    }
}
#endif

enum MenuBarPanelLayout {
    static let margin: CGFloat = 6

    static func frame(size: NSSize, anchoredTo anchorRect: NSRect, screenFrame: NSRect) -> NSRect {
        panelFrame(
            size: size,
            midX: anchorRect.midX,
            belowY: anchorRect.minY - size.height - margin,
            aboveY: anchorRect.maxY + margin,
            screenFrame: screenFrame
        )
    }

    @MainActor
    static func fallbackFrame(size: NSSize, near point: NSPoint) -> NSRect {
        let screenFrame = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(origin: .zero, size: size)
        return fallbackFrame(size: size, near: point, screenFrame: screenFrame)
    }

    static func fallbackFrame(size: NSSize, near point: NSPoint, screenFrame: NSRect) -> NSRect {
        panelFrame(
            size: size,
            midX: point.x,
            belowY: point.y - size.height - margin,
            aboveY: point.y + margin,
            screenFrame: screenFrame
        )
    }

    private static func panelFrame(size: NSSize, midX: CGFloat, belowY: CGFloat, aboveY: CGFloat, screenFrame: NSRect) -> NSRect {
        NSRect(
            origin: NSPoint(
                x: clampedHorizontalOrigin(preferredMidX: midX, width: size.width, screenFrame: screenFrame),
                y: verticalOrigin(preferredBelowY: belowY, fallbackAboveY: aboveY, height: size.height, screenFrame: screenFrame)
            ),
            size: size
        )
    }

    private static func clampedHorizontalOrigin(
        preferredMidX: CGFloat,
        width: CGFloat,
        screenFrame: NSRect
    ) -> CGFloat {
        let minimumX = screenFrame.minX + margin
        let maximumX = screenFrame.maxX - width - margin
        guard minimumX <= maximumX else {
            return screenFrame.midX - (width / 2)
        }

        return min(max(preferredMidX - (width / 2), minimumX), maximumX)
    }

    private static func verticalOrigin(
        preferredBelowY: CGFloat,
        fallbackAboveY: CGFloat,
        height: CGFloat,
        screenFrame: NSRect
    ) -> CGFloat {
        let minimumY = screenFrame.minY + margin
        let maximumY = screenFrame.maxY - height - margin
        var originY = preferredBelowY

        if originY < minimumY {
            originY = min(fallbackAboveY, maximumY)
        }

        if minimumY <= maximumY {
            return min(max(originY, minimumY), maximumY)
        }

        return screenFrame.midY - (height / 2)
    }
}

@MainActor
enum MenuBarStatusItemRenderer {
    @discardableResult
    static func apply(_ state: MenuBarBatteryLabelState, to statusItem: NSStatusItem) -> Bool {
        let title = state.statusItemTitle
        let length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        let imagePosition: NSControl.ImagePosition = title.isEmpty ? .imageOnly : .imageLeft
        statusItem.length = length

        guard let button = statusItem.button else {
            return false
        }

        let image = statusImage(systemName: state.symbolName)

        button.image = nil
        button.alternateImage = nil
        button.imagePosition = .noImage
        button.title = ""
        button.alternateTitle = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = nil
        button.contentTintColor = nil
        button.setAccessibilityLabel(nil)

        let renderedTitle = attributedStatusTitle(title, font: button.font)
        button.image = image
        button.title = title
        button.attributedTitle = renderedTitle
        button.imagePosition = imagePosition
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = state.accessibilityLabel
        button.setAccessibilityLabel(state.accessibilityLabel)
        button.invalidateIntrinsicContentSize()
        button.needsLayout = true
        button.needsDisplay = true

        statusItem.length = length
        return true
    }

    private static func statusImage(systemName: String) -> NSImage {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
            ?? NSImage()
        image.isTemplate = true
        return image
    }

    private static func attributedStatusTitle(_ title: String, font: NSFont?) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
        if let font {
            attributes[.font] = font
        }

        return NSAttributedString(string: title, attributes: attributes)
    }
}

#if DEBUG
struct MenuBarStatusItemButtonSnapshot: Equatable {
    let title: String
    let attributedTitle: String
    let imagePosition: NSControl.ImagePosition
    let length: CGFloat
    let toolTip: String?

    @MainActor
    init(statusItem: NSStatusItem) {
        title = statusItem.button?.title ?? ""
        attributedTitle = statusItem.button?.attributedTitle.string ?? ""
        imagePosition = statusItem.button?.imagePosition ?? .noImage
        length = statusItem.length
        toolTip = statusItem.button?.toolTip
    }
}
#endif

struct MenuBarBatteryLabelState {
    let symbolName: String
    let value: String?
    let accessibilityLabel: String
    let identity: String

    var statusItemTitle: String {
        value ?? ""
    }

    @MainActor
    init(snapshot: BatterySnapshot?, preferences: PreferencesStore) {
        self.init(
            snapshot: snapshot,
            displayMode: preferences.menuBarDisplayMode,
            temperatureUnitPreference: preferences.temperatureUnitPreference
        )
    }

    init(
        snapshot: BatterySnapshot?,
        displayMode: MenuBarDisplayMode,
        temperatureUnitPreference: TemperatureUnitPreference
    ) {
        let symbolTintStyle = BatteryPresentationStyle.chargeTintStyle(for: snapshot)
        symbolName = BatteryPresentationStyle.batterySymbolName(for: snapshot)
        value = MenuBarBatteryLabelFormatting.displayValue(
            snapshot: snapshot,
            displayMode: displayMode,
            temperatureUnitPreference: temperatureUnitPreference
        )
        accessibilityLabel = MenuBarBatteryLabelFormatting.accessibilityLabel(
            snapshot: snapshot,
            displayMode: displayMode,
            temperatureUnitPreference: temperatureUnitPreference
        )
        identity = [
            displayMode.rawValue,
            temperatureUnitPreference.rawValue,
            snapshot?.powerState.rawValue ?? "missingPowerState",
            symbolName,
            symbolTintStyle.rawValue,
            value ?? "iconOnly",
            accessibilityLabel
        ].joined(separator: "|")
    }
}

enum MenuBarBatteryLabelFormatting {
    static func displayValue(
        snapshot: BatterySnapshot?,
        displayMode: MenuBarDisplayMode,
        temperatureUnitPreference: TemperatureUnitPreference
    ) -> String? {
        switch displayMode {
        case .iconOnly:
            return nil
        case .iconAndPercentage:
            return BatteryWidgetMetricFormatting.percentText(snapshot?.presentationStateOfChargePercent)
        case .iconAndTimeRemaining:
            return BatteryFormatting.compactWidgetDuration(minutes: snapshot?.displayedTimeMinutes)
        case .iconAndHealth:
            return BatteryWidgetMetricFormatting.percentText(snapshot?.presentationHealthPercent)
        case .iconAndFullCharge:
            return abbreviatedCapacity(snapshot?.fullChargeCapacityMilliampHours)
        case .iconAndTemperature:
            return abbreviatedTemperature(snapshot?.presentationTemperatureCelsius, unitPreference: temperatureUnitPreference)
        case .iconAndPower:
            return abbreviatedPower(for: snapshot)
        }
    }

    static func accessibilityLabel(
        snapshot: BatterySnapshot?,
        displayMode: MenuBarDisplayMode,
        temperatureUnitPreference: TemperatureUnitPreference
    ) -> String {
        switch displayMode {
        case .iconOnly:
            return snapshot?.statusDisplayTitle ?? "Battery status unavailable"
        case .iconAndPercentage:
            return "Battery \(BatteryFormatting.percent(snapshot?.presentationStateOfChargePercent))"
        case .iconAndTimeRemaining:
            return "Battery time \(BatteryFormatting.duration(minutes: snapshot?.displayedTimeMinutes))"
        case .iconAndHealth:
            return "Battery health \(BatteryFormatting.percent(snapshot?.presentationHealthPercent, decimals: 0))"
        case .iconAndFullCharge:
            return "Battery full charge capacity \(BatteryFormatting.milliampHours(snapshot?.fullChargeCapacityMilliampHours, allowsZero: false))"
        case .iconAndTemperature:
            return "Battery temperature \(BatteryFormatting.temperature(snapshot?.presentationTemperatureCelsius, unitPreference: temperatureUnitPreference))"
        case .iconAndPower:
            return powerAccessibilityLabel(for: snapshot)
        }
    }

    private static func abbreviatedCapacity(_ milliampHours: Int?) -> String {
        guard let milliampHours = BatteryCalculations.plausibleCapacityMilliampHours(milliampHours, allowsZero: false) else {
            return "—"
        }

        let ampHours = Double(milliampHours) / 1_000
        return "\(ampHours.formatted(.number.precision(.fractionLength(1))))Ah"
    }

    private static func abbreviatedTemperature(_ celsius: Double?, unitPreference: TemperatureUnitPreference) -> String {
        guard let celsius = BatteryCalculations.plausibleTemperatureCelsius(celsius) else {
            return "—"
        }

        let value: Double
        switch unitPreference.resolvedUnit {
        case .celsius:
            value = celsius
        case .fahrenheit:
            value = (celsius * 9 / 5) + 32
        }

        return "\(value.formatted(.number.precision(.fractionLength(0))))°"
    }

    private static func abbreviatedPower(for snapshot: BatterySnapshot?) -> String {
        guard let snapshot,
              let watts = BatteryCalculations.plausibleWatts(snapshot.activePowerWatts) else {
            return "—"
        }

        let powerText = "\(watts.formatted(.number.precision(.fractionLength(1))))W"
        return BatteryPowerDisplayRole.role(for: snapshot) == .inputPower ? "In \(powerText)" : powerText
    }

    private static func powerAccessibilityLabel(for snapshot: BatterySnapshot?) -> String {
        let powerText = BatteryFormatting.watts(snapshot?.activePowerWatts)
        guard let snapshot else {
            return "Battery power \(powerText)"
        }

        let role = BatteryPowerDisplayRole.role(for: snapshot)
        let suffix = role == .inputPower && snapshot.powerState == .connectedDischarging
            ? ", battery discharging"
            : ""
        return "Battery \(role.accessibilityNoun) \(powerText)\(suffix)"
    }
}

#Preview {
    MenuBarBatteryView(monitor: {
        let monitor = BatteryMonitor()
        monitor.availabilityState = .available
        monitor.snapshot = .previewDischarging
        return monitor
    }(), preferences: PreferencesStore(), historyStore: BatteryHistoryStore())
}
