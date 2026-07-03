import Foundation

enum BatteryPowerState: String, Codable, Equatable, Sendable {
    case onBattery
    case charging
    case connectedDischarging
    case connectedNotCharging
    case fullOnAC
    case unknown

    var displayTitle: String {
        switch self {
        case .onBattery:
            return "On Battery"
        case .charging:
            return "Charging"
        case .connectedDischarging:
            return "Connected, Discharging"
        case .connectedNotCharging:
            return "Connected, Not Charging"
        case .fullOnAC:
            return "Fully Charged"
        case .unknown:
            return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .onBattery:
            return "battery.25"
        case .charging:
            return "battery.100.bolt"
        case .connectedDischarging:
            return "powerplug"
        case .connectedNotCharging:
            return "powerplug"
        case .fullOnAC:
            return "battery.100"
        case .unknown:
            return "questionmark.circle"
        }
    }

    var knownExternalPowerConnected: Bool? {
        switch self {
        case .charging, .connectedDischarging, .connectedNotCharging, .fullOnAC:
            return true
        case .onBattery:
            return false
        case .unknown:
            return nil
        }
    }

    var isExternallyPowered: Bool {
        knownExternalPowerConnected == true
    }

    var isBatteryDischarging: Bool {
        switch self {
        case .onBattery, .connectedDischarging:
            return true
        case .charging, .connectedNotCharging, .fullOnAC, .unknown:
            return false
        }
    }

    func timeTitle(charging: String, discharging: String, idle: String = "Time") -> String {
        switch self {
        case .charging:
            return charging
        case .onBattery, .connectedDischarging:
            return discharging
        case .connectedNotCharging, .fullOnAC, .unknown:
            return idle
        }
    }
}
