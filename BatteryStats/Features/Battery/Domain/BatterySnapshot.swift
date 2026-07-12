import Foundation

enum BatteryLevelTone: String, Equatable, Sendable {
    case red
    case yellow
    case greenYellow
    case midGreen
    case green

    static func forPercent(
        _ percent: Double?,
        greenAbove: Double,
        midGreenMinimum: Double,
        greenYellowMinimum: Double,
        yellowMinimum: Double
    ) -> BatteryLevelTone {
        guard let percent else {
            return .green
        }

        if percent > greenAbove {
            return .green
        }

        if percent >= midGreenMinimum {
            return .midGreen
        }

        if percent >= greenYellowMinimum {
            return .greenYellow
        }

        return percent >= yellowMinimum ? .yellow : .red
    }
}

enum BatteryInputPowerEvidence: String, Codable, Equatable, Sendable {
    case counterBacked
}

struct BatterySnapshot: Codable, Equatable, Sendable {
    private(set) var timestamp: Date
    let powerState: BatteryPowerState
    let isCharging: Bool
    let isExternalPowerConnected: Bool

    let currentChargeMilliampHours: Int?
    let currentChargeWattHours: Double?
    let fullChargeCapacityMilliampHours: Int?
    let fullChargeCapacityWattHours: Double?
    let designCapacityMilliampHours: Int?
    let healthPercent: Double?
    let stateOfChargePercent: Double?

    let voltageMillivolts: Int?
    let currentMilliampsSigned: Int?
    let dischargeRateMilliamps: Int?
    let chargeRateWatts: Double?
    private(set) var inputPowerWatts: Double? = nil
    private(set) var inputPowerEvidence: BatteryInputPowerEvidence? = nil
    let dischargeRateWatts: Double?

    private(set) var rateBasedTimeRemainingMinutes: Int?
    let systemTimeRemainingMinutes: Int?
    let timeToFullMinutes: Int?

    let cycleCount: Int?
    private(set) var manufactureDate: Date?
    let temperatureCelsius: Double?

    let adapterMaxWatts: Int?
    let notes: [String]

    var presentationHealthPercent: Double? {
        BatteryCalculations.presentationPercent(healthPercent, maximumAllowed: 120)
    }

    var presentationStateOfChargePercent: Double? {
        BatteryCalculations.presentationPercent(stateOfChargePercent, maximumAllowed: 105)
    }

    var hasUsableCharge: Bool {
        presentationStateOfChargePercent != nil
    }

    var isLowCharge: Bool {
        presentationStateOfChargePercent.map { $0 <= 20 } ?? false
    }

    var presentationTemperatureCelsius: Double? {
        BatteryCalculations.plausibleTemperatureCelsius(temperatureCelsius)
    }

    var visibleInputPowerWatts: Double? {
        powerState.isExternallyPowered ? validatedInputPowerWatts : nil
    }

    var activePowerWatts: Double? {
        switch powerState {
        case .charging:
            return visibleInputPowerWatts ?? BatteryCalculations.plausibleWatts(chargeRateWatts)
        case .connectedDischarging:
            return visibleInputPowerWatts ?? BatteryCalculations.plausibleWatts(dischargeRateWatts)
        case .onBattery:
            return BatteryCalculations.plausibleWatts(dischargeRateWatts)
        case .connectedNotCharging, .fullOnAC:
            return visibleInputPowerWatts
        case .unknown:
            return nil
        }
    }

    private var validatedInputPowerWatts: Double? {
        BatteryCalculations.displayableInputPowerWatts(
            inputPowerWatts,
            evidence: inputPowerEvidence,
            adapterMaxWatts: adapterMaxWatts
        )
    }

    var activeCurrentMilliamps: Int? {
        if powerState == .charging {
            return BatteryCalculations.chargeRateMilliamps(from: currentMilliampsSigned)
        } else if powerState.isBatteryDischarging {
            return BatteryCalculations.plausibleDischargeRateMilliamps(dischargeRateMilliamps)
                ?? BatteryCalculations.dischargeRateMilliamps(from: currentMilliampsSigned)
        } else {
            return nil
        }
    }

    var validatedManufactureDate: Date? {
        BatteryCalculations.plausibleManufactureDate(manufactureDate, now: timestamp)
    }

    var validatedBatteryAgeComponents: DateComponents? {
        guard let manufactureDate = validatedManufactureDate else {
            return nil
        }

        return BatteryCalculations.batteryAgeComponents(from: manufactureDate, now: timestamp)
    }

    var energyUseComparisonValue: Double? {
        activePowerWatts ?? activeCurrentMilliamps.map { Double($0) / 1_000 }
    }

    var displayedTimeMinutes: Int? {
        if powerState.isBatteryDischarging {
            return BatteryCalculations.plausibleDurationMinutes(systemTimeRemainingMinutes)
                ?? BatteryCalculations.plausibleDurationMinutes(rateBasedTimeRemainingMinutes)
        } else if powerState == .charging {
            return BatteryCalculations.plausibleDurationMinutes(timeToFullMinutes)
        } else {
            return nil
        }
    }

    var statusDisplayTitle: String {
        guard isLowCharge else {
            return powerState.displayTitle
        }

        switch powerState {
        case .onBattery:
            return "On Battery Low Power"
        case .connectedDischarging:
            return "Connected, Discharging Low Power"
        case .charging, .connectedNotCharging, .fullOnAC, .unknown:
            return powerState.displayTitle
        }
    }

    var statusSecondaryText: String? {
        switch powerState {
        case .onBattery:
            return "Using internal battery"
        case .connectedDischarging:
            if let inputPowerSecondaryText {
                return "\(inputPowerSecondaryText), battery discharging"
            }
            return activePowerWatts.map { "Discharging at \(BatteryFormatting.watts($0))" } ?? "External power connected"
        case .charging:
            return inputPowerSecondaryText
                ?? BatteryCalculations.plausibleWatts(chargeRateWatts)
                .map { "Charging at \(BatteryFormatting.watts($0))" }
                ?? "External power connected"
        case .connectedNotCharging, .fullOnAC:
            return inputPowerSecondaryText ?? "External power connected"
        case .unknown:
            return nil
        }
    }

    var healthTone: BatteryLevelTone {
        BatteryLevelTone.forPercent(
            presentationHealthPercent,
            greenAbove: 95,
            midGreenMinimum: 90,
            greenYellowMinimum: 85,
            yellowMinimum: 80
        )
    }

    var chargeTone: BatteryLevelTone {
        BatteryLevelTone.forPercent(
            presentationStateOfChargePercent,
            greenAbove: 70,
            midGreenMinimum: 40,
            greenYellowMinimum: 20,
            yellowMinimum: 10
        )
    }

    var batterySymbolName: String {
        guard let stateOfChargePercent = presentationStateOfChargePercent else {
            return "questionmark"
        }

        switch stateOfChargePercent {
        case ...0:
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
        let timeTitle = powerState.timeTitle(charging: "Time to full", discharging: "Time left")
        lines.append("Timestamp: \(timestamp.formatted(date: .numeric, time: .standard))")
        lines.append("Power state: \(powerState.displayTitle)")
        lines.append("State of charge: \(BatteryFormatting.percent(presentationStateOfChargePercent))")
        lines.append("Health: \(BatteryFormatting.percent(presentationHealthPercent, decimals: 1))")
        lines.append("Full charge capacity: \(BatteryFormatting.milliampHours(fullChargeCapacityMilliampHours, allowsZero: false))")
        lines.append("Design capacity: \(BatteryFormatting.milliampHours(designCapacityMilliampHours, allowsZero: false))")
        lines.append("Current charge: \(BatteryFormatting.milliampHours(currentChargeMilliampHours))")
        let energyLabel = fullChargeCapacityWattHours == nil ? "Estimated Energy" : "Energy"
        lines.append("\(energyLabel): \(BatteryFormatting.compactWattHourPair(current: currentChargeWattHours, maximum: fullChargeCapacityWattHours))")
        lines.append("Voltage: \(BatteryFormatting.millivolts(voltageMillivolts))")
        lines.append("Signed current: \(BatteryFormatting.signedMilliamps(currentMilliampsSigned))")
        lines.append("\(timeTitle): \(BatteryFormatting.duration(minutes: displayedTimeMinutes))")
        lines.append("Active power: \(BatteryFormatting.watts(activePowerWatts))")
        lines.append("Input power: \(BatteryFormatting.watts(validatedInputPowerWatts))")
        lines.append("Charge rate: \(BatteryFormatting.watts(powerState == .charging ? chargeRateWatts : nil))")
        lines.append("Discharge rate: \(BatteryFormatting.watts(powerState.isBatteryDischarging ? dischargeRateWatts : nil))")
        lines.append("Adapter max power: \(BatteryFormatting.adapterWatts(adapterMaxWatts) ?? "Unavailable")")
        lines.append("Temperature: \(BatteryFormatting.temperature(presentationTemperatureCelsius, unitPreference: .celsius))")
        lines.append("Cycle count: \(BatteryCalculations.plausibleCycleCount(cycleCount).map(String.init) ?? "Unavailable")")
        lines.append("Manufacture date: \(BatteryFormatting.date(validatedManufactureDate))")

        if notes.isEmpty == false {
            lines.append("Notes:")
            lines.append(contentsOf: notes.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private var inputPowerSecondaryText: String? {
        visibleInputPowerWatts.map { "Input power \(BatteryFormatting.watts($0))" }
    }

    func updating(rateBasedTimeRemainingMinutes: Int?, timestamp: Date? = nil) -> BatterySnapshot {
        var updatedSnapshot = self
        updatedSnapshot.timestamp = timestamp ?? self.timestamp
        updatedSnapshot.rateBasedTimeRemainingMinutes = rateBasedTimeRemainingMinutes
        updatedSnapshot.manufactureDate = BatteryCalculations.plausibleManufactureDate(
            manufactureDate,
            now: updatedSnapshot.timestamp
        )
        return updatedSnapshot
    }
}
