import Foundation

enum BatteryCalculations {
    static func stateOfChargePercent(
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?,
        publicPercentage: Double?
    ) -> Double? {
        if let currentChargeMilliampHours,
           let fullChargeCapacityMilliampHours,
           fullChargeCapacityMilliampHours > 0 {
            return (Double(currentChargeMilliampHours) / Double(fullChargeCapacityMilliampHours)) * 100
        }

        return publicPercentage
    }

    static func healthPercent(fullChargeCapacityMilliampHours: Int?, designCapacityMilliampHours: Int?) -> Double? {
        guard let fullChargeCapacityMilliampHours,
              let designCapacityMilliampHours,
              designCapacityMilliampHours > 0 else {
            return nil
        }

        return (Double(fullChargeCapacityMilliampHours) / Double(designCapacityMilliampHours)) * 100
    }

    static func wattHours(milliampHours: Int?, voltageMillivolts: Int?) -> Double? {
        guard let milliampHours, let voltageMillivolts else {
            return nil
        }

        return (Double(milliampHours) * Double(voltageMillivolts)) / 1_000_000
    }

    static func dischargeRateMilliamps(from signedCurrentMilliamps: Int?) -> Int? {
        guard let signedCurrentMilliamps, signedCurrentMilliamps < 0 else {
            return nil
        }

        return abs(signedCurrentMilliamps)
    }

    static func chargeRateWatts(voltageMillivolts: Int?, signedCurrentMilliamps: Int?) -> Double? {
        guard let voltageMillivolts,
              let signedCurrentMilliamps,
              signedCurrentMilliamps > 0 else {
            return nil
        }

        return (Double(voltageMillivolts) * Double(signedCurrentMilliamps)) / 1_000_000
    }

    static func dischargeRateWatts(voltageMillivolts: Int?, signedCurrentMilliamps: Int?) -> Double? {
        guard let voltageMillivolts,
              let signedCurrentMilliamps,
              signedCurrentMilliamps < 0 else {
            return nil
        }

        return (Double(voltageMillivolts) * Double(abs(signedCurrentMilliamps))) / 1_000_000
    }

    static func timeRemainingMinutes(currentChargeMilliampHours: Int?, dischargeRateMilliamps: Int?) -> Int? {
        guard let currentChargeMilliampHours,
              let dischargeRateMilliamps,
              dischargeRateMilliamps > 40 else {
            return nil
        }

        let hours = Double(currentChargeMilliampHours) / Double(dischargeRateMilliamps)
        let minutes = Int((hours * 60).rounded())
        guard (1...1_440).contains(minutes) else {
            return nil
        }

        return minutes
    }

    static func smoothedDischargeRate(_ samples: [Int], fallback: Int?) -> Int? {
        let recentSamples = Array(samples.suffix(8)).filter { $0 > 40 }
        guard recentSamples.isEmpty == false else {
            return fallback
        }

        let total = recentSamples.reduce(0, +)
        return Int((Double(total) / Double(recentSamples.count)).rounded())
    }

    static func batteryAgeComponents(from manufactureDate: Date?, now: Date, calendar: Calendar = .current) -> DateComponents? {
        guard let manufactureDate else {
            return nil
        }

        return calendar.dateComponents([.year, .month, .day], from: manufactureDate, to: now)
    }

    static func temperatureCelsius(fromRaw rawValue: Int?) -> Double? {
        guard let rawValue else {
            return nil
        }

        let candidateCelsius = Double(rawValue) / 100.0
        if (-20...120).contains(candidateCelsius) {
            return candidateCelsius
        }

        let kelvinTenthsCandidate = (Double(rawValue) / 10.0) - 273.15
        if (-20...120).contains(kelvinTenthsCandidate) {
            return kelvinTenthsCandidate
        }

        return candidateCelsius
    }

    static func deriveCurrentChargeMilliampHours(publicPercentage: Double?, fullChargeCapacityMilliampHours: Int?) -> Int? {
        guard let publicPercentage, let fullChargeCapacityMilliampHours else {
            return nil
        }

        return Int((publicPercentage / 100 * Double(fullChargeCapacityMilliampHours)).rounded())
    }

    static func derivePowerState(
        isCharging: Bool,
        isExternalPowerConnected: Bool,
        signedCurrentMilliamps: Int?,
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?
    ) -> BatteryPowerState {
        if isCharging {
            return .charging
        }

        if isExternalPowerConnected == false {
            return .onBattery
        }

        if let signedCurrentMilliamps, signedCurrentMilliamps < 0 {
            return .onBattery
        }

        if let currentChargeMilliampHours,
           let fullChargeCapacityMilliampHours,
           fullChargeCapacityMilliampHours > 0 {
            let threshold = max(8, Int(Double(fullChargeCapacityMilliampHours) * 0.01))
            if currentChargeMilliampHours >= fullChargeCapacityMilliampHours - threshold {
                return .fullOnAC
            }
        }

        return isExternalPowerConnected ? .connectedNotCharging : .unknown
    }
}
