import Foundation

struct BatteryReadOptions: Equatable, Sendable {
    var includesDiagnostics = false

    static let standard = BatteryReadOptions()
    static let diagnostics = BatteryReadOptions(includesDiagnostics: true)
}

struct BatteryReadResult: Sendable {
    let snapshot: BatterySnapshot?
    let rawSnapshotText: String?
    let parsedSnapshotText: String?
}

struct BatteryReadingService: Sendable {
    let powerSourceReader: PowerSourceReader
    let smartBatteryReader: SmartBatteryReader

    init(powerSourceReader: PowerSourceReader = PowerSourceReader(), smartBatteryReader: SmartBatteryReader = SmartBatteryReader()) {
        self.powerSourceReader = powerSourceReader
        self.smartBatteryReader = smartBatteryReader
    }

    func makeNotificationToken(handler: @escaping @Sendable () -> Void) -> PowerSourceReader.NotificationToken? {
        powerSourceReader.makeNotificationToken(handler: handler)
    }

    func read(at now: Date = .now, options: BatteryReadOptions = .standard) -> BatteryReadResult {
        let publicSnapshot = powerSourceReader.read()
        let smartBattery = smartBatteryReader.read()
        let resolvedPublicSnapshot = Self.resolvedPublicSnapshot(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        )

        guard let publicSnapshot = resolvedPublicSnapshot else {
            return BatteryReadResult(
                snapshot: nil,
                rawSnapshotText: options.includesDiagnostics ? "No internal battery detected." : nil,
                parsedSnapshotText: options.includesDiagnostics ? "Unsupported" : nil
            )
        }

        guard publicSnapshot.isPresent, publicSnapshot.isInternalBattery else {
            return BatteryReadResult(
                snapshot: nil,
                rawSnapshotText: options.includesDiagnostics ? prettyRawSnapshot(publicSnapshot: publicSnapshot, smartBattery: smartBattery) : nil,
                parsedSnapshotText: options.includesDiagnostics ? "Unsupported" : nil
            )
        }

        var notes: [String] = []
        if smartBattery == nil {
            notes.append("Detailed AppleSmartBattery properties were unavailable, so the app is showing public power-source data only.")
        }

        let fullChargeCapacityMilliampHours = smartBattery?.fullChargeCapacityMilliampHours
        let signedCurrentMilliamps = Self.reconciledSignedCurrentMilliamps(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: smartBattery?.signedCurrentMilliamps
        )
        let isCharged = Self.reconciledChargedState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: signedCurrentMilliamps,
            currentChargeMilliampHours: smartBattery?.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        )
        let publicStateOfChargePercent = Self.trustedPublicStateOfChargePercent(
            publicSnapshot: publicSnapshot,
            isCharged: isCharged
        )
        let currentChargeMilliampHours = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: smartBattery?.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            publicPercentage: publicStateOfChargePercent
        )
        let designCapacityMilliampHours = smartBattery?.designCapacityMilliampHours
        let voltageMillivolts = smartBattery?.voltageMillivolts
        let dischargeRateMilliamps = BatteryCalculations.dischargeRateMilliamps(from: signedCurrentMilliamps)
        let chargeRateMilliamps = BatteryCalculations.chargeRateMilliamps(from: signedCurrentMilliamps)
        let reportedTimeToFullMinutes = Self.reportedTimeToFullMinutes(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        )
        let computedTimeToFullMinutes = BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            chargeCurrentMilliamps: chargeRateMilliamps,
            reportedTimeToFullMinutes: nil
        )

        let powerState = Self.reconciledPowerState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            isCharged: isCharged,
            signedCurrentMilliamps: signedCurrentMilliamps,
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        )
        let powerFlags = BatteryCalculations.normalizedPowerFlags(for: powerState)
        let adapterMaxWatts = Self.displayableAdapterMaxWatts(
            smartBattery?.adapterMaxWatts,
            powerState: powerState
        )
        let inputPowerWatts = Self.displayableInputPowerWatts(
            smartBattery?.inputPowerWatts,
            evidence: smartBattery?.inputPowerEvidence,
            adapterMaxWatts: adapterMaxWatts,
            powerState: powerState
        )
        let powerRates = Self.displayablePowerRates(
            powerState: powerState,
            chargeRateWatts: Self.dynamicChargeRateWatts(
                smartBattery: smartBattery,
                voltageMillivolts: voltageMillivolts,
                signedCurrentMilliamps: signedCurrentMilliamps
            ),
            dischargeRateWatts: BatteryCalculations.dischargeRateWatts(
                voltageMillivolts: voltageMillivolts,
                signedCurrentMilliamps: signedCurrentMilliamps
            )
        )
        let timing = Self.displayableTiming(
            powerState: powerState,
            rateBasedTimeRemainingMinutes: BatteryCalculations.timeRemainingMinutes(
                currentChargeMilliampHours: currentChargeMilliampHours,
                dischargeRateMilliamps: dischargeRateMilliamps
            ),
            systemTimeRemainingMinutes: Self.reportedSystemTimeRemainingMinutes(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            ),
            timeToFullMinutes: Self.preferredTimeToFullMinutes(
                computedTimeToFullMinutes: computedTimeToFullMinutes,
                reportedTimeToFullMinutes: reportedTimeToFullMinutes
            )
        )

        if smartBattery?.temperatureCelsius == nil,
           smartBattery?.rawTemperature != nil {
            notes.append("Battery temperature was present but could not be converted confidently.")
        }

        let manufactureDate = BatteryCalculations.plausibleManufactureDate(smartBattery?.manufactureDate, now: now)
        let batteryAgeComponents = BatteryCalculations.batteryAgeComponents(from: manufactureDate, now: now)

        let snapshot = BatterySnapshot(
            timestamp: now,
            powerState: powerState,
            isCharging: powerFlags.isCharging,
            isExternalPowerConnected: powerFlags.isExternalPowerConnected,
            currentChargeMilliampHours: currentChargeMilliampHours,
            currentChargeWattHours: BatteryCalculations.wattHours(milliampHours: currentChargeMilliampHours, voltageMillivolts: voltageMillivolts),
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            fullChargeCapacityWattHours: BatteryCalculations.wattHours(milliampHours: fullChargeCapacityMilliampHours, voltageMillivolts: voltageMillivolts),
            designCapacityMilliampHours: designCapacityMilliampHours,
            designCapacityWattHours: BatteryCalculations.wattHours(milliampHours: designCapacityMilliampHours, voltageMillivolts: voltageMillivolts),
            healthPercent: BatteryCalculations.healthPercent(
                fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
                designCapacityMilliampHours: designCapacityMilliampHours
            ),
            stateOfChargePercent: BatteryCalculations.stateOfChargePercent(
                currentChargeMilliampHours: currentChargeMilliampHours,
                fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
                publicPercentage: publicStateOfChargePercent
            ),
            voltageMillivolts: voltageMillivolts,
            currentMilliampsSigned: signedCurrentMilliamps,
            dischargeRateMilliamps: dischargeRateMilliamps,
            chargeRateWatts: powerRates.chargeRateWatts,
            inputPowerWatts: inputPowerWatts,
            inputPowerEvidence: inputPowerWatts == nil ? nil : smartBattery?.inputPowerEvidence,
            dischargeRateWatts: powerRates.dischargeRateWatts,
            rateBasedTimeRemainingMinutes: timing.rateBasedTimeRemainingMinutes,
            systemTimeRemainingMinutes: timing.systemTimeRemainingMinutes,
            timeToFullMinutes: timing.timeToFullMinutes,
            cycleCount: smartBattery?.cycleCount,
            manufactureDate: manufactureDate,
            batteryAgeComponents: batteryAgeComponents,
            temperatureCelsius: smartBattery?.temperatureCelsius,
            adapterMaxWatts: adapterMaxWatts,
            notes: notes
        )

        return BatteryReadResult(
            snapshot: snapshot,
            rawSnapshotText: options.includesDiagnostics ? prettyRawSnapshot(publicSnapshot: publicSnapshot, smartBattery: smartBattery) : nil,
            parsedSnapshotText: options.includesDiagnostics ? snapshot.debugSummary : nil
        )
    }

    static func resolvedPublicSnapshot(
        publicSnapshot: PublicPowerSourceSnapshot?,
        smartBattery: SmartBatteryDetails?
    ) -> PublicPowerSourceSnapshot? {
        if let publicSnapshot,
           publicSnapshot.isPresent,
           publicSnapshot.isInternalBattery {
            return publicSnapshot
        }

        return fallbackPublicSnapshot(from: smartBattery)
    }

    static func fallbackPublicSnapshot(from smartBattery: SmartBatteryDetails?) -> PublicPowerSourceSnapshot? {
        guard let smartBattery else {
            return nil
        }

        let currentImpliesCharging = BatteryCalculations.chargeRateMilliamps(from: smartBattery.signedCurrentMilliamps) != nil
        let isDischarging = BatteryCalculations.dischargeRateMilliamps(from: smartBattery.signedCurrentMilliamps) != nil
        let reportsDisconnected = smartBattery.isExternalPowerConnected == false
        let isCharging = reportsDisconnected == false
            && isDischarging == false
            && (currentImpliesCharging || smartBattery.isCharging == true)
        let isCharged = Self.reconciledChargedState(
            publicIsCharged: false,
            smartIsFullyCharged: reportsDisconnected ? nil : smartBattery.isFullyCharged,
            signedCurrentMilliamps: smartBattery.signedCurrentMilliamps,
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicStateOfChargePercent: nil
        )
        let isExternalPowerConnected = Self.smartExternalPowerConnected(
            reportedExternalPowerConnected: smartBattery.isExternalPowerConnected,
            isCharging: isCharging,
            isCharged: isCharged,
            isDischarging: isDischarging,
            inputPowerWatts: smartBattery.inputPowerWatts,
            inputPowerEvidence: smartBattery.inputPowerEvidence,
            adapterMaxWatts: smartBattery.adapterMaxWatts
        )
        let trustedStateOfChargePercent = isCharged && isDischarging == false ? 100.0 : nil
        let stateOfChargePercent = BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours,
            publicPercentage: trustedStateOfChargePercent
        )
        let powerState = BatteryCalculations.derivePowerState(
            isCharging: isCharging,
            isCharged: isCharged,
            isExternalPowerConnected: isExternalPowerConnected,
            signedCurrentMilliamps: smartBattery.signedCurrentMilliamps,
            currentChargeMilliampHours: smartBattery.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery.fullChargeCapacityMilliampHours
        )
        let powerSourceState = isExternalPowerConnected ? "AC Power" : "Battery Power"

        return PublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: isCharging,
            isCharged: powerState == .fullOnAC,
            isExternalPowerConnected: isExternalPowerConnected,
            isInternalBattery: true,
            stateOfChargePercent: stateOfChargePercent,
            systemTimeRemainingMinutes: smartBattery.reportedTimeToEmptyMinutes,
            timeToFullMinutes: smartBattery.reportedTimeToFullMinutes,
            powerSourceState: powerSourceState,
            rawDescription: [:]
        )
    }

    static func reportedSystemTimeRemainingMinutes(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?
    ) -> Int? {
        firstDisplayableReportedMinutes(
            publicMinutes: publicSnapshot.systemTimeRemainingMinutes,
            smartMinutes: smartBattery?.reportedTimeToEmptyMinutes,
            zeroIsDisplayable: isEffectivelyEmptyForZeroTimeToEmpty(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            )
        )
    }

    static func reportedTimeToFullMinutes(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?
    ) -> Int? {
        firstDisplayableReportedMinutes(
            publicMinutes: publicSnapshot.timeToFullMinutes,
            smartMinutes: smartBattery?.reportedTimeToFullMinutes,
            zeroIsDisplayable: isEffectivelyFullForZeroTimeToFull(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            )
        )
    }

    static func trustedPublicStateOfChargePercent(
        publicSnapshot: PublicPowerSourceSnapshot,
        isCharged: Bool
    ) -> Double? {
        if isCharged {
            return 100
        }

        return publicSnapshot.stateOfChargePercent
    }

    static func reconciledChargedState(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?,
        signedCurrentMilliamps: Int?,
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?
    ) -> Bool {
        let hasDisconnectEvidence = hasExplicitDisconnectEvidence(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        )

        return reconciledChargedState(
            publicIsCharged: publicSnapshot.isCharged && hasDisconnectEvidence == false,
            smartIsFullyCharged: hasDisconnectEvidence ? nil : smartBattery?.isFullyCharged,
            signedCurrentMilliamps: signedCurrentMilliamps,
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            publicStateOfChargePercent: publicSnapshot.stateOfChargePercent
        )
    }

    static func reconciledPowerState(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?,
        isCharged: Bool,
        signedCurrentMilliamps: Int?,
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?
    ) -> BatteryPowerState {
        let signedCurrentMilliamps = Self.reconciledSignedCurrentMilliamps(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: signedCurrentMilliamps
        )
        let suppressSmartExternalPowerEvidence = hasExplicitDisconnectEvidence(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery
        )
        let isPublicCharging = publicSnapshot.isCharging && suppressSmartExternalPowerEvidence == false
        let isSmartCharging = smartBattery?.isCharging == true && suppressSmartExternalPowerEvidence == false
        let isCharging = isPublicCharging || isSmartCharging
        let isExternalPowerConnected = Self.reconciledExternalPowerConnected(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            isCharging: isCharging,
            isCharged: isCharged,
            signedCurrentMilliamps: signedCurrentMilliamps
        )

        return BatteryCalculations.derivePowerState(
            isCharging: isCharging,
            isCharged: isCharged,
            isExternalPowerConnected: isExternalPowerConnected,
            signedCurrentMilliamps: signedCurrentMilliamps,
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        )
    }

    static func reconciledSignedCurrentMilliamps(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?,
        signedCurrentMilliamps: Int?
    ) -> Int? {
        guard BatteryCalculations.chargeRateMilliamps(from: signedCurrentMilliamps) != nil,
              hasExplicitDisconnectEvidence(publicSnapshot: publicSnapshot, smartBattery: smartBattery) else {
            return signedCurrentMilliamps
        }

        return nil
    }

    static func reconciledPowerState(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?,
        signedCurrentMilliamps: Int?,
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?
    ) -> BatteryPowerState {
        reconciledPowerState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            isCharged: reconciledChargedState(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery,
                signedCurrentMilliamps: signedCurrentMilliamps,
                currentChargeMilliampHours: currentChargeMilliampHours,
                fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
            ),
            signedCurrentMilliamps: signedCurrentMilliamps,
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        )
    }

    static func displayableAdapterMaxWatts(_ adapterMaxWatts: Int?, powerState: BatteryPowerState) -> Int? {
        guard powerState.isExternallyPowered,
              let adapterMaxWatts = BatteryCalculations.plausibleAdapterWatts(adapterMaxWatts) else {
            return nil
        }

        return adapterMaxWatts
    }

    static func displayableInputPowerWatts(
        _ inputPowerWatts: Double?,
        evidence: BatteryInputPowerEvidence? = nil,
        adapterMaxWatts: Int? = nil,
        powerState: BatteryPowerState
    ) -> Double? {
        guard let inputPowerWatts = displayableInputPowerWatts(
            inputPowerWatts,
            evidence: evidence,
            adapterMaxWatts: adapterMaxWatts
        ) else {
            return nil
        }

        return powerState.isExternallyPowered ? inputPowerWatts : nil
    }

    static func displayablePowerRates(
        powerState: BatteryPowerState,
        chargeRateWatts: Double?,
        dischargeRateWatts: Double?
    ) -> (chargeRateWatts: Double?, dischargeRateWatts: Double?) {
        if powerState.isBatteryDischarging {
            return (nil, BatteryCalculations.plausibleWatts(dischargeRateWatts))
        } else if powerState == .charging {
            return (BatteryCalculations.plausibleWatts(chargeRateWatts), nil)
        } else {
            return (nil, nil)
        }
    }

    static func dynamicChargeRateWatts(
        smartBattery: SmartBatteryDetails?,
        voltageMillivolts: Int?,
        signedCurrentMilliamps: Int?
    ) -> Double? {
        chargeRateWattsWithinAdapterContract(
            voltageMillivolts: voltageMillivolts,
            signedCurrentMilliamps: signedCurrentMilliamps,
            adapterMaxWatts: smartBattery?.adapterMaxWatts
        )
    }

    static func displayableTiming(
        powerState: BatteryPowerState,
        rateBasedTimeRemainingMinutes: Int?,
        systemTimeRemainingMinutes: Int?,
        timeToFullMinutes: Int?
    ) -> (rateBasedTimeRemainingMinutes: Int?, systemTimeRemainingMinutes: Int?, timeToFullMinutes: Int?) {
        if powerState.isBatteryDischarging {
            return (
                BatteryCalculations.plausibleDurationMinutes(rateBasedTimeRemainingMinutes),
                BatteryCalculations.plausibleDurationMinutes(systemTimeRemainingMinutes),
                nil
            )
        } else if powerState == .charging {
            return (
                nil,
                nil,
                BatteryCalculations.plausibleDurationMinutes(timeToFullMinutes)
            )
        } else {
            return (nil, nil, nil)
        }
    }

    static func preferredTimeToFullMinutes(
        computedTimeToFullMinutes: Int?,
        reportedTimeToFullMinutes: Int?
    ) -> Int? {
        let computedTimeToFullMinutes = BatteryCalculations.plausibleDurationMinutes(computedTimeToFullMinutes)
        let reportedTimeToFullMinutes = BatteryCalculations.plausibleDurationMinutes(reportedTimeToFullMinutes)

        if computedTimeToFullMinutes == 0 {
            return 0
        }

        return reportedTimeToFullMinutes ?? computedTimeToFullMinutes
    }

    private static func reconciledExternalPowerConnected(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?,
        isCharging: Bool,
        isCharged: Bool,
        signedCurrentMilliamps: Int?
    ) -> Bool {
        if isCharging {
            return true
        }

        if isCharged {
            return true
        }

        if publicSnapshot.explicitlyReportsBatteryPower,
           BatteryCalculations.dischargeRateMilliamps(from: signedCurrentMilliamps) != nil {
            return false
        }

        if hasExplicitDisconnectEvidence(publicSnapshot: publicSnapshot, smartBattery: smartBattery) {
            return false
        }

        if trustedCounterBackedInputPowerWatts(smartBattery: smartBattery) != nil {
            return true
        }

        if trustedInputPowerWatts(smartBattery: smartBattery) != nil {
            return true
        }

        if publicSnapshot.reportedExternalPowerConnected {
            return true
        }

        if publicSnapshot.explicitlyReportsBatteryPower {
            return false
        }

        if let smartExternalPowerConnected = smartBattery?.isExternalPowerConnected {
            return smartExternalPowerConnected
        }

        return publicSnapshot.reportedExternalPowerConnected || isCharged
    }

    private static func smartExternalPowerConnected(
        reportedExternalPowerConnected: Bool?,
        isCharging: Bool,
        isCharged: Bool,
        isDischarging: Bool,
        inputPowerWatts: Double?,
        inputPowerEvidence: BatteryInputPowerEvidence?,
        adapterMaxWatts: Int?
    ) -> Bool {
        if isCharging {
            return true
        }

        if isCharged {
            return true
        }

        if displayableInputPowerWatts(
            inputPowerWatts,
            evidence: inputPowerEvidence,
            adapterMaxWatts: adapterMaxWatts
        ) != nil {
            return true
        }

        if let reportedExternalPowerConnected {
            return reportedExternalPowerConnected
        }

        if isDischarging {
            return false
        }

        return false
    }

    private static func hasExplicitDisconnectEvidence(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?
    ) -> Bool {
        publicSnapshot.explicitlyReportsBatteryPower
            || smartBattery?.isExternalPowerConnected == false
    }

    private static func trustedInputPowerWatts(smartBattery: SmartBatteryDetails?) -> Double? {
        displayableInputPowerWatts(
            smartBattery?.inputPowerWatts,
            evidence: smartBattery?.inputPowerEvidence,
            adapterMaxWatts: smartBattery?.adapterMaxWatts
        )
    }

    private static func trustedCounterBackedInputPowerWatts(smartBattery: SmartBatteryDetails?) -> Double? {
        guard smartBattery?.inputPowerEvidence == .counterBacked else {
            return nil
        }

        return trustedInputPowerWatts(smartBattery: smartBattery)
    }

    static func chargeRateWattsWithinAdapterContract(
        voltageMillivolts: Int?,
        signedCurrentMilliamps: Int?,
        adapterMaxWatts: Int?
    ) -> Double? {
        displayableCurrentDerivedChargeRateWatts(
            BatteryCalculations.chargeRateWatts(
                voltageMillivolts: voltageMillivolts,
                signedCurrentMilliamps: signedCurrentMilliamps
            ),
            adapterMaxWatts: adapterMaxWatts
        )
    }

    static func displayableCurrentDerivedChargeRateWatts(_ watts: Double?, adapterMaxWatts: Int?) -> Double? {
        BatteryCalculations.displayableLiveMeasuredInputPowerWatts(watts, adapterMaxWatts: adapterMaxWatts)
    }

    private static func displayableInputPowerWatts(
        _ inputPowerWatts: Double?,
        evidence: BatteryInputPowerEvidence? = nil,
        adapterMaxWatts: Int?
    ) -> Double? {
        switch evidence {
        case .counterBacked:
            return BatteryCalculations.displayableCounterBackedInputPowerWatts(
                inputPowerWatts,
                adapterMaxWatts: adapterMaxWatts
            )
        case nil:
            return BatteryCalculations.displayableInputPowerWatts(
                inputPowerWatts,
                adapterMaxWatts: adapterMaxWatts
            )
        }
    }

    private static func isEffectivelyFullForZeroTimeToFull(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?
    ) -> Bool {
        if reconciledChargedState(
            publicSnapshot: publicSnapshot,
            smartBattery: smartBattery,
            signedCurrentMilliamps: smartBattery?.signedCurrentMilliamps,
            currentChargeMilliampHours: smartBattery?.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: smartBattery?.fullChargeCapacityMilliampHours
        ) {
            return true
        }

        return BatteryCalculations.isEffectivelyFull(
            currentChargeMilliampHours: nil,
            fullChargeCapacityMilliampHours: nil,
            stateOfChargePercent: publicSnapshot.stateOfChargePercent
        )
    }

    private static func isEffectivelyEmptyForZeroTimeToEmpty(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?
    ) -> Bool {
        BatteryCalculations.isEffectivelyEmpty(
            currentChargeMilliampHours: smartBattery?.currentChargeMilliampHours,
            stateOfChargePercent: publicSnapshot.stateOfChargePercent
        )
    }

    private static func reconciledChargedState(
        publicIsCharged: Bool,
        smartIsFullyCharged: Bool?,
        signedCurrentMilliamps: Int?,
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?,
        publicStateOfChargePercent: Double?
    ) -> Bool {
        guard BatteryCalculations.dischargeRateMilliamps(from: signedCurrentMilliamps) == nil,
              publicIsCharged || smartIsFullyCharged == true else {
            return false
        }

        if let capacityEvidence = BatteryCalculations.chargedCapacityEvidence(
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        ) {
            return capacityEvidence
        }

        if let publicStateOfChargePercent,
           publicStateOfChargePercent.isFinite {
            return publicStateOfChargePercent >= 95 && publicStateOfChargePercent <= 105
        }

        return true
    }

    private static func firstDisplayableReportedMinutes(
        publicMinutes: Int?,
        smartMinutes: Int?,
        zeroIsDisplayable: Bool
    ) -> Int? {
        for reportedMinutes in [
            BatteryCalculations.plausibleDurationMinutes(publicMinutes),
            BatteryCalculations.plausibleDurationMinutes(smartMinutes)
        ] {
            guard let reportedMinutes else {
                continue
            }

            guard reportedMinutes == 0 else {
                return reportedMinutes
            }

            if zeroIsDisplayable {
                return 0
            }
        }

        return nil
    }

    private func prettyRawSnapshot(publicSnapshot: PublicPowerSourceSnapshot?, smartBattery: SmartBatteryDetails?) -> String {
        var sections: [String] = []

        sections.append("Public power source")
        sections.append(Self.renderDiagnosticValue(publicSnapshot?.rawDescription ?? [:]))
        sections.append("")
        sections.append("AppleSmartBattery")
        sections.append(Self.renderDiagnosticValue(smartBattery?.rawProperties ?? [:]))

        return sections.joined(separator: "\n")
    }

    static func renderDiagnosticValue(_ value: Any, indentLevel: Int = 0) -> String {
        let indent = String(repeating: "  ", count: indentLevel)

        switch value {
        case let dictionary as [String: Any]:
            if dictionary.isEmpty {
                return "\(indent){}"
            }

            return dictionary.keys.sorted().map { key in
                let renderedValue = renderDiagnosticValue(dictionary[key] ?? "nil", indentLevel: indentLevel + 1)
                if renderedValue.contains("\n") {
                    return "\(indent)\(key):\n\(renderedValue)"
                }

                return "\(indent)\(key): \(renderedValue.trimmingCharacters(in: .whitespaces))"
            }.joined(separator: "\n")
        case let dictionary as NSDictionary:
            var swiftDictionary: [String: Any] = [:]
            dictionary.forEach { key, value in
                if let key = key as? String {
                    swiftDictionary[key] = value
                }
            }
            return renderDiagnosticValue(swiftDictionary, indentLevel: indentLevel)
        case let array as [Any]:
            if array.isEmpty {
                return "\(indent)[]"
            }

            return array.map { item in
                let rendered = renderDiagnosticValue(item, indentLevel: indentLevel + 1)
                return "\(indent)- \(rendered.trimmingCharacters(in: .whitespacesAndNewlines))"
            }.joined(separator: "\n")
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "\(indent)\(number.boolValue)"
            }

            return "\(indent)\(number)"
        case let string as String:
            return "\(indent)\(string)"
        default:
            return "\(indent)\(String(describing: value))"
        }
    }
}

private extension PublicPowerSourceSnapshot {
    var explicitlyReportsBatteryPower: Bool {
        powerSourceState?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Battery Power") == .orderedSame
    }

    var reportedExternalPowerConnected: Bool {
        explicitlyReportsBatteryPower ? false : isExternalPowerConnected
    }
}
