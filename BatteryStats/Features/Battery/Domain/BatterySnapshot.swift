import Foundation

enum BatteryLevelTone: String, Equatable, Sendable {
    case red
    case yellow
    case greenYellow
    case midGreen
    case green
}

struct BatterySnapshot: Equatable, Sendable {
    let timestamp: Date
    let powerState: BatteryPowerState
    let isCharging: Bool
    let isExternalPowerConnected: Bool

    let currentChargeMilliampHours: Int?
    let currentChargeWattHours: Double?
    let fullChargeCapacityMilliampHours: Int?
    let fullChargeCapacityWattHours: Double?
    let designCapacityMilliampHours: Int?
    let designCapacityWattHours: Double?
    let healthPercent: Double?
    let stateOfChargePercent: Double?

    let voltageMillivolts: Int?
    let currentMilliampsSigned: Int?
    let dischargeRateMilliamps: Int?
    let chargeRateWatts: Double?
    let dischargeRateWatts: Double?

    let rateBasedTimeRemainingMinutes: Int?
    let systemTimeRemainingMinutes: Int?
    let timeToFullMinutes: Int?

    let cycleCount: Int?
    let manufactureDate: Date?
    let batteryAgeComponents: DateComponents?
    let temperatureCelsius: Double?

    let adapterMaxWatts: Int?
    let notes: [String]

    var displayedTimeMinutes: Int? {
        switch powerState {
        case .onBattery:
            return rateBasedTimeRemainingMinutes ?? systemTimeRemainingMinutes
        case .charging:
            return timeToFullMinutes
        default:
            return systemTimeRemainingMinutes
        }
    }

    var statusDisplayTitle: String {
        switch powerState {
        case .onBattery:
            if let stateOfChargePercent, stateOfChargePercent <= 20 {
                return "On Battery Low Power"
            }
            return "On Battery"
        case .charging:
            return "Charging"
        case .connectedNotCharging, .fullOnAC:
            return "Plugged In"
        case .unknown:
            return "Unknown"
        }
    }

    var statusSecondaryText: String? {
        switch powerState {
        case .onBattery:
            return "Using internal battery"
        case .charging:
            return chargeRateWatts.map { "Charging at \(BatteryFormatting.watts($0))" } ?? "External power connected"
        case .connectedNotCharging, .fullOnAC:
            return "External power connected"
        case .unknown:
            return nil
        }
    }

    var healthTone: BatteryLevelTone {
        guard let healthPercent else {
            return .green
        }

        if healthPercent > 95 {
            return .green
        }

        if healthPercent >= 90 {
            return .midGreen
        }

        if healthPercent >= 85 {
            return .greenYellow
        }

        if healthPercent >= 80 {
            return .yellow
        }

        return .red
    }

    var chargeTone: BatteryLevelTone {
        guard let stateOfChargePercent else {
            return .green
        }

        if stateOfChargePercent > 70 {
            return .green
        }

        if stateOfChargePercent >= 40 {
            return .midGreen
        }

        if stateOfChargePercent >= 20 {
            return .greenYellow
        }

        if stateOfChargePercent >= 10 {
            return .yellow
        }

        return .red
    }

    var batterySymbolName: String {
        guard let stateOfChargePercent else {
            return "battery.0"
        }

        switch stateOfChargePercent {
        case ..<10:
            return "battery.0"
        case ..<37.5:
            return "battery.25"
        case ..<62.5:
            return "battery.50"
        case ..<87.5:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    var debugSummary: String {
        var lines: [String] = []
        lines.append("Timestamp: \(timestamp.formatted(date: .numeric, time: .standard))")
        lines.append("Power state: \(powerState.displayTitle)")
        lines.append("State of charge: \(BatteryFormatting.percent(stateOfChargePercent))")
        lines.append("Full charge capacity: \(BatteryFormatting.milliampHours(fullChargeCapacityMilliampHours))")
        lines.append("Design capacity: \(BatteryFormatting.milliampHours(designCapacityMilliampHours))")
        lines.append("Current charge: \(BatteryFormatting.milliampHours(currentChargeMilliampHours))")
        lines.append("Voltage: \(BatteryFormatting.millivolts(voltageMillivolts))")
        lines.append("Signed current: \(BatteryFormatting.signedMilliamps(currentMilliampsSigned))")
        lines.append("Temperature: \(BatteryFormatting.temperature(temperatureCelsius, unitPreference: .celsius))")
        lines.append("Cycle count: \(cycleCount.map(String.init) ?? "Unavailable")")
        lines.append("Manufacture date: \(BatteryFormatting.date(manufactureDate))")

        if notes.isEmpty == false {
            lines.append("Notes:")
            lines.append(contentsOf: notes.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    func updating(rateBasedTimeRemainingMinutes: Int?) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: timestamp,
            powerState: powerState,
            isCharging: isCharging,
            isExternalPowerConnected: isExternalPowerConnected,
            currentChargeMilliampHours: currentChargeMilliampHours,
            currentChargeWattHours: currentChargeWattHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            fullChargeCapacityWattHours: fullChargeCapacityWattHours,
            designCapacityMilliampHours: designCapacityMilliampHours,
            designCapacityWattHours: designCapacityWattHours,
            healthPercent: healthPercent,
            stateOfChargePercent: stateOfChargePercent,
            voltageMillivolts: voltageMillivolts,
            currentMilliampsSigned: currentMilliampsSigned,
            dischargeRateMilliamps: dischargeRateMilliamps,
            chargeRateWatts: chargeRateWatts,
            dischargeRateWatts: dischargeRateWatts,
            rateBasedTimeRemainingMinutes: rateBasedTimeRemainingMinutes,
            systemTimeRemainingMinutes: systemTimeRemainingMinutes,
            timeToFullMinutes: timeToFullMinutes,
            cycleCount: cycleCount,
            manufactureDate: manufactureDate,
            batteryAgeComponents: batteryAgeComponents,
            temperatureCelsius: temperatureCelsius,
            adapterMaxWatts: adapterMaxWatts,
            notes: notes
        )
    }
}

extension BatterySnapshot {
    static let previewDischarging = BatterySnapshot(
        timestamp: .now,
        powerState: .onBattery,
        isCharging: false,
        isExternalPowerConnected: false,
        currentChargeMilliampHours: 4_912,
        currentChargeWattHours: 62.8,
        fullChargeCapacityMilliampHours: 5_338,
        fullChargeCapacityWattHours: 68.3,
        designCapacityMilliampHours: 6_559,
        designCapacityWattHours: 83.8,
        healthPercent: 81.4,
        stateOfChargePercent: 92.0,
        voltageMillivolts: 12_780,
        currentMilliampsSigned: -1_086,
        dischargeRateMilliamps: 1_086,
        chargeRateWatts: nil,
        dischargeRateWatts: 13.9,
        rateBasedTimeRemainingMinutes: 168,
        systemTimeRemainingMinutes: 180,
        timeToFullMinutes: nil,
        cycleCount: 247,
        manufactureDate: Calendar.current.date(from: DateComponents(year: 2023, month: 9, day: 12)),
        batteryAgeComponents: DateComponents(year: 2, month: 7),
        temperatureCelsius: 34.2,
        adapterMaxWatts: 70,
        notes: []
    )

    static let previewCharging = BatterySnapshot(
        timestamp: .now,
        powerState: .charging,
        isCharging: true,
        isExternalPowerConnected: true,
        currentChargeMilliampHours: 4_031,
        currentChargeWattHours: 52.0,
        fullChargeCapacityMilliampHours: 5_338,
        fullChargeCapacityWattHours: 68.3,
        designCapacityMilliampHours: 6_559,
        designCapacityWattHours: 83.8,
        healthPercent: 81.4,
        stateOfChargePercent: 75.5,
        voltageMillivolts: 12_910,
        currentMilliampsSigned: 1_721,
        dischargeRateMilliamps: nil,
        chargeRateWatts: 22.2,
        dischargeRateWatts: nil,
        rateBasedTimeRemainingMinutes: nil,
        systemTimeRemainingMinutes: nil,
        timeToFullMinutes: 52,
        cycleCount: 247,
        manufactureDate: Calendar.current.date(from: DateComponents(year: 2023, month: 9, day: 12)),
        batteryAgeComponents: DateComponents(year: 2, month: 7),
        temperatureCelsius: 32.0,
        adapterMaxWatts: 70,
        notes: []
    )
}
