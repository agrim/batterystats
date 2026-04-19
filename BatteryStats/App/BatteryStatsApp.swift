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

    var body: some Scene {
        WindowGroup("BatteryStats", id: "main") {
            BatteryDashboardView(monitor: monitor, preferences: preferences)
                .environment(monitor)
                .environment(preferences)
                .onAppear {
                    monitor.start()
                }
        }
        .defaultSize(width: 620, height: 720)

        MenuBarExtra {
            MenuBarBatteryView(monitor: monitor, preferences: preferences)
                .environment(monitor)
                .environment(preferences)
                .onAppear {
                    monitor.start()
                }
        } label: {
            MenuBarBatteryLabelView(snapshot: monitor.snapshot, displayMode: preferences.menuBarDisplayMode)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(preferences: preferences, monitor: monitor)
                .environment(preferences)
                .environment(monitor)
        }
        .commands {
            AppCommands(refreshAction: monitor.refresh)
        }
    }
}
