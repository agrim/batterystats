import SwiftUI

enum BatteryPresentationStyle {
    static func tint(for tone: BatteryLevelTone) -> Color {
        tintStyle(for: tone).color
    }

    static func tintStyle(for tone: BatteryLevelTone) -> BatteryPresentationTint {
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
        healthTintStyle(for: snapshot).color
    }

    static func healthTintStyle(for snapshot: BatterySnapshot?) -> BatteryPresentationTint {
        guard let snapshot,
              snapshot.presentationHealthPercent != nil else {
            return .secondary
        }

        return tintStyle(for: snapshot.healthTone)
    }

    static func chargeTint(for snapshot: BatterySnapshot?) -> Color {
        chargeTintStyle(for: snapshot).color
    }

    static func chargeTintStyle(for snapshot: BatterySnapshot?) -> BatteryPresentationTint {
        guard let snapshot,
              snapshot.presentationStateOfChargePercent != nil else {
            return .secondary
        }

        return tintStyle(for: snapshot.chargeTone)
    }

    static func batterySymbolName(for snapshot: BatterySnapshot?) -> String {
        guard let snapshot else {
            return "questionmark"
        }

        if snapshot.presentationStateOfChargePercent != nil {
            return snapshot.batterySymbolName
        }

        switch snapshot.powerState {
        case .charging, .connectedDischarging, .connectedNotCharging, .fullOnAC:
            return snapshot.powerState.symbolName
        case .onBattery, .unknown:
            return "questionmark"
        }
    }

    static func timeTint(for snapshot: BatterySnapshot?) -> Color {
        timeTintStyle(for: snapshot).color
    }

    static func timeTintStyle(for snapshot: BatterySnapshot?) -> BatteryPresentationTint {
        guard let snapshot else {
            return .secondary
        }

        switch snapshot.powerState {
        case .charging, .connectedNotCharging, .fullOnAC:
            if isLowCharge(snapshot) {
                return .yellow
            }

            return .green
        case .onBattery, .connectedDischarging:
            guard snapshot.displayedTimeMinutes != nil || hasUsableCharge(snapshot) else {
                return .secondary
            }

            return isLowCharge(snapshot) ? .red : .yellow
        case .unknown:
            return .secondary
        }
    }

    static func statusDescriptor(for snapshot: BatterySnapshot?) -> BatteryStatusDescriptor {
        guard let snapshot else {
            return BatteryStatusDescriptor(symbolName: "questionmark", ringTintStyle: .secondary, contentTintStyle: .secondary)
        }

        switch snapshot.powerState {
        case .charging, .connectedNotCharging, .fullOnAC:
            return BatteryStatusDescriptor(symbolName: "powerplug", ringTintStyle: .green, contentTintStyle: .primary)
        case .onBattery:
            guard hasUsableCharge(snapshot) else {
                return BatteryStatusDescriptor(symbolName: "questionmark", ringTintStyle: .secondary, contentTintStyle: .secondary)
            }

            if isLowCharge(snapshot) {
                return BatteryStatusDescriptor(symbolName: snapshot.batterySymbolName, ringTintStyle: .yellow, contentTintStyle: .yellow)
            }

            return BatteryStatusDescriptor(symbolName: snapshot.batterySymbolName, ringTintStyle: .green, contentTintStyle: .primary)
        case .connectedDischarging:
            guard hasUsableCharge(snapshot) else {
                return BatteryStatusDescriptor(symbolName: "powerplug", ringTintStyle: .secondary, contentTintStyle: .secondary)
            }

            return BatteryStatusDescriptor(symbolName: "powerplug", ringTintStyle: isLowCharge(snapshot) ? .red : .yellow, contentTintStyle: .primary)
        case .unknown:
            return BatteryStatusDescriptor(symbolName: "questionmark", ringTintStyle: .secondary, contentTintStyle: .secondary)
        }
    }

    private static func isLowCharge(_ snapshot: BatterySnapshot) -> Bool {
        guard let stateOfChargePercent = snapshot.presentationStateOfChargePercent else {
            return false
        }

        return stateOfChargePercent <= 20
    }

    private static func hasUsableCharge(_ snapshot: BatterySnapshot) -> Bool {
        snapshot.presentationStateOfChargePercent != nil
    }
}

struct BatteryStatusDescriptor {
    let symbolName: String
    let ringTintStyle: BatteryPresentationTint
    let contentTintStyle: BatteryPresentationTint

    var ringTint: Color {
        ringTintStyle.color
    }

    var contentTint: Color {
        contentTintStyle.color
    }
}

enum BatteryPresentationTint: Equatable {
    case primary
    case secondary
    case green
    case yellow
    case red

    var color: Color {
        switch self {
        case .primary:
            return .primary
        case .secondary:
            return .secondary
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .red:
            return .red
        }
    }

    var identityToken: String {
        switch self {
        case .primary:
            return "primary"
        case .secondary:
            return "secondary"
        case .green:
            return "green"
        case .yellow:
            return "yellow"
        case .red:
            return "red"
        }
    }
}
