import SwiftUI

extension Notification.Name {
    static let showBatteryStatsSettingsWindow = Notification.Name("BatteryStats.showSettingsWindow")
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Open BatteryStats") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("1", modifiers: [.command])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NotificationCenter.default.post(name: .showBatteryStatsSettingsWindow, object: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
