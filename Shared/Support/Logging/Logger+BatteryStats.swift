import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.agrim.batterystats"

    static let batteryReader = Logger(subsystem: subsystem, category: "batteryReader")
    static let powerSource = Logger(subsystem: subsystem, category: "powerSource")
    static let settingsSync = Logger(subsystem: subsystem, category: "settingsSync")
    static let launchAtLogin = Logger(subsystem: subsystem, category: "launchAtLogin")
}
