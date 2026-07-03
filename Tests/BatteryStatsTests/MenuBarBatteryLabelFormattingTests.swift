import AppKit
import XCTest
@testable import BatteryStats

final class MenuBarBatteryLabelFormattingTests: XCTestCase {
    @MainActor
    func testLabelStateReadsCurrentSharedPreferences() {
        let preferences = makePreferencesFixture("MenuBarBatteryLabelStateTests").preferences
        let monitor = BatteryMonitor()
        monitor.snapshot = .previewDischarging

        let percentage = MenuBarBatteryLabelState(
            snapshot: monitor.snapshot,
            preferences: preferences
        )

        XCTAssertEqual(percentage.value, "92%")

        preferences.menuBarDisplayMode = .iconOnly

        let iconOnly = MenuBarBatteryLabelState(
            snapshot: monitor.snapshot,
            preferences: preferences
        )

        XCTAssertNil(iconOnly.value)

        preferences.menuBarDisplayMode = .iconAndPower

        let power = MenuBarBatteryLabelState(
            snapshot: monitor.snapshot,
            preferences: preferences
        )

        XCTAssertEqual(power.value, "13.9W")
        XCTAssertNotEqual(percentage.identity, iconOnly.identity)
        XCTAssertNotEqual(iconOnly.identity, power.identity)
    }

    @MainActor
    func testLabelStateRecomputesFromCurrentDisplayPreferences() {
        let preferences = makePreferencesFixture("MenuBarBatteryLabelFormattingTests").preferences
        preferences.menuBarDisplayMode = .iconOnly
        preferences.temperatureUnitPreference = .fahrenheit

        let iconOnly = MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            preferences: preferences
        )

        preferences.menuBarDisplayMode = .iconAndPower

        let power = MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            preferences: preferences
        )

        XCTAssertNil(iconOnly.value)
        XCTAssertEqual(power.value, "13.9W")
        XCTAssertNotEqual(iconOnly.identity, power.identity)
    }

    func testDisplayValueUsesSelectedTemperatureUnit() {
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: .previewDischarging,
                displayMode: .iconAndTemperature,
                temperatureUnitPreference: .celsius
            ),
            "34°"
        )

        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: .previewDischarging,
                displayMode: .iconAndTemperature,
                temperatureUnitPreference: .fahrenheit
            ),
            "94°"
        )
    }

    func testMenuPanelPresentationDoesNotScheduleDuplicateVisibleSurfaceRefresh() throws {
        let menuBarSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/MenuBarBatteryView.swift")

        XCTAssertTrue(menuBarSource.contains("private func showPanel(relativeTo button: NSStatusBarButton)"))
        XCTAssertFalse(menuBarSource.contains("lastPanelShowDate = Date()\n        monitor.refreshForVisibleSurface()"))
    }

    func testAppInstallsExplicitStatusItemForDisplayPreferenceChanges() throws {
        let appSource = try Self.loadSource(relativePath: "BatteryStats/App/BatteryStatsApp.swift")
        let appCommandsSource = try Self.loadSource(relativePath: "BatteryStats/App/AppCommands.swift")
        let menuBarSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/MenuBarBatteryView.swift")
        let preferencesSource = try Self.loadSource(relativePath: "BatteryStats/Settings/PreferencesStore.swift")
        let settingsSource = try Self.loadSource(relativePath: "BatteryStats/Settings/SettingsView.swift")
        let windowSpaceBehaviorSource = try Self.loadSource(relativePath: "BatteryStats/Shared/Utilities/BatteryWindowSpaceBehavior.swift")

        XCTAssertTrue(appSource.contains("@Observable\nprivate final class BatteryStatsAppRuntime"))
        XCTAssertTrue(appSource.contains("WindowGroup(\"BatteryStats\", id: \"main\")"))
        XCTAssertTrue(appSource.contains(".defaultLaunchBehavior(.presented)"))
        XCTAssertFalse(appSource.contains("private let mainWindowController = MainBatteryWindowController()"))
        XCTAssertFalse(appSource.contains("forName: .showBatteryStatsMainWindow"))
        XCTAssertFalse(appSource.contains("BatteryStatsAppRuntime.shared.showMainWindow()"))
        XCTAssertFalse(appSource.contains("func showMainWindow()"))
        XCTAssertFalse(appSource.contains("private final class MainBatteryWindowController"))
        XCTAssertTrue(appSource.contains("private let settingsWindowController = SettingsWindowController()"))
        XCTAssertTrue(appSource.contains("forName: .showBatteryStatsSettingsWindow"))
        XCTAssertTrue(appSource.contains("func showSettingsWindow()"))
        XCTAssertTrue(appSource.contains("private final class SettingsWindowController"))
        XCTAssertTrue(appSource.contains("BatteryWindowSpaceBehavior.applyActiveSpacePresentation(to: window)"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains("enum BatteryWindowSpaceBehavior"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains("static let activeSpacePresentation: NSWindow.CollectionBehavior"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains("static let menuBarPanelPresentation: NSWindow.CollectionBehavior"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains("behavior.remove(.canJoinAllSpaces)"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".canJoinAllApplications"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".fullScreenAuxiliary"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".moveToActiveSpace"))
        XCTAssertTrue(appSource.contains("installMenuBarStatusItem()"))
        XCTAssertTrue(appSource.contains("MenuBarStatusItemController("))
        XCTAssertTrue(appSource.contains("private let monitorConfigurationObserver: BatteryMonitorConfigurationObserver"))
        XCTAssertTrue(appSource.contains("monitorConfigurationObserver.start()"))
        XCTAssertTrue(appSource.contains("monitor.refreshForVisibleSurface()"))
        XCTAssertTrue(appSource.contains("@State private var isVisibleSurfaceMonitoringActive = false"))
        XCTAssertTrue(appSource.contains("if isVisibleSurfaceMonitoringActive == false"))
        XCTAssertTrue(appSource.contains("isVisibleSurfaceMonitoringActive = true\n                        monitor.beginVisibleSurfaceMonitoring()"))
        XCTAssertTrue(appSource.contains("isVisibleSurfaceMonitoringActive = false\n                    monitor.endVisibleSurfaceMonitoring()"))
        XCTAssertTrue(appSource.contains("withObservationTracking"))
        XCTAssertFalse(appSource.contains("BatteryStatsAppRuntime.shared.startMonitoring()\n        NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertFalse(appSource.contains(".onChange(of: preferences.refreshPolicy)"))
        XCTAssertFalse(appSource.contains(".onChange(of: preferences.historyPolicy)"))
        XCTAssertFalse(appSource.contains(".onChange(of: preferences.alertPolicy)"))
        XCTAssertFalse(appSource.contains(".onChange(of: preferences.monitoringDemand)"))
        XCTAssertFalse(appSource.contains("MenuBarExtra"))
        XCTAssertFalse(appCommandsSource.contains("static let showBatteryStatsMainWindow"))
        XCTAssertTrue(appCommandsSource.contains("static let showBatteryStatsSettingsWindow"))
        XCTAssertTrue(appCommandsSource.contains("@Environment(\\.openWindow)"))
        XCTAssertTrue(appCommandsSource.contains("openWindow(id: \"main\")"))
        XCTAssertTrue(appCommandsSource.contains("CommandGroup(replacing: .appSettings)"))
        XCTAssertFalse(appCommandsSource.contains("NotificationCenter.default.post(name: .showBatteryStatsMainWindow"))
        XCTAssertTrue(appCommandsSource.contains("NotificationCenter.default.post(name: .showBatteryStatsSettingsWindow"))
        XCTAssertTrue(appCommandsSource.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(menuBarSource.contains("final class MenuBarStatusItemController: NSObject"))
        XCTAssertTrue(menuBarSource.contains("prepareForSettingsAction()"))
        XCTAssertTrue(menuBarSource.contains("openSettingsAction()"))
        XCTAssertTrue(menuBarSource.contains("NotificationCenter.default.post(name: .showBatteryStatsSettingsWindow"))
        XCTAssertFalse(menuBarSource.contains("@Environment(\\.openSettings)"))
        XCTAssertFalse(menuBarSource.contains("openSettings()"))
        XCTAssertFalse(menuBarSource.contains("showSettingsWindow"))
        XCTAssertTrue(menuBarSource.contains("let image = statusImage(systemName: content.symbolName)"))
        XCTAssertTrue(menuBarSource.contains("?? NSImage(systemSymbolName: \"questionmark\", accessibilityDescription: nil)"))
        XCTAssertFalse(menuBarSource.contains("?? NSImage(systemSymbolName: \"battery.100\", accessibilityDescription: nil)"))
        XCTAssertTrue(menuBarSource.contains("button.image = nil"))
        XCTAssertTrue(menuBarSource.contains("button.image = image"))
        XCTAssertTrue(menuBarSource.contains("button.title = content.title"))
        XCTAssertTrue(menuBarSource.contains("button.invalidateIntrinsicContentSize()"))
        XCTAssertTrue(menuBarSource.contains("button.needsDisplay = true"))
        XCTAssertFalse(menuBarSource.contains("button.sizeToFit()"))
        XCTAssertTrue(menuBarSource.contains("@discardableResult"))
        XCTAssertTrue(menuBarSource.contains("private let statusBar: NSStatusBar"))
        XCTAssertTrue(menuBarSource.contains("self.statusBar = statusBar"))
        XCTAssertTrue(menuBarSource.contains("private var isStarted = false"))
        XCTAssertTrue(menuBarSource.contains("guard isStarted == false else {\n            return\n        }\n\n        isStarted = true"))
        XCTAssertTrue(menuBarSource.contains("statusBar.removeStatusItem(statusItem)"))
        XCTAssertTrue(menuBarSource.contains("reinstallStatusItemForDisplayPreferenceChange()"))
        XCTAssertTrue(menuBarSource.contains("if MenuBarStatusItemRenderer.apply(content, to: statusItem)"))
        XCTAssertTrue(menuBarSource.contains("_ = preferences.menuBarDisplayMode"))
        XCTAssertTrue(menuBarSource.contains("_ = preferences.temperatureUnitPreference"))
        XCTAssertTrue(menuBarSource.contains("_ = preferences.temperatureUnitResolutionToken"))
        XCTAssertTrue(menuBarSource.contains("forName: .menuBarDisplayPreferencesDidChange"))
        XCTAssertTrue(menuBarSource.contains("object: nil"))
        XCTAssertTrue(menuBarSource.contains("let invalidation = MenuBarDisplayPreferencesInvalidation(notification: notification)"))
        XCTAssertTrue(menuBarSource.contains("preferences.shouldAcceptMenuBarDisplayPreferencesInvalidation(invalidation)"))
        XCTAssertTrue(menuBarSource.contains("preferences.refreshMenuBarDisplayPreferences(from: invalidation.displayPreferences)"))
        XCTAssertFalse(menuBarSource.contains("MenuBarBatteryLabelModel"))
        XCTAssertFalse(menuBarSource.contains("labelModel.stateDidChange"))
        XCTAssertTrue(menuBarSource.contains("applyCurrentStatusItemState()"))
        XCTAssertTrue(menuBarSource.contains("observeStatusItemInputs()"))
        XCTAssertTrue(menuBarSource.contains("observeDisplayPreferenceNotifications()"))
        XCTAssertTrue(menuBarSource.contains("MenuBarStatusItemRenderer.apply(content, to: statusItem)"))
        XCTAssertTrue(menuBarSource.contains("button.sendAction(on: [.leftMouseDown, .rightMouseDown])"))
        XCTAssertFalse(menuBarSource.contains("button.sendAction(on: [.leftMouseUp, .rightMouseUp])"))
        XCTAssertFalse(menuBarSource.contains("private let popover: NSPopover"))
        XCTAssertFalse(menuBarSource.contains("popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)"))
        XCTAssertFalse(menuBarSource.contains("popoverWindowConfigurationTask"))
        XCTAssertFalse(menuBarSource.contains("scheduleShownPopoverWindowConfiguration()"))
        XCTAssertFalse(menuBarSource.contains("configureShownPopoverWindow()"))
        XCTAssertTrue(menuBarSource.contains("private var panel: NSPanel?"))
        XCTAssertTrue(menuBarSource.contains("private static let panelGlobalDismissalGrace: TimeInterval"))
        XCTAssertFalse(menuBarSource.contains("private static let panelCollectionBehavior: NSWindow.CollectionBehavior"))
        XCTAssertTrue(menuBarSource.contains("BatteryWindowSpaceBehavior.menuBarPanelPresentation"))
        XCTAssertTrue(menuBarSource.contains("private var deferredPanelPresentationTask: Task<Void, Never>?"))
        XCTAssertTrue(menuBarSource.contains("private final class MenuBarStatusPanel: NSPanel"))
        XCTAssertFalse(menuBarSource.contains("styleMask: [.borderless]"))
        XCTAssertTrue(menuBarSource.contains("styleMask: [.borderless, .nonactivatingPanel]"))
        XCTAssertFalse(menuBarSource.contains(".canJoinAllSpaces"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".canJoinAllApplications"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".fullScreenAuxiliary"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".moveToActiveSpace"))
        XCTAssertFalse(menuBarSource.contains(".stationary"))
        XCTAssertTrue(menuBarSource.contains("BatterySurfaceLayout.menuBarPanelMinimumHeight"))
        XCTAssertFalse(menuBarSource.contains("contentView.layoutSubtreeIfNeeded()"))
        XCTAssertTrue(menuBarSource.contains("let fittingSize = contentView.fittingSize"))
        XCTAssertTrue(menuBarSource.contains("height: max(BatterySurfaceLayout.menuBarPanelMinimumHeight, fittingSize.height)"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".transient"))
        XCTAssertTrue(menuBarSource.contains("panel.level = .popUpMenu"))
        XCTAssertTrue(menuBarSource.contains("panel.isFloatingPanel = true"))
        XCTAssertTrue(menuBarSource.contains("panel.becomesKeyOnlyIfNeeded = false"))
        XCTAssertTrue(menuBarSource.contains("panel.canHide = false"))
        XCTAssertTrue(menuBarSource.contains("panel.isMovable = false"))
        XCTAssertTrue(menuBarSource.contains("panel.worksWhenModal = true"))
        XCTAssertTrue(menuBarSource.contains("preparePanelForActiveSpacePresentation(panel)"))
        XCTAssertFalse(menuBarSource.contains("attachPanel(panel, to: button.window)"))
        XCTAssertFalse(menuBarSource.contains("anchorWindow.addChildWindow(panel, ordered: .above)"))
        XCTAssertTrue(menuBarSource.contains("panel.parent?.removeChildWindow(panel)"))
        XCTAssertTrue(menuBarSource.contains("panel.collectionBehavior = BatteryWindowSpaceBehavior.menuBarPanelPresentation"))
        XCTAssertTrue(menuBarSource.contains("presentPanel(panel, relativeTo: button)"))
        XCTAssertTrue(menuBarSource.contains("scheduleDeferredPanelPresentationRetries(for: panel, relativeTo: button)"))
        XCTAssertFalse(menuBarSource.contains("panel.order(.above, relativeTo: anchorWindowNumber)"))
        XCTAssertTrue(menuBarSource.contains("panel.makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(menuBarSource.contains("panel.orderFrontRegardless()"))
        XCTAssertTrue(menuBarSource.contains("override var canBecomeKey: Bool {\n        true\n    }"))
        XCTAssertTrue(menuBarSource.contains("preparePanelForActiveSpacePresentation(panel)\n        panel.level = .popUpMenu"))
        XCTAssertFalse(menuBarSource.contains("NSApp.activate(ignoringOtherApps: true)\n        panel.level = .popUpMenu"))
        XCTAssertFalse(menuBarSource.contains("NSApp.activate()\n        panel.makeKey()"))
        XCTAssertFalse(menuBarSource.contains(".activateAllWindows"))
        XCTAssertFalse(menuBarSource.contains("panel.makeKey()\n        panel.displayIfNeeded()"))
        XCTAssertTrue(menuBarSource.contains("panel.displayIfNeeded()"))
        XCTAssertTrue(menuBarSource.contains("self.layoutPanel(panel, relativeTo: button)"))
        XCTAssertTrue(menuBarSource.contains("closePanel()\n\n        let panel = makePanel()"))
        XCTAssertTrue(menuBarSource.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertTrue(menuBarSource.contains("NSEvent.addGlobalMonitorForEvents"))
        XCTAssertTrue(menuBarSource.contains("self?.closePanelFromGlobalEventIfNeeded()"))
        XCTAssertTrue(menuBarSource.contains("private func closePanelFromGlobalEventIfNeeded(now: Date = Date())"))
        XCTAssertTrue(menuBarSource.contains("now.timeIntervalSince(lastPanelShowDate) < Self.panelGlobalDismissalGrace"))
        XCTAssertTrue(menuBarSource.contains("observeActiveSpaceChanges()"))
        XCTAssertTrue(menuBarSource.contains("NSWorkspace.activeSpaceDidChangeNotification"))
        XCTAssertTrue(menuBarSource.contains("repositionPanelForActiveSpaceChangeIfNeeded()"))
        XCTAssertTrue(menuBarSource.contains("private var lastPanelShowDate: Date?"))
        XCTAssertTrue(menuBarSource.contains("lastPanelShowDate = nil"))
        XCTAssertTrue(menuBarSource.contains("[50_000_000, 180_000_000, 450_000_000, 900_000_000]"))
        XCTAssertTrue(menuBarSource.contains("layoutPanel(panel, relativeTo: button)"))
        XCTAssertFalse(menuBarSource.contains("NSApplication.didResignActiveNotification"))
        XCTAssertTrue(preferencesSource.contains("static let menuBarDisplayPreferencesDidChange"))
        XCTAssertTrue(preferencesSource.contains("NSLocale.currentLocaleDidChangeNotification"))
        XCTAssertTrue(preferencesSource.contains("temperatureUnitResolutionToken &+="))
        XCTAssertTrue(preferencesSource.contains("func invalidateMenuBarDisplayPreferences()"))
        XCTAssertTrue(preferencesSource.contains("private func applyMenuBarDisplayDefaultsChanges() -> Bool"))
        XCTAssertTrue(settingsSource.contains("menuBarDisplayPreferenceBinding(\\.menuBarDisplayMode)"))
        XCTAssertTrue(settingsSource.contains("where Value: Equatable"))
        XCTAssertTrue(settingsSource.contains("guard preferences[keyPath: keyPath] != value else"))
        XCTAssertTrue(settingsSource.contains("preferences.invalidateMenuBarDisplayPreferences()"))
        XCTAssertFalse(settingsSource.contains("preferences[keyPath: keyPath] = value\n                preferences.invalidateMenuBarDisplayPreferences()"))
    }

    func testSettingsViewRefreshesExternalStateWhenAppBecomesActive() throws {
        let settingsSource = try Self.loadSource(relativePath: "BatteryStats/Settings/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("import AppKit"))
        XCTAssertTrue(settingsSource.contains("refreshExternalSettingsState()"))
        XCTAssertTrue(settingsSource.contains("for: NSApplication.didBecomeActiveNotification"))
        XCTAssertTrue(settingsSource.contains("preferences.refreshICloudSyncAvailability()"))
        XCTAssertTrue(settingsSource.contains("refreshLaunchAtLoginState()"))
        XCTAssertTrue(settingsSource.contains("alertSettings.refreshAuthorizationStatus(preferences: preferences)"))
    }

    func testSettingsResetCancelsPendingAlertEnablesBeforeResettingPreferences() throws {
        let settingsSource = try Self.loadSource(relativePath: "BatteryStats/Settings/SettingsView.swift")
        let cancelPendingAlertsRange = try XCTUnwrap(settingsSource.range(of: "alertSettings.cancelPendingAlertEnables()"))
        let resetPreferencesRange = try XCTUnwrap(settingsSource.range(of: "preferences.reset()"))

        XCTAssertLessThan(cancelPendingAlertsRange.lowerBound, resetPreferencesRange.lowerBound)
    }

    func testSettingsWindowMinimumWidthMatchesContentWidthPlusPadding() throws {
        let appSource = try Self.loadSource(relativePath: "BatteryStats/App/BatteryStatsApp.swift")
        let settingsSource = try Self.loadSource(relativePath: "BatteryStats/Settings/SettingsView.swift")

        XCTAssertEqual(SettingsLayout.contentWidth, 520)
        XCTAssertEqual(SettingsLayout.contentPadding, 20)
        XCTAssertEqual(SettingsLayout.minimumWindowWidth, 560)
        XCTAssertTrue(settingsSource.contains(".frame(width: SettingsLayout.contentWidth)"))
        XCTAssertTrue(settingsSource.contains(".frame(width: SettingsLayout.contentWidth)\n        .padding(SettingsLayout.contentPadding)"))
        XCTAssertTrue(appSource.contains("width: SettingsLayout.minimumWindowWidth"))
        XCTAssertTrue(appSource.contains("window.minSize = NSSize(width: SettingsLayout.minimumWindowWidth, height: 480)"))
        XCTAssertFalse(appSource.contains("window.minSize = NSSize(width: 520, height: 480)"))
    }

    func testSystemTemperatureUnitInvalidationKeysTemperatureRows() throws {
        let dashboardSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatterySummaryGridView.swift")
        let historySource = try Self.loadSource(relativePath: "BatteryStats/Settings/HistoryStatsView.swift")
        let settingsSource = try Self.loadSource(relativePath: "BatteryStats/Settings/SettingsView.swift")

        XCTAssertTrue(dashboardSource.contains(".id(temperatureUnitResolutionToken)"))
        XCTAssertTrue(historySource.contains(".id(unitResolutionToken)"))
        XCTAssertTrue(settingsSource.contains("unitResolutionToken: preferences.temperatureUnitResolutionToken"))
    }

    func testAdvancedBatteryAgeLabelClarifiesManufactureAge() throws {
        let dashboardSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatterySummaryGridView.swift")

        XCTAssertTrue(dashboardSource.contains("BatteryDetailRowView(title: \"Made\", value: manufactureDate)"))
        XCTAssertTrue(dashboardSource.contains("BatteryDetailRowView(title: \"Age\", value: age)"))
        XCTAssertFalse(dashboardSource.contains("BatteryDetailRowView(title: \"Since Made\", value: age)"))
    }

    func testUnsupportedBatteryViewDoesNotUseEmptyBatteryIcon() throws {
        let unsupportedSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/UnsupportedBatteryView.swift")

        XCTAssertTrue(unsupportedSource.contains("systemImage: \"questionmark.circle\""))
        XCTAssertFalse(unsupportedSource.contains("systemImage: \"battery.0\""))
    }

    func testMainWindowUsesNativeWindowGroupForLaunchAndOpenCommand() throws {
        let appSource = try Self.loadSource(relativePath: "BatteryStats/App/BatteryStatsApp.swift")
        let appCommandsSource = try Self.loadSource(relativePath: "BatteryStats/App/AppCommands.swift")

        XCTAssertTrue(appSource.contains("WindowGroup(\"BatteryStats\", id: \"main\")"))
        XCTAssertTrue(appSource.contains(".windowResizability(.contentSize)"))
        XCTAssertTrue(appSource.contains(".defaultLaunchBehavior(.presented)"))
        XCTAssertFalse(appSource.contains("func applicationShouldHandleReopen("))
        XCTAssertFalse(appSource.contains("BatteryStatsAppRuntime.shared.showMainWindow()"))
        XCTAssertFalse(appSource.contains("private final class MainBatteryWindowController"))
        XCTAssertTrue(appCommandsSource.contains("@Environment(\\.openWindow)"))
        XCTAssertTrue(appCommandsSource.contains("openWindow(id: \"main\")"))
    }

    func testMainDashboardWindowCanMoveToCurrentFullScreenSpace() throws {
        let dashboardSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatteryDashboardView.swift")
        let windowSpaceBehaviorSource = try Self.loadSource(relativePath: "BatteryStats/Shared/Utilities/BatteryWindowSpaceBehavior.swift")

        XCTAssertTrue(dashboardSource.contains("import AppKit"))
        XCTAssertTrue(dashboardSource.contains(".background(BatteryDashboardWindowObserver(isLightningRefreshEnabled: $isLightningRefreshEnabled))"))
        XCTAssertTrue(dashboardSource.contains("NSViewRepresentable"))
        XCTAssertTrue(dashboardSource.contains("windowLookupRetryDelays"))
        XCTAssertTrue(dashboardSource.contains("Task { @MainActor"))
        XCTAssertTrue(dashboardSource.contains("Task.sleep"))
        XCTAssertTrue(dashboardSource.contains("BatteryWindowSpaceBehavior.applyActiveSpacePresentation(to: window)"))
        XCTAssertFalse(dashboardSource.contains("configure(_ window: NSWindow)"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains("behavior.remove(.canJoinAllSpaces)"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".canJoinAllApplications"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".fullScreenAuxiliary"))
        XCTAssertTrue(windowSpaceBehaviorSource.contains(".moveToActiveSpace"))
    }

    func testDashboardLightningRefreshIsFocusBound() throws {
        let dashboardSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatteryDashboardView.swift")
        let monitorSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Data/BatteryMonitor.swift")

        XCTAssertTrue(dashboardSource.contains("showsLightningRefreshButton: true"))
        XCTAssertTrue(dashboardSource.contains("LightningRefreshButton"))
        XCTAssertTrue(dashboardSource.contains("Image(systemName: isEnabled ? \"bolt.fill\" : \"bolt\")"))
        XCTAssertTrue(dashboardSource.contains("BatteryDashboardWindowObserver"))
        XCTAssertTrue(dashboardSource.contains("NSWindow.didResignKeyNotification"))
        XCTAssertTrue(dashboardSource.contains("NSWindow.didMiniaturizeNotification"))
        XCTAssertTrue(dashboardSource.contains("NSWindow.willCloseNotification"))
        XCTAssertTrue(dashboardSource.contains("NSApplication.didResignActiveNotification"))
        XCTAssertTrue(dashboardSource.contains("monitor.setLightningRefreshActive(isEnabled)"))
        XCTAssertTrue(dashboardSource.contains(".onDisappear"))
        XCTAssertTrue(monitorSource.contains("var isLightningRefreshActive = false"))
        XCTAssertTrue(monitorSource.contains("func setLightningRefreshActive(_ isActive: Bool)"))
    }

    func testMenuBarPanelFallbackLayoutStaysOnActiveScreenNearClick() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = MenuBarPanelLayout.fallbackFrame(
            size: NSSize(width: 260, height: 320),
            near: NSPoint(x: 1_380, y: 890),
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame.size, NSSize(width: 260, height: 320))
        XCTAssertLessThanOrEqual(frame.maxX, screenFrame.maxX - MenuBarPanelLayout.margin)
        XCTAssertGreaterThanOrEqual(frame.minX, screenFrame.minX + MenuBarPanelLayout.margin)
        XCTAssertLessThanOrEqual(frame.maxY, screenFrame.maxY - MenuBarPanelLayout.margin)
        XCTAssertGreaterThanOrEqual(frame.minY, screenFrame.minY + MenuBarPanelLayout.margin)
        XCTAssertGreaterThan(frame.midX, 1_250)
    }

    func testMenuBarPanelButtonLayoutFlipsAboveWhenThereIsNoRoomBelow() {
        let screenFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let anchor = NSRect(x: 300, y: 8, width: 22, height: 18)
        let frame = MenuBarPanelLayout.frame(
            size: NSSize(width: 260, height: 220),
            anchoredTo: anchor,
            screenFrame: screenFrame
        )

        XCTAssertGreaterThanOrEqual(frame.minY, anchor.maxY)
        XCTAssertGreaterThanOrEqual(frame.minY, screenFrame.minY + MenuBarPanelLayout.margin)
        XCTAssertLessThanOrEqual(frame.maxY, screenFrame.maxY - MenuBarPanelLayout.margin)
    }

    @MainActor
    func testMenuBarPanelPresentationUsesFullScreenAuxiliaryNonActivatingWindow() throws {
        let controller = makeStatusItemControllerFixture("MenuBarPanelPresentationTests").controller
        controller.showPanelForTesting()
        defer {
            controller.closePanelForTesting()
        }

        let panel = try XCTUnwrap(controller.currentPanelSnapshotForTesting())
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.level, .popUpMenu)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundAlpha, 0)
        XCTAssertEqual(panel.contentViewClassName, "NSVisualEffectView")
        XCTAssertEqual(panel.contentViewCornerRadius, BatterySurfaceLayout.menuBarPanelCornerRadius)
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }

    @MainActor
    func testMenuBarPanelOutsideClickDuringOpeningGraceStillDismissesAfterGrace() async throws {
        let controller = makeStatusItemControllerFixture("MenuBarPanelDismissalGraceTests").controller
        controller.showPanelForTesting()
        defer {
            controller.closePanelForTesting()
        }

        let shownAt = Date(timeIntervalSinceReferenceDate: 1_000)
        controller.overwriteLastPanelShowDateForTesting(shownAt)
        controller.closePanelFromGlobalEventForTesting(now: shownAt.addingTimeInterval(1.20))

        XCTAssertTrue(try XCTUnwrap(controller.currentPanelSnapshotForTesting()).isVisible)

        try? await Task.sleep(nanoseconds: 180_000_000)
        await Self.drainObservationUpdates()

        XCTAssertNil(controller.currentPanelSnapshotForTesting())
    }

    @MainActor
    func testMenuBarPanelInsideInteractionCancelsDeferredDismissal() async throws {
        let controller = makeStatusItemControllerFixture("MenuBarPanelDismissalCancellationTests").controller
        controller.showPanelForTesting()
        defer {
            controller.closePanelForTesting()
        }

        let shownAt = Date(timeIntervalSinceReferenceDate: 1_000)
        controller.overwriteLastPanelShowDateForTesting(shownAt)
        controller.closePanelFromGlobalEventForTesting(now: shownAt.addingTimeInterval(1.20))
        controller.cancelDeferredPanelDismissalForTesting()

        try? await Task.sleep(nanoseconds: 180_000_000)
        await Self.drainObservationUpdates()

        XCTAssertTrue(try XCTUnwrap(controller.currentPanelSnapshotForTesting()).isVisible)
    }

    @MainActor
    func testStatusItemRendererAppliesSelectedDisplayModeToAppKitButton() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        let percentage = MenuBarStatusItemContent(state: MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconAndPercentage,
            temperatureUnitPreference: .celsius
        ))
        XCTAssertTrue(MenuBarStatusItemRenderer.apply(percentage, to: statusItem))

        XCTAssertEqual(statusItem.button?.title, "92%")
        XCTAssertEqual(statusItem.button?.attributedTitle.string, "92%")
        XCTAssertEqual(statusItem.button?.imagePosition, .imageLeft)
        XCTAssertEqual(statusItem.length, NSStatusItem.variableLength)
        XCTAssertEqual(statusItem.button?.toolTip, "Battery 92%")
        XCTAssertTrue(statusItem.button?.image?.isTemplate == true)
        XCTAssertNil(statusItem.button?.contentTintColor)

        statusItem.button?.title = "stale title"
        statusItem.button?.alternateTitle = "stale alternate"
        statusItem.button?.attributedTitle = NSAttributedString(string: "stale attributed title")
        statusItem.button?.imagePosition = .imageRight

        let iconOnly = MenuBarStatusItemContent(state: MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        ))
        XCTAssertTrue(MenuBarStatusItemRenderer.apply(iconOnly, to: statusItem))

        XCTAssertEqual(statusItem.button?.title, "")
        XCTAssertEqual(statusItem.button?.alternateTitle, "")
        XCTAssertEqual(statusItem.button?.attributedTitle.string, "")
        XCTAssertEqual(statusItem.button?.imagePosition, .imageOnly)
        XCTAssertEqual(statusItem.length, NSStatusItem.squareLength)
        XCTAssertTrue(statusItem.button?.image?.isTemplate == true)
        XCTAssertNil(statusItem.button?.contentTintColor)

        let power = MenuBarStatusItemContent(state: MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconAndPower,
            temperatureUnitPreference: .celsius
        ))
        XCTAssertTrue(MenuBarStatusItemRenderer.apply(power, to: statusItem))

        XCTAssertEqual(statusItem.button?.title, "13.9W")
        XCTAssertEqual(statusItem.button?.attributedTitle.string, "13.9W")
        XCTAssertEqual(statusItem.button?.imagePosition, .imageLeft)
        XCTAssertEqual(statusItem.length, NSStatusItem.variableLength)
        XCTAssertEqual(statusItem.button?.toolTip, "Battery power 13.9 W")
        XCTAssertTrue(statusItem.button?.image?.isTemplate == true)
        XCTAssertNil(statusItem.button?.contentTintColor)
    }

    @MainActor
    func testStatusItemRendererKeepsTemplateImageAdaptiveInsideSameSymbolBucket() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        let green = MenuBarStatusItemContent(state: MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .onBattery, stateOfChargePercent: 40),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        ))
        let yellow = MenuBarStatusItemContent(state: MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .onBattery, stateOfChargePercent: 39),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        ))

        XCTAssertEqual(green.symbolName, yellow.symbolName)

        XCTAssertTrue(MenuBarStatusItemRenderer.apply(green, to: statusItem))
        XCTAssertTrue(statusItem.button?.image?.isTemplate == true)
        XCTAssertNil(statusItem.button?.contentTintColor)

        XCTAssertTrue(MenuBarStatusItemRenderer.apply(yellow, to: statusItem))
        XCTAssertTrue(statusItem.button?.image?.isTemplate == true)
        XCTAssertNil(statusItem.button?.contentTintColor)
    }

    @MainActor
    func testStatusItemControllerRepaintsAppKitButtonWhenPreferencesChange() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemControllerTests")
        let preferences = fixture.preferences
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().attributedTitle, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)

        preferences.menuBarDisplayMode = .iconOnly
        await Self.drainObservationUpdates()

        XCTAssertEqual(controller.currentButtonSnapshot().title, "")
        XCTAssertEqual(controller.currentButtonSnapshot().attributedTitle, "")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().length, NSStatusItem.squareLength)

        preferences.menuBarDisplayMode = .iconAndPower
        await Self.drainObservationUpdates()

        XCTAssertEqual(controller.currentButtonSnapshot().title, "13.9W")
        XCTAssertEqual(controller.currentButtonSnapshot().attributedTitle, "13.9W")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().length, NSStatusItem.variableLength)
        XCTAssertEqual(controller.currentButtonSnapshot().toolTip, "Battery power 13.9 W")
    }

    @MainActor
    func testStatusItemControllerReinstallsStatusItemWhenDisplayPreferencesChange() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemControllerReinstallTests")
        let preferences = fixture.preferences
        let controller = fixture.controller

        let initialStatusItem = controller.currentStatusItemIdentityForTesting()
        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        preferences.menuBarDisplayMode = .iconOnly
        await Self.drainObservationUpdates()

        let iconOnlyStatusItem = controller.currentStatusItemIdentityForTesting()
        XCTAssertNotEqual(initialStatusItem, iconOnlyStatusItem)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageOnly)

        preferences.menuBarDisplayMode = .iconAndPower
        await Self.drainObservationUpdates()

        XCTAssertNotEqual(iconOnlyStatusItem, controller.currentStatusItemIdentityForTesting())
        XCTAssertEqual(controller.currentButtonSnapshot().title, "13.9W")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
    }

    @MainActor
    func testStatusItemControllerRepaintsWhenDisplayDefaultsChangeOutsideStore() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemControllerDefaultsTests")
        let defaults = fixture.defaults
        let preferences = fixture.preferences
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)

        defaults.set(MenuBarDisplayMode.iconOnly.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        await Self.drainObservationUpdates()

        XCTAssertEqual(preferences.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().length, NSStatusItem.squareLength)

        defaults.set(MenuBarDisplayMode.iconAndPower.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        await Self.drainObservationUpdates()

        XCTAssertEqual(preferences.menuBarDisplayMode, .iconAndPower)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "13.9W")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().length, NSStatusItem.variableLength)
    }

    @MainActor
    func testStatusItemControllerRepaintsWhenSettingsStoreWritesSharedDefaults() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemControllerSharedDefaultsTests")
        let defaults = fixture.defaults
        let runtimePreferences = fixture.preferences
        let settingsPreferences = PreferencesStore(defaults: defaults, sync: NoopPreferencesSync())
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)

        settingsPreferences.menuBarDisplayMode = .iconOnly
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        await Self.drainObservationUpdates()

        XCTAssertEqual(runtimePreferences.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().length, NSStatusItem.squareLength)

        settingsPreferences.menuBarDisplayMode = .iconAndPower
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        await Self.drainObservationUpdates()

        XCTAssertEqual(runtimePreferences.menuBarDisplayMode, .iconAndPower)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "13.9W")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().length, NSStatusItem.variableLength)
    }

    @MainActor
    func testStatusItemControllerUsesDisplayPreferenceInvalidationPayloadBeforeDefaultsCatchUp() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemControllerInvalidationPayloadTests")
        let defaults = fixture.defaults
        let preferences = fixture.preferences
        let controller = fixture.controller

        XCTAssertEqual(preferences.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        NotificationCenter.default.post(
            name: .menuBarDisplayPreferencesDidChange,
            object: nil,
            userInfo: MenuBarDisplayPreferences(
                displayMode: .iconOnly,
                temperatureUnitPreference: .system
            ).userInfo
        )
        await Self.drainObservationUpdates()

        XCTAssertEqual(preferences.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().length, NSStatusItem.squareLength)
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey), MenuBarDisplayMode.iconOnly.rawValue)
    }

    @MainActor
    func testDisplayPreferenceInvalidationForcesStatusItemRepaint() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemForcedRepaintTests")
        let preferences = fixture.preferences
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        controller.overwriteButtonTitleForTesting("stale")
        preferences.invalidateMenuBarDisplayPreferences()
        await Self.drainObservationUpdates()

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().toolTip, "Battery 92%")
    }

    @MainActor
    func testResetSettingsForcesStatusItemRepaintEvenWhenDisplayPreferencesRemainDefault() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemResetRepaintTests")
        let preferences = fixture.preferences
        let controller = fixture.controller

        XCTAssertEqual(preferences.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        controller.overwriteButtonTitleForTesting("stale")
        preferences.reset()
        await Self.drainObservationUpdates()

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().toolTip, "Battery 92%")
    }

    @MainActor
    func testSameDisplayPreferenceInvalidationRepaintsWithoutReplacingStatusItemOrClosingPanel() async throws {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemSamePreferenceInvalidationTests")
        let preferences = fixture.preferences
        let controller = fixture.controller
        controller.showPanelForTesting()
        defer {
            controller.closePanelForTesting()
        }

        let initialStatusItem = controller.currentStatusItemIdentityForTesting()
        XCTAssertTrue(try XCTUnwrap(controller.currentPanelSnapshotForTesting()).isVisible)

        controller.overwriteButtonTitleForTesting("stale")
        preferences.invalidateMenuBarDisplayPreferences()
        await Self.drainObservationUpdates()

        XCTAssertEqual(controller.currentStatusItemIdentityForTesting(), initialStatusItem)
        XCTAssertTrue(try XCTUnwrap(controller.currentPanelSnapshotForTesting()).isVisible)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().toolTip, "Battery 92%")
    }

    @MainActor
    func testDisplayPreferenceInvalidationFromSiblingStoreForcesStatusItemRepaint() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemSiblingInvalidationTests")
        let settingsPreferences = PreferencesStore(defaults: fixture.defaults, sync: NoopPreferencesSync())
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        controller.overwriteButtonTitleForTesting("stale")
        settingsPreferences.invalidateMenuBarDisplayPreferences()
        await Self.drainObservationUpdates()

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().toolTip, "Battery 92%")
    }

    @MainActor
    func testDisplayPreferenceInvalidationFromSameDefaultsSuiteForcesStatusItemRepaint() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemSameSuiteInvalidationTests")
        let settingsDefaults = UserDefaults(suiteName: fixture.suiteName)!
        let runtimePreferences = fixture.preferences
        let settingsPreferences = PreferencesStore(defaults: settingsDefaults, sync: NoopPreferencesSync())
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        settingsPreferences.menuBarDisplayMode = .iconOnly
        await Self.drainObservationUpdates()

        XCTAssertEqual(runtimePreferences.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageOnly)
        XCTAssertEqual(controller.currentButtonSnapshot().length, NSStatusItem.squareLength)
    }

    @MainActor
    func testDisplayPreferenceInvalidationFromUnrelatedStoreDoesNotChangeStatusItem() async {
        let runtimeFixture = makeStatusItemControllerFixture("MenuBarStatusItemRuntimeInvalidationTests")
        let unrelatedPreferences = makePreferencesFixture("MenuBarStatusItemUnrelatedInvalidationTests").preferences
        let runtimePreferences = runtimeFixture.preferences
        let controller = runtimeFixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        unrelatedPreferences.menuBarDisplayMode = .iconOnly
        await Self.drainObservationUpdates()

        XCTAssertEqual(runtimePreferences.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().toolTip, "Battery 92%")
    }

    @MainActor
    func testDisplayPreferenceInvalidationRepaintsAfterPickerCommitSettles() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemDeferredInvalidationTests")
        let preferences = fixture.preferences
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        preferences.invalidateMenuBarDisplayPreferences()
        controller.overwriteButtonTitleForTesting("stale during picker commit")
        await Self.drainDeferredStatusItemRepaint()

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().toolTip, "Battery 92%")
    }

    @MainActor
    func testDisplayPreferenceInvalidationRepaintsAfterDelayedPickerCommitSettles() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemDelayedInvalidationTests")
        let preferences = fixture.preferences
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")

        preferences.invalidateMenuBarDisplayPreferences()
        try? await Task.sleep(nanoseconds: 60_000_000)
        controller.overwriteButtonTitleForTesting("stale after picker commit")
        await Self.drainDelayedStatusItemRepaint()

        XCTAssertEqual(controller.currentButtonSnapshot().title, "92%")
        XCTAssertEqual(controller.currentButtonSnapshot().imagePosition, .imageLeft)
        XCTAssertEqual(controller.currentButtonSnapshot().toolTip, "Battery 92%")
    }

    @MainActor
    func testStatusItemControllerTracksTemperatureUnitPreferenceChanges() async {
        let fixture = makeStatusItemControllerFixture("MenuBarStatusItemTemperatureUnitTests") { preferences, _ in
            preferences.menuBarDisplayMode = .iconAndTemperature
            preferences.temperatureUnitPreference = .celsius
        }
        let preferences = fixture.preferences
        let controller = fixture.controller

        XCTAssertEqual(controller.currentButtonSnapshot().title, "34°")

        preferences.temperatureUnitPreference = .fahrenheit
        await Self.drainObservationUpdates()

        XCTAssertEqual(controller.currentButtonSnapshot().title, "94°")
    }

    func testAccessibilityLabelUsesSelectedTemperatureUnit() {
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.accessibilityLabel(
                snapshot: .previewDischarging,
                displayMode: .iconAndTemperature,
                temperatureUnitPreference: .fahrenheit
            ),
            "Battery temperature 93.6 °F"
        )
    }

    func testIconOnlyHasNoDisplayValue() {
        XCTAssertNil(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: .previewDischarging,
                displayMode: .iconOnly,
                temperatureUnitPreference: .celsius
            )
        )
    }

    func testDisplayValueHidesImpossibleCapacityPowerAndTemperatureValues() {
        let snapshot = BatterySnapshot(
            timestamp: .now,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: nil,
            currentChargeWattHours: nil,
            fullChargeCapacityMilliampHours: Int.max,
            fullChargeCapacityWattHours: nil,
            designCapacityMilliampHours: nil,
            designCapacityWattHours: nil,
            healthPercent: nil,
            stateOfChargePercent: 50,
            voltageMillivolts: nil,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: .greatestFiniteMagnitude,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: nil,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 180,
            adapterMaxWatts: nil,
            notes: []
        )

        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: snapshot,
                displayMode: .iconAndFullCharge,
                temperatureUnitPreference: .celsius
            ),
            "—"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ),
            "—"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: snapshot,
                displayMode: .iconAndTemperature,
                temperatureUnitPreference: .celsius
            ),
            "—"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.accessibilityLabel(
                snapshot: snapshot,
                displayMode: .iconAndTemperature,
                temperatureUnitPreference: .celsius
            ),
            "Battery temperature Unavailable"
        )
    }

    func testDisplayValueHidesZeroFullChargeCapacity() {
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            stateOfChargePercent: 50,
            fullChargeCapacityMilliampHours: 0
        )

        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: snapshot,
                displayMode: .iconAndFullCharge,
                temperatureUnitPreference: .celsius
            ),
            "—"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.accessibilityLabel(
                snapshot: snapshot,
                displayMode: .iconAndFullCharge,
                temperatureUnitPreference: .celsius
            ),
            "Battery full charge capacity Unavailable"
        )
    }

    func testLabelStateIdentityChangesWithDisplayMode() {
        let iconOnly = MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )
        let percentage = MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconAndPercentage,
            temperatureUnitPreference: .celsius
        )

        XCTAssertNil(iconOnly.value)
        XCTAssertEqual(percentage.value, "92%")
        XCTAssertNotEqual(iconOnly.identity, percentage.identity)
    }

    func testStatusItemTitleUsesSelectedDisplayValue() {
        let iconOnly = MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )
        let percentage = MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconAndPercentage,
            temperatureUnitPreference: .celsius
        )
        let power = MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconAndPower,
            temperatureUnitPreference: .celsius
        )

        XCTAssertEqual(iconOnly.statusItemTitle, "")
        XCTAssertEqual(percentage.statusItemTitle, "92%")
        XCTAssertEqual(power.statusItemTitle, "13.9W")
    }

    func testStatusItemContentTracksSelectedDisplayMode() {
        let iconOnly = MenuBarStatusItemContent(state: MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        ))
        let percentage = MenuBarStatusItemContent(state: MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconAndPercentage,
            temperatureUnitPreference: .celsius
        ))
        let power = MenuBarStatusItemContent(state: MenuBarBatteryLabelState(
            snapshot: .previewDischarging,
            displayMode: .iconAndPower,
            temperatureUnitPreference: .celsius
        ))

        XCTAssertEqual(iconOnly.title, "")
        XCTAssertEqual(iconOnly.imagePosition, .imageOnly)
        XCTAssertEqual(iconOnly.length, NSStatusItem.squareLength)
        XCTAssertEqual(percentage.title, "92%")
        XCTAssertEqual(percentage.imagePosition, .imageLeft)
        XCTAssertEqual(percentage.length, NSStatusItem.variableLength)
        XCTAssertEqual(power.title, "13.9W")
        XCTAssertEqual(power.imagePosition, .imageLeft)
        XCTAssertEqual(power.length, NSStatusItem.variableLength)
    }

    func testLabelStateIdentityChangesWithPowerStateEvenWhenTextMatches() {
        let connectedNotCharging = makeSnapshot(
            powerState: .connectedNotCharging,
            stateOfChargePercent: 100
        )
        let fullOnAC = makeSnapshot(
            powerState: .fullOnAC,
            stateOfChargePercent: 100
        )

        let connectedState = MenuBarBatteryLabelState(
            snapshot: connectedNotCharging,
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )
        let fullState = MenuBarBatteryLabelState(
            snapshot: fullOnAC,
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )

        XCTAssertEqual(connectedState.symbolName, "battery.100")
        XCTAssertEqual(fullState.symbolName, "battery.100")
        XCTAssertNil(connectedState.value)
        XCTAssertNil(fullState.value)
        XCTAssertNotEqual(connectedState.accessibilityLabel, fullState.accessibilityLabel)
        XCTAssertNotEqual(connectedState.identity, fullState.identity)
    }

    func testIconOnlyIdentityChangesWhenTintChangesInsideSameSymbolBucket() {
        let greenState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .onBattery, stateOfChargePercent: 40),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )
        let yellowState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .onBattery, stateOfChargePercent: 39),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )

        XCTAssertEqual(greenState.symbolName, yellowState.symbolName)
        XCTAssertNil(greenState.value)
        XCTAssertNil(yellowState.value)
        XCTAssertNotEqual(
            BatteryPresentationStyle.chargeTintStyle(for: makeSnapshot(powerState: .onBattery, stateOfChargePercent: 40)),
            BatteryPresentationStyle.chargeTintStyle(for: makeSnapshot(powerState: .onBattery, stateOfChargePercent: 39))
        )
        XCTAssertNotEqual(greenState.identity, yellowState.identity)
    }

    func testIconOnlyIdentityChangesWhenLowPowerStatusChangesInsideSameSymbolBucket() {
        let normalState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .onBattery, stateOfChargePercent: 21),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )
        let lowPowerState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .onBattery, stateOfChargePercent: 20),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )

        XCTAssertEqual(normalState.symbolName, lowPowerState.symbolName)
        XCTAssertNil(normalState.value)
        XCTAssertNil(lowPowerState.value)
        XCTAssertNotEqual(normalState.accessibilityLabel, lowPowerState.accessibilityLabel)
        XCTAssertNotEqual(normalState.identity, lowPowerState.identity)
    }

    func testLabelStateFallsBackToPowerStateIconWhenChargePercentIsUnavailable() {
        let chargingState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .charging, stateOfChargePercent: nil),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )
        let connectedState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .connectedNotCharging, stateOfChargePercent: nil),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )
        let fullState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .fullOnAC, stateOfChargePercent: nil),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )
        let onBatteryState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .onBattery, stateOfChargePercent: nil),
            displayMode: .iconOnly,
            temperatureUnitPreference: .celsius
        )

        XCTAssertEqual(chargingState.symbolName, "battery.100.bolt")
        XCTAssertEqual(connectedState.symbolName, "powerplug")
        XCTAssertEqual(fullState.symbolName, "battery.100")
        XCTAssertEqual(onBatteryState.symbolName, "questionmark")
    }

    func testLabelStateUsesChargeBucketIconWhenChargePercentIsAvailable() {
        let chargingState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .charging, stateOfChargePercent: 42),
            displayMode: .iconAndPercentage,
            temperatureUnitPreference: .celsius
        )
        let connectedState = MenuBarBatteryLabelState(
            snapshot: makeSnapshot(powerState: .connectedDischarging, stateOfChargePercent: 42),
            displayMode: .iconAndPercentage,
            temperatureUnitPreference: .celsius
        )

        XCTAssertEqual(chargingState.symbolName, "battery.50")
        XCTAssertEqual(chargingState.value, "42%")
        XCTAssertEqual(connectedState.symbolName, "battery.50")
        XCTAssertEqual(connectedState.value, "42%")
    }

    func testPowerDisplayValueHidesInvalidActivePower() {
        let snapshot = BatterySnapshot(
            timestamp: .now,
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 55,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 1_200,
            dischargeRateMilliamps: nil,
            chargeRateWatts: -18,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 50,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        XCTAssertNil(snapshot.activePowerWatts)
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ),
            "—"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.accessibilityLabel(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ),
            "Battery charge rate Unavailable"
        )
    }

    func testPowerDisplayValueLabelsVisibleInputPower() {
        let charging = makeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 55,
            inputPowerWatts: 39.8,
            inputPowerEvidence: .counterBacked
        )
        let connectedNotCharging = makeSnapshot(
            powerState: .connectedNotCharging,
            stateOfChargePercent: 83,
            inputPowerWatts: 27.4,
            inputPowerEvidence: .counterBacked
        )

        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: charging,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ),
            "In 39.8W"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.accessibilityLabel(
                snapshot: charging,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ),
            "Battery input power 39.8 W"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: connectedNotCharging,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ),
            "In 27.4W"
        )
    }

    @MainActor
    private static func drainObservationUpdates() async {
        await Task.yield()
        await Task.yield()
        await Task.yield()
        await Task.yield()
    }

    @MainActor
    private static func drainDeferredStatusItemRepaint() async {
        try? await Task.sleep(nanoseconds: 50_000_000)
        await drainObservationUpdates()
    }

    @MainActor
    private static func drainDelayedStatusItemRepaint() async {
        try? await Task.sleep(nanoseconds: 450_000_000)
        await drainObservationUpdates()
    }

    @MainActor
    private func makeStatusItemControllerFixture(
        _ suitePrefix: String,
        configure: (PreferencesStore, BatteryMonitor) -> Void = { _, _ in }
    ) -> MenuBarStatusItemControllerFixture {
        let preferencesFixture = makePreferencesFixture(suitePrefix)
        let preferences = preferencesFixture.preferences
        let monitor = BatteryMonitor()
        monitor.snapshot = .previewDischarging
        configure(preferences, monitor)
        let controller = MenuBarStatusItemController(
            monitor: monitor,
            preferences: preferences,
            historyStore: BatteryHistoryStore()
        )
        controller.start()

        return MenuBarStatusItemControllerFixture(
            suiteName: preferencesFixture.suiteName,
            defaults: preferencesFixture.defaults,
            preferences: preferences,
            controller: controller
        )
    }

    @MainActor
    private func makePreferencesFixture(_ suitePrefix: String) -> PreferencesFixture {
        let suiteName = "\(suitePrefix)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = PreferencesStore(defaults: defaults, sync: NoopPreferencesSync())

        return PreferencesFixture(
            suiteName: suiteName,
            defaults: defaults,
            preferences: preferences
        )
    }

    private struct PreferencesFixture {
        let suiteName: String
        let defaults: UserDefaults
        let preferences: PreferencesStore
    }

    private struct MenuBarStatusItemControllerFixture {
        let suiteName: String
        let defaults: UserDefaults
        let preferences: PreferencesStore
        let controller: MenuBarStatusItemController
    }

    private func makeSnapshot(
        powerState: BatteryPowerState,
        stateOfChargePercent: Double?,
        fullChargeCapacityMilliampHours: Int = 5_000,
        inputPowerWatts: Double? = nil,
        inputPowerEvidence: BatteryInputPowerEvidence? = nil
    ) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: powerState,
            isCharging: powerState == .charging,
            isExternalPowerConnected: powerState != .onBattery,
            currentChargeMilliampHours: 5_000,
            currentChargeWattHours: 65,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: stateOfChargePercent,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            inputPowerWatts: inputPowerWatts,
            inputPowerEvidence: inputPowerEvidence,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )
    }
}

@MainActor
private final class NoopPreferencesSync: PreferencesSyncing {
    var isEnabled = false
    var isAvailable = true
    var isICloudAccountAvailable = true
    var availabilityDescription = "iCloud is available for tests."

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol {
        NSObject()
    }

    func removeObserver(_ token: NSObjectProtocol) {}

    func hasValue(forKey key: String) -> Bool {
        false
    }

    func bool(forKey key: String) -> Bool? {
        nil
    }

    func string(forKey key: String) -> String? {
        nil
    }

    func set(_ value: Bool, forKey key: String) {}

    func set(_ value: String, forKey key: String) {}

    func removeValue(forKey key: String) {}

    func flush() {}
}
