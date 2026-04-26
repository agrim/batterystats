import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Open BatteryStats") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("1", modifiers: [.command])

            Divider()

            Button("Settings…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
