import Foundation

enum BatteryPowerState: String, Equatable, Sendable {
    case onBattery
    case charging
    case connectedNotCharging
    case fullOnAC
    case unknown

    var displayTitle: String {
        switch self {
        case .onBattery:
            return "On Battery"
        case .charging:
            return "Charging"
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
        case .connectedNotCharging:
            return "powerplug"
        case .fullOnAC:
            return "battery.100"
        case .unknown:
            return "questionmark.circle"
        }
    }
}
