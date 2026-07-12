import Foundation

enum RefreshCadencePreference: String, CaseIterable, Identifiable {
    case dynamic
    case fiveSeconds
    case fifteenSeconds
    case thirtySeconds
    case oneMinute
    case fiveMinutes

    var id: String { rawValue }

    private var metadata: (title: String, fixedInterval: TimeInterval?) {
        switch self {
        case .dynamic:
            return ("Dynamic", nil)
        case .fiveSeconds:
            return ("Every 5 Seconds", 5)
        case .fifteenSeconds:
            return ("Every 15 Seconds", 15)
        case .thirtySeconds:
            return ("Every 30 Seconds", 30)
        case .oneMinute:
            return ("Every 1 Minute", 60)
        case .fiveMinutes:
            return ("Every 5 Minutes", 300)
        }
    }

    var title: String {
        metadata.title
    }

    var fixedInterval: TimeInterval? {
        metadata.fixedInterval
    }
}

enum EnergyChangeSensitivity: String, CaseIterable, Identifiable {
    case subtle
    case balanced
    case large

    var id: String { rawValue }

    private var metadata: (title: String, thresholdPercent: Double) {
        switch self {
        case .subtle:
            return ("20%", 20)
        case .balanced:
            return ("35%", 35)
        case .large:
            return ("50%", 50)
        }
    }

    var title: String {
        metadata.title
    }

    var thresholdPercent: Double {
        metadata.thresholdPercent
    }
}

struct BatteryMonitoringDemand: Equatable, Sendable {
    var needsEnergyChangeAwareness = false
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

    func usesEnergyChangeProbe(for demand: BatteryMonitoringDemand) -> Bool {
        demand.needsEnergyChangeAwareness
            && (cadence.fixedInterval.map { $0 > energyProbeInterval } ?? true)
    }

    func refreshInterval(for snapshot: BatterySnapshot?) -> TimeInterval {
        if let fixedInterval = cadence.fixedInterval {
            return fixedInterval
        }

        guard let snapshot else {
            return 60
        }

        if let stateOfChargePercent = snapshot.presentationStateOfChargePercent,
           snapshot.powerState.isBatteryDischarging,
           stateOfChargePercent <= 20 {
            return 30
        }

        switch snapshot.powerState {
        case .onBattery, .connectedDischarging, .charging:
            return 60
        case .connectedNotCharging, .fullOnAC:
            return 300
        case .unknown:
            return 120
        }
    }

    static func isSignificantEnergyChange(previous: Double?, current: Double?, thresholdPercent: Double) -> Bool {
        let previous = previous.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let current = current.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }

        switch (previous, current) {
        case (nil, nil):
            return false
        case (nil, .some), (.some, nil):
            return true
        case let (.some(previous), .some(current)):
            let thresholdPercent = max(0, thresholdPercent)
            let percentChange = abs(current - previous) / previous * 100
            return percentChange >= thresholdPercent
        }
    }
}
