import Foundation

enum BatteryReadOptions: Equatable, Sendable {
    case standard
    case diagnostics

    func merged(with options: BatteryReadOptions) -> BatteryReadOptions {
        self == .diagnostics || options == .diagnostics ? .diagnostics : .standard
    }
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

    @MainActor
    func makeNotificationToken(handler: @escaping @MainActor @Sendable () -> Void) -> PowerSourceReader.NotificationToken? {
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
            return unsupportedReadResult(rawSnapshotText: options == .diagnostics ? "No internal battery detected." : nil)
        }

        guard publicSnapshot.isPresent, publicSnapshot.isInternalBattery else {
            return unsupportedReadResult(rawSnapshotText: options == .diagnostics ? prettyRawSnapshot(publicSnapshot: publicSnapshot, smartBattery: smartBattery) : nil)
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
        let adapterMaxWatts = BatteryTelemetrySanitization.displayableAdapterMaxWatts(
            smartBattery?.adapterMaxWatts,
            powerState: powerState
        )
        let inputPowerWatts = BatteryTelemetrySanitization.displayableInputPowerWatts(
            smartBattery?.inputPowerWatts,
            evidence: smartBattery?.inputPowerEvidence,
            adapterMaxWatts: adapterMaxWatts,
            powerState: powerState
        )
        let powerRates = BatteryTelemetrySanitization.displayablePowerRates(
            powerState: powerState,
            chargeRateWatts: BatteryTelemetrySanitization.chargeRateWattsWithinAdapterContract(
                voltageMillivolts: voltageMillivolts,
                signedCurrentMilliamps: signedCurrentMilliamps,
                adapterMaxWatts: adapterMaxWatts
            ),
            dischargeRateWatts: BatteryCalculations.dischargeRateWatts(
                voltageMillivolts: voltageMillivolts,
                signedCurrentMilliamps: signedCurrentMilliamps
            )
        )
        let timing = BatteryTelemetrySanitization.displayableTiming(
            powerState: powerState,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: Self.reportedSystemTimeRemainingMinutes(
                publicSnapshot: publicSnapshot,
                smartBattery: smartBattery
            ),
            timeToFullMinutes: BatteryTelemetrySanitization.preferredTimeToFullMinutes(
                computedTimeToFullMinutes: computedTimeToFullMinutes,
                reportedTimeToFullMinutes: reportedTimeToFullMinutes
            )
        )

        if smartBattery?.temperatureCelsius == nil,
           smartBattery?.rawTemperature != nil {
            notes.append("Battery temperature was present but could not be converted confidently.")
        }

        let manufactureDate = BatteryCalculations.plausibleManufactureDate(smartBattery?.manufactureDate, now: now)

        let snapshot = BatterySnapshot(
            timestamp: now,
            powerState: powerState,
            isCharging: powerFlags.isCharging,
            isExternalPowerConnected: powerFlags.isExternalPowerConnected,
            currentChargeMilliampHours: currentChargeMilliampHours,
            currentChargeWattHours: BatteryCalculations.wattHours(
                milliampHours: currentChargeMilliampHours,
                voltageMillivolts: voltageMillivolts
            ),
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            fullChargeCapacityWattHours: nil,
            designCapacityMilliampHours: designCapacityMilliampHours,
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
            temperatureCelsius: smartBattery?.temperatureCelsius,
            adapterMaxWatts: adapterMaxWatts,
            notes: notes
        )

        return BatteryReadResult(
            snapshot: snapshot,
            rawSnapshotText: options == .diagnostics ? prettyRawSnapshot(publicSnapshot: publicSnapshot, smartBattery: smartBattery) : nil,
            parsedSnapshotText: options == .diagnostics ? snapshot.debugSummary : nil
        )
    }

    private func unsupportedReadResult(rawSnapshotText: String?) -> BatteryReadResult {
        BatteryReadResult(snapshot: nil, rawSnapshotText: rawSnapshotText, parsedSnapshotText: rawSnapshotText == nil ? nil : "Unsupported")
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
        let isExternalPowerConnected = isCharging
            || isCharged
            || BatteryCalculations.displayableInputPowerWatts(
                smartBattery.inputPowerWatts,
                evidence: smartBattery.inputPowerEvidence,
                adapterMaxWatts: smartBattery.adapterMaxWatts
            ) != nil
            || smartBattery.isExternalPowerConnected == true
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
            isCharged: isCharged
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

    private static func reconciledExternalPowerConnected(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?,
        isCharging: Bool,
        isCharged: Bool
    ) -> Bool {
        if isCharging || isCharged {
            return true
        }

        if hasExplicitDisconnectEvidence(publicSnapshot: publicSnapshot, smartBattery: smartBattery) {
            return false
        }

        if BatteryCalculations.displayableInputPowerWatts(
            smartBattery?.inputPowerWatts,
            evidence: smartBattery?.inputPowerEvidence,
            adapterMaxWatts: smartBattery?.adapterMaxWatts
        ) != nil {
            return true
        }

        if publicSnapshot.reportedExternalPowerConnected {
            return true
        }

        return smartBattery?.isExternalPowerConnected ?? false
    }

    private static func hasExplicitDisconnectEvidence(
        publicSnapshot: PublicPowerSourceSnapshot,
        smartBattery: SmartBatteryDetails?
    ) -> Bool {
        publicSnapshot.explicitlyReportsBatteryPower
            || smartBattery?.isExternalPowerConnected == false
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
        if let publicMinutes = BatteryCalculations.plausibleDurationMinutes(publicMinutes),
           publicMinutes != 0 || zeroIsDisplayable {
            return publicMinutes
        }

        if let smartMinutes = BatteryCalculations.plausibleDurationMinutes(smartMinutes),
           smartMinutes != 0 || zeroIsDisplayable {
            return smartMinutes
        }

        return nil
    }

    private func prettyRawSnapshot(publicSnapshot: PublicPowerSourceSnapshot?, smartBattery: SmartBatteryDetails?) -> String {
        [
            "Public power source",
            Self.renderDiagnosticValue(publicSnapshot?.rawDescription ?? [:]),
            "",
            "AppleSmartBattery",
            Self.renderDiagnosticValue(smartBattery?.rawProperties ?? [:])
        ].joined(separator: "\n")
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
