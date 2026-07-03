import Foundation

enum BatteryLevelTone: String, Equatable, Sendable {
    case red
    case yellow
    case greenYellow
    case midGreen
    case green
}

enum BatteryInputPowerEvidence: String, Codable, Equatable, Sendable {
    case counterBacked
}

struct BatterySnapshot: Codable, Equatable, Sendable {
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
    let inputPowerWatts: Double?
    let inputPowerEvidence: BatteryInputPowerEvidence?
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

    init(
        timestamp: Date,
        powerState: BatteryPowerState,
        isCharging: Bool,
        isExternalPowerConnected: Bool,
        currentChargeMilliampHours: Int?,
        currentChargeWattHours: Double?,
        fullChargeCapacityMilliampHours: Int?,
        fullChargeCapacityWattHours: Double?,
        designCapacityMilliampHours: Int?,
        designCapacityWattHours: Double?,
        healthPercent: Double?,
        stateOfChargePercent: Double?,
        voltageMillivolts: Int?,
        currentMilliampsSigned: Int?,
        dischargeRateMilliamps: Int?,
        chargeRateWatts: Double?,
        inputPowerWatts: Double? = nil,
        inputPowerEvidence: BatteryInputPowerEvidence? = nil,
        dischargeRateWatts: Double?,
        rateBasedTimeRemainingMinutes: Int?,
        systemTimeRemainingMinutes: Int?,
        timeToFullMinutes: Int?,
        cycleCount: Int?,
        manufactureDate: Date?,
        batteryAgeComponents: DateComponents?,
        temperatureCelsius: Double?,
        adapterMaxWatts: Int?,
        notes: [String]
    ) {
        self.timestamp = timestamp
        self.powerState = powerState
        self.isCharging = isCharging
        self.isExternalPowerConnected = isExternalPowerConnected
        self.currentChargeMilliampHours = currentChargeMilliampHours
        self.currentChargeWattHours = currentChargeWattHours
        self.fullChargeCapacityMilliampHours = fullChargeCapacityMilliampHours
        self.fullChargeCapacityWattHours = fullChargeCapacityWattHours
        self.designCapacityMilliampHours = designCapacityMilliampHours
        self.designCapacityWattHours = designCapacityWattHours
        self.healthPercent = healthPercent
        self.stateOfChargePercent = stateOfChargePercent
        self.voltageMillivolts = voltageMillivolts
        self.currentMilliampsSigned = currentMilliampsSigned
        self.dischargeRateMilliamps = dischargeRateMilliamps
        self.chargeRateWatts = chargeRateWatts
        self.inputPowerWatts = inputPowerWatts
        self.inputPowerEvidence = inputPowerEvidence
        self.dischargeRateWatts = dischargeRateWatts
        self.rateBasedTimeRemainingMinutes = rateBasedTimeRemainingMinutes
        self.systemTimeRemainingMinutes = systemTimeRemainingMinutes
        self.timeToFullMinutes = timeToFullMinutes
        self.cycleCount = cycleCount
        self.manufactureDate = manufactureDate
        self.batteryAgeComponents = batteryAgeComponents
        self.temperatureCelsius = temperatureCelsius
        self.adapterMaxWatts = adapterMaxWatts
        self.notes = notes
    }

    var presentationHealthPercent: Double? {
        BatteryCalculations.presentationPercent(healthPercent, maximumAllowed: 120)
    }

    var presentationStateOfChargePercent: Double? {
        BatteryCalculations.presentationPercent(stateOfChargePercent, maximumAllowed: 105)
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
            return BatteryCalculations.plausibleDurationMinutes(rateBasedTimeRemainingMinutes)
                ?? BatteryCalculations.plausibleDurationMinutes(systemTimeRemainingMinutes)
        } else if powerState == .charging {
            return BatteryCalculations.plausibleDurationMinutes(timeToFullMinutes)
        } else {
            return nil
        }
    }

    var statusDisplayTitle: String {
        switch powerState {
        case .onBattery:
            if let stateOfChargePercent = presentationStateOfChargePercent, stateOfChargePercent <= 20 {
                return "On Battery Low Power"
            }
            return "On Battery"
        case .charging:
            return "Charging"
        case .connectedDischarging:
            if let stateOfChargePercent = presentationStateOfChargePercent, stateOfChargePercent <= 20 {
                return "Connected, Discharging Low Power"
            }
            return "Connected, Discharging"
        case .connectedNotCharging:
            return "Connected, Not Charging"
        case .fullOnAC:
            return "Fully Charged"
        case .unknown:
            return "Unknown"
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
        guard let healthPercent = presentationHealthPercent else {
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
        guard let stateOfChargePercent = presentationStateOfChargePercent else {
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
        lines.append("Timestamp: \(timestamp.formatted(date: .numeric, time: .standard))")
        lines.append("Power state: \(powerState.displayTitle)")
        lines.append("State of charge: \(BatteryFormatting.percent(presentationStateOfChargePercent))")
        lines.append("Health: \(BatteryFormatting.percent(presentationHealthPercent, decimals: 1))")
        lines.append("Full charge capacity: \(BatteryFormatting.milliampHours(fullChargeCapacityMilliampHours, allowsZero: false))")
        lines.append("Design capacity: \(BatteryFormatting.milliampHours(designCapacityMilliampHours, allowsZero: false))")
        lines.append("Current charge: \(BatteryFormatting.milliampHours(currentChargeMilliampHours))")
        lines.append("Energy: \(BatteryFormatting.compactWattHourPair(current: currentChargeWattHours, maximum: fullChargeCapacityWattHours))")
        lines.append("Voltage: \(BatteryFormatting.millivolts(voltageMillivolts))")
        lines.append("Signed current: \(BatteryFormatting.signedMilliamps(currentMilliampsSigned))")
        lines.append("\(debugTimeTitle): \(BatteryFormatting.duration(minutes: displayedTimeMinutes))")
        lines.append("Active power: \(BatteryFormatting.watts(activePowerWatts))")
        lines.append("Input power: \(BatteryFormatting.watts(validatedInputPowerWatts))")
        lines.append("Charge rate: \(BatteryFormatting.watts(powerState == .charging ? chargeRateWatts : nil))")
        lines.append("Discharge rate: \(BatteryFormatting.watts(powerState.isBatteryDischarging ? dischargeRateWatts : nil))")
        lines.append("Adapter max power: \(Self.debugAdapterMaxWatts(adapterMaxWatts))")
        lines.append("Temperature: \(BatteryFormatting.temperature(presentationTemperatureCelsius, unitPreference: .celsius))")
        lines.append("Cycle count: \(BatteryCalculations.plausibleCycleCount(cycleCount).map(String.init) ?? "Unavailable")")
        lines.append("Manufacture date: \(BatteryFormatting.date(validatedManufactureDate))")

        if notes.isEmpty == false {
            lines.append("Notes:")
            lines.append(contentsOf: notes.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private var debugTimeTitle: String {
        powerState.timeTitle(charging: "Time to full", discharging: "Time left")
    }

    private var inputPowerSecondaryText: String? {
        visibleInputPowerWatts.map { "Input power \(BatteryFormatting.watts($0))" }
    }

    private static func debugAdapterMaxWatts(_ value: Int?) -> String {
        guard let value = BatteryCalculations.plausibleAdapterWatts(value) else {
            return "Unavailable"
        }

        return "\(value) W"
    }

    func updating(rateBasedTimeRemainingMinutes: Int?, timestamp: Date? = nil) -> BatterySnapshot {
        let nextTimestamp = timestamp ?? self.timestamp
        let nextManufactureDate = BatteryCalculations.plausibleManufactureDate(manufactureDate, now: nextTimestamp)
        let nextBatteryAgeComponents = BatteryCalculations.batteryAgeComponents(
            from: nextManufactureDate,
            now: nextTimestamp
        )

        return BatterySnapshot(
            timestamp: nextTimestamp,
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
            inputPowerWatts: inputPowerWatts,
            inputPowerEvidence: inputPowerEvidence,
            dischargeRateWatts: dischargeRateWatts,
            rateBasedTimeRemainingMinutes: rateBasedTimeRemainingMinutes,
            systemTimeRemainingMinutes: systemTimeRemainingMinutes,
            timeToFullMinutes: timeToFullMinutes,
            cycleCount: cycleCount,
            manufactureDate: nextManufactureDate,
            batteryAgeComponents: nextBatteryAgeComponents,
            temperatureCelsius: temperatureCelsius,
            adapterMaxWatts: adapterMaxWatts,
            notes: notes
        )
    }
}
