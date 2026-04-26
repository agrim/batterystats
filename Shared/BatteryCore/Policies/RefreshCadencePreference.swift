import Foundation

enum RefreshCadencePreference: String, CaseIterable, Identifiable {
    case dynamic
    case fiveSeconds
    case fifteenSeconds
    case thirtySeconds
    case oneMinute
    case fiveMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dynamic:
            return "Dynamic"
        case .fiveSeconds:
            return "Every 5 Seconds"
        case .fifteenSeconds:
            return "Every 15 Seconds"
        case .thirtySeconds:
            return "Every 30 Seconds"
        case .oneMinute:
            return "Every 1 Minute"
        case .fiveMinutes:
            return "Every 5 Minutes"
        }
    }

    var fixedInterval: TimeInterval? {
        switch self {
        case .dynamic:
            return nil
        case .fiveSeconds:
            return 5
        case .fifteenSeconds:
            return 15
        case .thirtySeconds:
            return 30
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 300
        }
    }
}

enum EnergyChangeSensitivity: String, CaseIterable, Identifiable {
    case subtle
    case balanced
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle:
            return "20%"
        case .balanced:
            return "35%"
        case .large:
            return "50%"
        }
    }

    var thresholdPercent: Double {
        switch self {
        case .subtle:
            return 20
        case .balanced:
            return 35
        case .large:
            return 50
        }
    }
}

struct BatteryRefreshPolicy: Equatable {
    var cadence: RefreshCadencePreference = .dynamic
    var energyChangeSensitivity: EnergyChangeSensitivity = .balanced

    var energyChangeThresholdPercent: Double {
        energyChangeSensitivity.thresholdPercent
    }

    var energyProbeInterval: TimeInterval {
        15
    }

    var usesEnergyChangeProbe: Bool {
        guard let fixedInterval = cadence.fixedInterval else {
            return true
        }

        return fixedInterval > energyProbeInterval
    }

    func refreshInterval(for snapshot: BatterySnapshot?) -> TimeInterval {
        if let fixedInterval = cadence.fixedInterval {
            return fixedInterval
        }

        guard let snapshot else {
            return 60
        }

        if let stateOfChargePercent = snapshot.stateOfChargePercent,
           snapshot.powerState == .onBattery,
           stateOfChargePercent <= 20 {
            return 30
        }

        switch snapshot.powerState {
        case .onBattery, .charging:
            return 60
        case .connectedNotCharging, .fullOnAC:
            return 300
        case .unknown:
            return 120
        }
    }

    static func isSignificantEnergyChange(previous: Double?, current: Double?, thresholdPercent: Double) -> Bool {
        guard let previous,
              let current,
              previous > 0,
              current > 0 else {
            return false
        }

        let percentChange = abs(current - previous) / previous * 100
        return percentChange >= thresholdPercent
    }
}
