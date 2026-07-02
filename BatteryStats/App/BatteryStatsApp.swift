import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        BatteryStatsAppRuntime.shared.startMonitoring()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        BatteryStatsAppRuntime.shared.refreshExternalConfiguration()
    }
}

@main
@MainActor
struct BatteryStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var runtime = BatteryStatsAppRuntime.shared

    var body: some Scene {
        WindowGroup("BatteryStats", id: "main") {
            BatteryDashboardView(monitor: runtime.monitor, preferences: runtime.preferences)
                .environment(runtime.monitor)
                .environment(runtime.preferences)
                .monitorConfiguration(
                    monitor: runtime.monitor,
                    preferences: runtime.preferences,
                    historyStore: runtime.historyStore,
                    startsMonitor: true
                )
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 276, height: 280)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.disabled)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)

        Settings {
            SettingsView(preferences: runtime.preferences, monitor: runtime.monitor, historyStore: runtime.historyStore)
                .environment(runtime.preferences)
                .environment(runtime.monitor)
                .monitorConfiguration(monitor: runtime.monitor, preferences: runtime.preferences, historyStore: runtime.historyStore, startsMonitor: false)
        }
        .commands {
            AppCommands()
        }
    }
}

@MainActor
@Observable
private final class BatteryStatsAppRuntime {
    static let shared = BatteryStatsAppRuntime()

    @ObservationIgnored
    let monitor: BatteryMonitor
    @ObservationIgnored
    let preferences: PreferencesStore
    @ObservationIgnored
    let historyStore: BatteryHistoryStore

    @ObservationIgnored
    private let monitorConfigurationObserver: BatteryMonitorConfigurationObserver
    @ObservationIgnored
    private let alertAuthorizationObserver: BatteryAlertAuthorizationObserver
    @ObservationIgnored
    private var menuBarStatusItemController: MenuBarStatusItemController?
    @ObservationIgnored
    private let settingsWindowController = SettingsWindowController()
    @ObservationIgnored
    private var showSettingsObserver: NSObjectProtocol?

    private init() {
        monitor = BatteryMonitor()
        preferences = PreferencesStore()
        historyStore = BatteryHistoryStore()
        monitorConfigurationObserver = BatteryMonitorConfigurationObserver(
            monitor: monitor,
            preferences: preferences,
            historyStore: historyStore
        )
        alertAuthorizationObserver = BatteryAlertAuthorizationObserver(preferences: preferences)

        showSettingsObserver = NotificationCenter.default.addObserver(
            forName: .showBatteryStatsSettingsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showSettingsWindow()
            }
        }
    }

    func startMonitoring() {
        preferences.refreshICloudSyncAvailability()
        alertAuthorizationObserver.start()
        monitorConfigurationObserver.start()
        installMenuBarStatusItem()
        monitor.start()
    }

    func refreshExternalConfiguration() {
        preferences.refreshICloudSyncAvailability()
        alertAuthorizationObserver.refreshAuthorizationStatus()
    }

    func showSettingsWindow() {
        startMonitoring()
        settingsWindowController.show(
            preferences: preferences,
            monitor: monitor,
            historyStore: historyStore
        )
    }

    private func installMenuBarStatusItem() {
        guard menuBarStatusItemController == nil else {
            return
        }

        let controller = MenuBarStatusItemController(
            monitor: monitor,
            preferences: preferences,
            historyStore: historyStore
        )
        menuBarStatusItemController = controller
        controller.start()
    }
}

@MainActor
private final class SettingsWindowController {
    private var window: NSWindow?

    func show(
        preferences: PreferencesStore,
        monitor: BatteryMonitor,
        historyStore: BatteryHistoryStore
    ) {
        NSApp.setActivationPolicy(.regular)
        let window = window ?? makeWindow(
            preferences: preferences,
            monitor: monitor,
            historyStore: historyStore
        )
        self.window = window
        BatteryWindowSpaceBehavior.applyActiveSpacePresentation(to: window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(
        preferences: PreferencesStore,
        monitor: BatteryMonitor,
        historyStore: BatteryHistoryStore
    ) -> NSWindow {
        let contentView = NSHostingView(rootView:
            SettingsView(preferences: preferences, monitor: monitor, historyStore: historyStore)
                .environment(preferences)
                .environment(monitor)
                .monitorConfiguration(
                    monitor: monitor,
                    preferences: preferences,
                    historyStore: historyStore,
                    startsMonitor: false
                )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.minimumWindowWidth, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: SettingsLayout.minimumWindowWidth, height: 480)
        window.contentView = contentView
        window.center()
        return window
    }
}

@MainActor
final class BatteryMonitorConfigurationObserver {
    private let monitor: BatteryMonitor
    private let preferences: PreferencesStore
    private let historyStore: BatteryHistoryStore
    private var observationGeneration = 0
    private var isStarted = false

    init(
        monitor: BatteryMonitor,
        preferences: PreferencesStore,
        historyStore: BatteryHistoryStore
    ) {
        self.monitor = monitor
        self.preferences = preferences
        self.historyStore = historyStore
    }

    func start() {
        guard isStarted == false else {
            return
        }

        isStarted = true
        monitor.applyConfiguration(preferences: preferences, historyStore: historyStore)
        observePreferences()
    }

    private func observePreferences() {
        observationGeneration += 1
        let generation = observationGeneration

        withObservationTracking {
            _ = preferences.refreshPolicy
            _ = preferences.historyPolicy
            _ = preferences.alertPolicy
            _ = preferences.monitoringDemand
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      isStarted,
                      observationGeneration == generation else {
                    return
                }

                monitor.applyConfiguration(preferences: preferences, historyStore: historyStore)
                observePreferences()
            }
        }
    }
}

private struct MonitorConfigurationModifier: ViewModifier {
    let monitor: BatteryMonitor
    let preferences: PreferencesStore
    let historyStore: BatteryHistoryStore
    let startsMonitor: Bool
    @State private var isVisibleSurfaceMonitoringActive = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor.applyConfiguration(preferences: preferences, historyStore: historyStore)
                if startsMonitor {
                    if isVisibleSurfaceMonitoringActive == false {
                        isVisibleSurfaceMonitoringActive = true
                        monitor.beginVisibleSurfaceMonitoring()
                    }

                    if monitor.start() == false {
                        monitor.refreshForVisibleSurface()
                    }
                }
            }
            .onDisappear {
                if startsMonitor,
                   isVisibleSurfaceMonitoringActive {
                    isVisibleSurfaceMonitoringActive = false
                    monitor.endVisibleSurfaceMonitoring()
                }
            }
    }
}

private extension BatteryMonitor {
    func applyConfiguration(preferences: PreferencesStore, historyStore: BatteryHistoryStore) {
        updateRefreshPolicy(preferences.refreshPolicy)
        updateHistory(store: historyStore, policy: preferences.historyPolicy)
        updateAlerts(preferences.alertPolicy)
        updateMonitoringDemand(preferences.monitoringDemand)
    }
}

extension View {
    func monitorConfiguration(
        monitor: BatteryMonitor,
        preferences: PreferencesStore,
        historyStore: BatteryHistoryStore,
        startsMonitor: Bool
    ) -> some View {
        modifier(
            MonitorConfigurationModifier(
                monitor: monitor,
                preferences: preferences,
                historyStore: historyStore,
                startsMonitor: startsMonitor
            )
        )
    }
}
