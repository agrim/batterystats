import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct BatteryStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var monitor = BatteryMonitor()
    @State private var preferences = PreferencesStore()
    @State private var historyStore = BatteryHistoryStore()

    var body: some Scene {
        WindowGroup("BatteryStats", id: "main") {
            BatteryDashboardView(monitor: monitor, preferences: preferences)
                .environment(monitor)
                .environment(preferences)
                .monitorConfiguration(monitor: monitor, preferences: preferences, historyStore: historyStore, startsMonitor: true)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 276, height: 280)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.disabled)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarBatteryView(monitor: monitor, preferences: preferences, historyStore: historyStore)
                .environment(monitor)
                .environment(preferences)
                .monitorConfiguration(monitor: monitor, preferences: preferences, historyStore: historyStore, startsMonitor: true)
        } label: {
            MenuBarBatteryLabelView(snapshot: monitor.snapshot, displayMode: preferences.menuBarDisplayMode)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences, monitor: monitor, historyStore: historyStore)
                .environment(preferences)
                .environment(monitor)
                .monitorConfiguration(monitor: monitor, preferences: preferences, historyStore: historyStore, startsMonitor: false)
        }
        .commands {
            AppCommands()
        }
    }
}

private struct MonitorConfigurationModifier: ViewModifier {
    let monitor: BatteryMonitor
    let preferences: PreferencesStore
    let historyStore: BatteryHistoryStore
    let startsMonitor: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                configureMonitor()
                if startsMonitor {
                    monitor.start()
                }
            }
            .onChange(of: preferences.refreshPolicy) { _, policy in
                monitor.updateRefreshPolicy(policy)
            }
            .onChange(of: preferences.historyPolicy) { _, policy in
                monitor.updateHistory(store: historyStore, policy: policy)
            }
            .onChange(of: preferences.alertPolicy) { _, policy in
                monitor.updateAlerts(policy)
            }
            .onChange(of: preferences.monitoringDemand) { _, demand in
                monitor.updateMonitoringDemand(demand)
            }
    }

    private func configureMonitor() {
        monitor.updateRefreshPolicy(preferences.refreshPolicy)
        monitor.updateHistory(store: historyStore, policy: preferences.historyPolicy)
        monitor.updateAlerts(preferences.alertPolicy)
        monitor.updateMonitoringDemand(preferences.monitoringDemand)
    }
}

private extension View {
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
