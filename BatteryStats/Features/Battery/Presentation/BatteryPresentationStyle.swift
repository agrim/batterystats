import SwiftUI

enum BatteryPresentationStyle {
    static func tint(for tone: BatteryLevelTone) -> Color {
        switch tone {
        case .green:
            return .green
        case .midGreen:
            return .green
        case .greenYellow:
            return .yellow
        case .yellow:
            return .yellow
        case .red:
            return .red
        }
    }

    static func healthTint(for snapshot: BatterySnapshot?) -> Color {
        guard let snapshot else {
            return .secondary
        }

        return tint(for: snapshot.healthTone)
    }

    static func chargeTint(for snapshot: BatterySnapshot?) -> Color {
        guard let snapshot else {
            return .secondary
        }

        return tint(for: snapshot.chargeTone)
    }

    static func timeTint(for snapshot: BatterySnapshot?) -> Color {
        guard let snapshot else {
            return .secondary
        }

        switch snapshot.powerState {
        case .charging, .connectedNotCharging, .fullOnAC:
            if isLowCharge(snapshot) {
                return .yellow
            }

            return .green
        case .onBattery:
            return isLowCharge(snapshot) ? .red : .yellow
        case .unknown:
            return .secondary
        }
    }

    static func statusDescriptor(for snapshot: BatterySnapshot?) -> BatteryStatusDescriptor {
        guard let snapshot else {
            return BatteryStatusDescriptor(symbolName: "questionmark", ringTint: .secondary, contentTint: .white)
        }

        switch snapshot.powerState {
        case .charging, .connectedNotCharging, .fullOnAC:
            return BatteryStatusDescriptor(symbolName: "powerplug", ringTint: .green, contentTint: .white)
        case .onBattery:
            if isLowCharge(snapshot) {
                return BatteryStatusDescriptor(symbolName: "battery.100", ringTint: .yellow, contentTint: .yellow)
            }

            return BatteryStatusDescriptor(symbolName: "battery.100", ringTint: .green, contentTint: .white)
        case .unknown:
            return BatteryStatusDescriptor(symbolName: "questionmark", ringTint: .secondary, contentTint: .white)
        }
    }

    private static func isLowCharge(_ snapshot: BatterySnapshot) -> Bool {
        (snapshot.stateOfChargePercent ?? 100) < 20
    }
}

struct BatteryStatusDescriptor {
    let symbolName: String
    let ringTint: Color
    let contentTint: Color
}
