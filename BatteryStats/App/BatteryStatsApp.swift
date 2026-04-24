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
                .onAppear {
                    configureMonitor()
                    monitor.start()
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
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacement { content, _ in
            WindowPlacement(size: content.sizeThatFits(.unspecified))
        }
        .windowIdealSize(.fitToContent)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.disabled)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarBatteryView(monitor: monitor, preferences: preferences, historyStore: historyStore)
                .environment(monitor)
                .environment(preferences)
                .onAppear {
                    configureMonitor()
                    monitor.start()
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
        } label: {
            MenuBarBatteryLabelView(snapshot: monitor.snapshot, displayMode: preferences.menuBarDisplayMode)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences, monitor: monitor, historyStore: historyStore)
                .environment(preferences)
                .environment(monitor)
                .onAppear {
                    configureMonitor()
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
        }
        .commands {
            AppCommands()
        }
    }

    private func configureMonitor() {
        monitor.updateRefreshPolicy(preferences.refreshPolicy)
        monitor.updateHistory(store: historyStore, policy: preferences.historyPolicy)
        monitor.updateAlerts(preferences.alertPolicy)
    }
}
