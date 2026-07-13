import SwiftUI

enum BatteryPresentationStyle {
    static func tintStyle(for tone: BatteryLevelTone) -> BatteryPresentationTint {
        switch tone {
        case .green, .midGreen:
            return .green
        case .greenYellow, .yellow:
            return .yellow
        case .red:
            return .red
        }
    }

    static func healthTintStyle(for snapshot: BatterySnapshot?) -> BatteryPresentationTint {
        guard let snapshot,
              snapshot.presentationHealthPercent != nil else {
            return .secondary
        }

        return tintStyle(for: snapshot.healthTone)
    }

    static func chargeTintStyle(for snapshot: BatterySnapshot?) -> BatteryPresentationTint {
        guard let snapshot,
              snapshot.hasUsableCharge else {
            return .secondary
        }

        return tintStyle(for: snapshot.chargeTone)
    }

    static func batterySymbolName(for snapshot: BatterySnapshot?) -> String {
        guard let snapshot else {
            return "questionmark"
        }

        if snapshot.hasUsableCharge {
            return snapshot.batterySymbolName
        }

        return snapshot.powerState.isExternallyPowered ? snapshot.powerState.symbolName : "questionmark"
    }

    static func timeTintStyle(
        for snapshot: BatterySnapshot?,
        displayedTimeMinutes: Int?
    ) -> BatteryPresentationTint {
        guard let snapshot,
              displayedTimeMinutes != nil else {
            return .secondary
        }

        return snapshot.isLowCharge ? .red : .green
    }

    static func statusDescriptor(for snapshot: BatterySnapshot?) -> BatteryStatusDescriptor {
        guard let snapshot else {
            return BatteryStatusDescriptor(symbolName: "questionmark", ringTintStyle: .secondary, contentTintStyle: .secondary)
        }

        switch snapshot.powerState {
        case .charging, .connectedNotCharging, .fullOnAC:
            return BatteryStatusDescriptor(symbolName: "powerplug", ringTintStyle: .green, contentTintStyle: .primary)
        case .onBattery:
            guard snapshot.hasUsableCharge else {
                return BatteryStatusDescriptor(symbolName: "questionmark", ringTintStyle: .secondary, contentTintStyle: .secondary)
            }

            if snapshot.isLowCharge {
                return BatteryStatusDescriptor(symbolName: snapshot.batterySymbolName, ringTintStyle: .yellow, contentTintStyle: .yellow)
            }

            return BatteryStatusDescriptor(symbolName: snapshot.batterySymbolName, ringTintStyle: .green, contentTintStyle: .primary)
        case .connectedDischarging:
            guard snapshot.hasUsableCharge else {
                return BatteryStatusDescriptor(symbolName: "powerplug", ringTintStyle: .secondary, contentTintStyle: .secondary)
            }

            return BatteryStatusDescriptor(symbolName: "powerplug", ringTintStyle: snapshot.isLowCharge ? .red : .yellow, contentTintStyle: .primary)
        case .unknown:
            return BatteryStatusDescriptor(symbolName: "questionmark", ringTintStyle: .secondary, contentTintStyle: .secondary)
        }
    }

}

struct BatteryStatusDescriptor {
    let symbolName: String
    let ringTintStyle: BatteryPresentationTint
    let contentTintStyle: BatteryPresentationTint

    var progress: Double? {
        ringTintStyle == .secondary ? nil : 1
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
}
