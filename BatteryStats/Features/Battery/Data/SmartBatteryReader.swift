import Foundation
import IOKit

struct SmartBatteryDetails {
    let currentChargeMilliampHours: Int?
    let fullChargeCapacityMilliampHours: Int?
    let designCapacityMilliampHours: Int?
    let cycleCount: Int?
    let voltageMillivolts: Int?
    let signedCurrentMilliamps: Int?
    let reportedTimeToEmptyMinutes: Int?
    let reportedTimeToFullMinutes: Int?
    let isExternalPowerConnected: Bool?
    let isCharging: Bool?
    let isFullyCharged: Bool?
    let rawTemperature: Int?
    let temperatureCelsius: Double?
    let manufactureDate: Date?
    let inputPowerWatts: Double?
    let inputPowerEvidence: BatteryInputPowerEvidence?
    let adapterMaxWatts: Int?
    let rawProperties: [String: Any]
}

final class SmartBatteryReader: @unchecked Sendable {
    private enum PropertyCandidate {
        case root(String)
        case nested(String, String)
        case nestedRootOnly(String, String)
    }

    func read() -> SmartBatteryDetails? {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return nil
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return nil
        }

        defer {
            IOObjectRelease(service)
        }

        var propertiesReference: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propertiesReference, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let rawProperties = propertiesReference?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let mergedProperties = Self.mergedProperties(
            rootProperties: rawProperties,
            packProperties: childPackProperties(from: service),
            chargerProperties: properties(forFirstServiceMatching: "AppleChargerData")
        )
        return parse(properties: mergedProperties)
    }

    static func mergedProperties(
        rootProperties: [String: Any],
        packProperties: [String: Any]?,
        chargerProperties: [String: Any]? = nil
    ) -> [String: Any] {
        var mergedProperties = rootProperties

        if let packProperties,
           let packBatteryData = stringDictionary(from: packProperties["BatteryData"]) {
            var mergedBatteryData = stringDictionary(from: rootProperties["BatteryData"]) ?? [:]

            for (key, value) in packBatteryData where mergedBatteryData[key] == nil && key != "ManufactureDate" {
                mergedBatteryData[key] = value
            }

            mergedProperties["BatteryData"] = mergedBatteryData
            mergedProperties["AppleSmartBatteryPack"] = packProperties
        }

        if let chargerProperties,
           let chargerData = stringDictionary(from: chargerProperties["ChargerData"])?.nilIfEmpty ?? chargerProperties.nilIfEmpty {
            mergedProperties["AppleChargerData"] = chargerData
        }

        return mergedProperties
    }

    func parse(properties rawProperties: [String: Any]) -> SmartBatteryDetails {
        let currentChargeMilliampHours = physicalCapacityInteger(
            for: [
                .root("AppleRawCurrentCapacity"),
                .nested("BatteryData", "AppleRawCurrentCapacity"),
                .nested("BatteryData", "RemainingCapacity")
            ],
            legacyFallbacks: [.root("CurrentCapacity")],
            allowsZero: true,
            in: rawProperties
        )
        let fullChargeCapacityMilliampHours = physicalCapacityInteger(
            for: [
                .root("AppleRawMaxCapacity"),
                .nested("BatteryData", "AppleRawMaxCapacity"),
                .nested("BatteryData", "FullChargeCapacity"),
                .root("NominalChargeCapacity"),
                .nested("BatteryData", "NominalChargeCapacity")
            ],
            legacyFallbacks: [.root("MaxCapacity")],
            in: rawProperties
        )
        let designCapacityMilliampHours = physicalCapacityInteger(
            for: [.root("DesignCapacity"), .nested("BatteryData", "DesignCapacity")],
            in: rawProperties
        )
        let cycleCount = plausibleInteger(for: [.root("CycleCount"), .nested("BatteryData", "CycleCount"), .nested("LegacyBatteryInfo", "Cycle Count")], in: rawProperties) {
            BatteryCalculations.plausibleCycleCount($0)
        }
        let voltageMillivolts = plausibleInteger(for: [.root("Voltage"), .nested("BatteryData", "Voltage"), .nested("LegacyBatteryInfo", "Voltage")], in: rawProperties) {
            BatteryCalculations.plausibleVoltageMillivolts($0)
        }
        let signedCurrentMilliamps = plausibleInteger(
            for: [
                .root("InstantAmperage"),
                .nested("BatteryData", "InstantAmperage"),
                .nested("BatteryData", "Amperage"),
                .nested("LegacyBatteryInfo", "Amperage"),
                .root("Amperage")
            ],
            in: rawProperties
        ) {
            BatteryCalculations.plausibleSignedCurrentMilliamps($0)
        }
        let rawTimeRemainingMinutes = plausibleInteger(
            for: [.root("TimeRemaining"), .nested("BatteryData", "TimeRemaining")],
            in: rawProperties
        ) {
            BatteryCalculations.plausibleDurationMinutes($0)
        }
        let currentImpliesCharging = BatteryCalculations.chargeRateMilliamps(from: signedCurrentMilliamps) != nil
        let currentImpliesDischarging = BatteryCalculations.dischargeRateMilliamps(from: signedCurrentMilliamps) != nil
        let reportedTimeToEmptyMinutes = plausibleInteger(
            for: [
                .root("AvgTimeToEmpty"),
                .nested("BatteryData", "AvgTimeToEmpty"),
                .root("TimeToEmpty"),
                .nested("BatteryData", "TimeToEmpty")
            ],
            in: rawProperties
        ) {
            BatteryCalculations.plausibleDurationMinutes($0)
        } ?? (currentImpliesDischarging ? rawTimeRemainingMinutes : nil)
        let reportedTimeToFullMinutes = plausibleInteger(
            for: [
                .root("AvgTimeToFull"),
                .nested("BatteryData", "AvgTimeToFull"),
                .root("TimeToFull"),
                .nested("BatteryData", "TimeToFull")
            ],
            in: rawProperties
        ) {
            BatteryCalculations.plausibleDurationMinutes($0)
        } ?? (currentImpliesCharging ? rawTimeRemainingMinutes : nil)
        let isExternalPowerConnected = boolean(
            for: [
                .root("ExternalConnected"),
                .root("AppleRawExternalConnected"),
                .nested("BatteryData", "ExternalConnected")
            ],
            in: rawProperties
        )
        let isCharging = boolean(
            for: [
                .root("IsCharging"),
                .nested("ChargerData", "IsCharging"),
                .nested("AppleChargerData", "IsCharging"),
                .nested("BatteryData", "IsCharging")
            ],
            in: rawProperties
        )
        let isFullyCharged = boolean(
            for: [
                .root("FullyCharged"),
                .nested("BatteryData", "FullyCharged")
            ],
            in: rawProperties
        )
        let rawTemperature = rawTemperatureValue(for: [.root("Temperature"), .nested("BatteryData", "Temperature")], in: rawProperties)
        let decodedManufactureDate = manufactureDate(
            for: [.root("ManufactureDate"), .nestedRootOnly("BatteryData", "ManufactureDate")],
            in: rawProperties
        )
        let adapterDetailsWatts = Self.stringDictionary(from: rawProperties["AdapterDetails"])
            .flatMap { adapterWatts(from: $0) }
        let negotiatedWatts = negotiatedAdapterContractWatts(in: rawProperties)
        let reportedWatts = reconciledReportedAdapterMaxWatts(
            rawWatts: rawAdapterMaxWatts(in: rawProperties),
            adapterDetailsWatts: adapterDetailsWatts
        )
        let adapterMaxWatts = reconciledAdapterMaxWatts(
            negotiatedWatts: negotiatedWatts,
            reportedWatts: reportedWatts,
            properties: rawProperties
        )
        let inputPower = inputPower(in: rawProperties, adapterMaxWatts: adapterMaxWatts)

        return SmartBatteryDetails(
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            designCapacityMilliampHours: designCapacityMilliampHours,
            cycleCount: cycleCount,
            voltageMillivolts: voltageMillivolts,
            signedCurrentMilliamps: signedCurrentMilliamps,
            reportedTimeToEmptyMinutes: reportedTimeToEmptyMinutes,
            reportedTimeToFullMinutes: reportedTimeToFullMinutes,
            isExternalPowerConnected: isExternalPowerConnected,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            rawTemperature: rawTemperature,
            temperatureCelsius: BatteryCalculations.temperatureCelsius(fromRaw: rawTemperature),
            manufactureDate: decodedManufactureDate,
            inputPowerWatts: inputPower?.watts,
            inputPowerEvidence: inputPower?.evidence,
            adapterMaxWatts: adapterMaxWatts,
            rawProperties: rawProperties
        )
    }

    private func plausibleInteger(
        for candidates: [PropertyCandidate],
        in properties: [String: Any],
        transform: (Int) -> Int?
    ) -> Int? {
        firstValue(for: candidates, in: properties) { rawValue in
            guard let parsed = SignedIntegerNormalizer.normalize(rawValue) else {
                return nil
            }

            return transform(parsed)
        }
    }

    private func rawTemperatureValue(for candidates: [PropertyCandidate], in properties: [String: Any]) -> Int? {
        plausibleInteger(for: candidates, in: properties) {
            BatteryCalculations.temperatureCelsius(fromRaw: $0) == nil ? nil : $0
        }
    }

    private func manufactureDate(
        for candidates: [PropertyCandidate],
        in properties: [String: Any]
    ) -> Date? {
        firstValue(for: candidates, in: properties) { rawValue in
            guard let parsed = SignedIntegerNormalizer.normalize(rawValue) else {
                return nil
            }

            return ManufactureDateDecoder.decode(rawValue: parsed)
        }
    }

    private struct AdapterWattsReading {
        let watts: Int
        let hasDerivedEvidence: Bool
    }

    private func rawAdapterMaxWatts(in properties: [String: Any]) -> AdapterWattsReading? {
        let adapterDetails = arrayDictionaries(from: properties["AppleRawAdapterDetails"])

        if let bestAdapterIndex = bestAdapterIndex(in: properties),
           adapterDetails.indices.contains(bestAdapterIndex),
           let watts = adapterWatts(from: adapterDetails[bestAdapterIndex]) {
            return watts
        }

        for adapterDetails in adapterDetails {
            if let watts = adapterWatts(from: adapterDetails) {
                return watts
            }
        }

        return nil
    }

    private func bestAdapterIndex(in properties: [String: Any]) -> Int? {
        guard let index = SignedIntegerNormalizer.normalize(properties["BestAdapterIndex"]),
              index >= 0 else {
            return nil
        }

        return index
    }

    private func adapterWatts(from adapterDetails: [String: Any]) -> AdapterWattsReading? {
        reconciledAdapterWatts(
            reportedWatts: BatteryCalculations.plausibleAdapterWatts(
                SignedIntegerNormalizer.normalize(adapterDetails["Watts"])
            ),
            derivedWatts: derivedAdapterWatts(from: adapterDetails)
        )
    }

    private func negotiatedAdapterContractWatts(in properties: [String: Any]) -> Int? {
        let milliwatts = milliwattsFrom(
            voltageCandidate: .nested("PowerDistribution", "IPDInputVoltage"),
            currentCandidate: .nested("PowerDistribution", "IPDInputCurrent"),
            in: properties
        ) ?? corroboratedIPDInputPowerMilliwatts(in: properties)

        guard let milliwatts else {
            return nil
        }

        return adapterWatts(fromWatts: milliwatts / 1_000)
    }

    private func corroboratedIPDInputPowerMilliwatts(in properties: [String: Any]) -> Double? {
        guard hasLiveSystemPowerInCounter(in: properties),
              let ipdInputPower = positiveInteger(for: [.nested("PowerDistribution", "IPDInputPower")], in: properties),
              let systemPowerIn = positiveInteger(for: [.nested("PowerTelemetryData", "SystemPowerIn")], in: properties) else {
            return nil
        }

        let negotiatedMilliwatts = Double(ipdInputPower)
        let systemMilliwatts = Double(systemPowerIn)
        guard isWithinTelemetryTolerance(systemMilliwatts, referenceMilliwatts: negotiatedMilliwatts) else {
            return nil
        }

        return negotiatedMilliwatts
    }

    private func reconciledAdapterMaxWatts(
        negotiatedWatts: Int?,
        reportedWatts: AdapterWattsReading?,
        properties: [String: Any]
    ) -> Int? {
        guard let reportedWatts else {
            return negotiatedWatts
        }

        guard let negotiatedWatts else {
            return reportedWatts.watts
        }

        if adapterWattsDifferBeyondStaleTolerance(negotiatedWatts, reportedWatts.watts) {
            if negotiatedWatts > reportedWatts.watts,
               reportedWatts.hasDerivedEvidence,
               counterBackedInputPowerCorroboratesNegotiatedPower(negotiatedWatts, in: properties) == false {
                return reportedWatts.watts
            }

            return negotiatedWatts
        }

        return reportedWatts.watts
    }

    private func reconciledReportedAdapterMaxWatts(
        rawWatts: AdapterWattsReading?,
        adapterDetailsWatts: AdapterWattsReading?
    ) -> AdapterWattsReading? {
        guard let rawWatts else {
            return adapterDetailsWatts
        }

        guard let adapterDetailsWatts else {
            return rawWatts
        }

        guard rawWatts.watts != adapterDetailsWatts.watts else {
            return AdapterWattsReading(
                watts: rawWatts.watts,
                hasDerivedEvidence: rawWatts.hasDerivedEvidence || adapterDetailsWatts.hasDerivedEvidence
            )
        }

        if rawWatts.hasDerivedEvidence != adapterDetailsWatts.hasDerivedEvidence {
            return rawWatts.hasDerivedEvidence ? rawWatts : adapterDetailsWatts
        }

        return rawWatts.watts < adapterDetailsWatts.watts ? rawWatts : adapterDetailsWatts
    }

    private func reconciledAdapterWatts(reportedWatts: Int?, derivedWatts: Int?) -> AdapterWattsReading? {
        guard let reportedWatts else {
            return derivedWatts.map { AdapterWattsReading(watts: $0, hasDerivedEvidence: true) }
        }

        guard let derivedWatts else {
            return AdapterWattsReading(watts: reportedWatts, hasDerivedEvidence: false)
        }

        if adapterWattsDifferBeyondStaleTolerance(reportedWatts, derivedWatts) {
            return AdapterWattsReading(watts: derivedWatts, hasDerivedEvidence: true)
        }

        return AdapterWattsReading(watts: reportedWatts, hasDerivedEvidence: true)
    }

    private func adapterWattsDifferBeyondStaleTolerance(_ first: Int, _ second: Int) -> Bool {
        let tolerance = max(2, Int((Double(max(first, second)) * 0.05).rounded(.up)))
        return abs(first - second) > tolerance
    }

    private func derivedAdapterWatts(from adapterDetails: [String: Any]) -> Int? {
        guard let voltageMillivolts = plausibleInteger(
            for: [.root("Voltage"), .root("AdapterVoltage")],
            in: adapterDetails,
            transform: BatteryCalculations.plausibleVoltageMillivolts
        ),
              let currentMilliamps = plausibleInteger(
                  for: [.root("Current"), .root("AdapterCurrent")],
                  in: adapterDetails,
                  transform: { Self.plausibleInputCurrentMagnitudeMilliamps($0).flatMap { $0 > 0 ? $0 : nil } }
              ) else {
            return nil
        }

        let watts = (Double(voltageMillivolts) * Double(currentMilliamps)) / 1_000_000
        return adapterWatts(fromWatts: watts)
    }

    private func adapterWatts(fromWatts watts: Double) -> Int? {
        guard watts.isFinite,
              watts >= 0,
              watts <= Double(Int.max) else {
            return nil
        }

        return BatteryCalculations.plausibleAdapterWatts(Int(watts.rounded(.toNearestOrAwayFromZero)))
    }

    private func inputPower(
        in properties: [String: Any],
        adapterMaxWatts: Int?
    ) -> (watts: Double, evidence: BatteryInputPowerEvidence?)? {
        if let watts = wattsFromCorroboratedSystemPowerIn(in: properties, adapterMaxWatts: adapterMaxWatts) {
            return (watts, .counterBacked)
        }

        if let watts = BatteryCalculations.displayableInputPowerWatts(
            liveSystemTelemetryWatts(in: properties, adapterMaxWatts: adapterMaxWatts),
            adapterMaxWatts: adapterMaxWatts
        ) {
            return (watts, nil)
        }

        return nil
    }

    private func wattsFromCorroboratedSystemPowerIn(in properties: [String: Any], adapterMaxWatts: Int?) -> Double? {
        guard let milliwatts = counterBackedSystemPowerInMilliwatts(in: properties) else {
            return nil
        }

        let watts = milliwatts / 1_000
        guard isDistinctFromCounterBackedNegotiatedInputPower(milliwatts: milliwatts, in: properties),
              isTrustedCounterBackedSystemPowerIn(milliwatts: milliwatts, in: properties, adapterMaxWatts: adapterMaxWatts),
              let displayableWatts = displayableCorroboratedSystemPowerInWatts(
                  watts,
                  milliwatts: milliwatts,
                  in: properties,
                  adapterMaxWatts: adapterMaxWatts
              ) else {
            return nil
        }

        return displayableWatts
    }

    private func liveSystemTelemetryWatts(in properties: [String: Any], adapterMaxWatts: Int?) -> Double? {
        guard let milliwatts = liveSystemTelemetryMilliwatts(in: properties),
              isDistinctFromNegotiatedInputPower(milliwatts: milliwatts, in: properties),
              isDistinctFromAdapterCapability(milliwatts: milliwatts, adapterMaxWatts: adapterMaxWatts) else {
            return nil
        }

        return BatteryCalculations.plausibleWatts(milliwatts / 1_000)
    }

    private func liveSystemTelemetryMilliwatts(in properties: [String: Any]) -> Double? {
        milliwattsFrom(
            voltageCandidate: .nested("PowerTelemetryData", "SystemVoltageIn"),
            currentCandidate: .nested("PowerTelemetryData", "SystemCurrentIn"),
            in: properties
        )
    }

    private func isTrustedCounterBackedSystemPowerIn(
        milliwatts: Double,
        in properties: [String: Any],
        adapterMaxWatts: Int?
    ) -> Bool {
        guard isNearHighAdapterCapability(milliwatts: milliwatts, adapterMaxWatts: adapterMaxWatts) else {
            return true
        }

        return liveSystemTelemetryCorroborates(milliwatts: milliwatts, in: properties)
    }

    private func displayableCorroboratedSystemPowerInWatts(
        _ watts: Double,
        milliwatts: Double,
        in properties: [String: Any],
        adapterMaxWatts: Int?
    ) -> Double? {
        if liveSystemTelemetryCorroborates(milliwatts: milliwatts, in: properties) {
            return BatteryCalculations.displayableLiveMeasuredInputPowerWatts(watts, adapterMaxWatts: adapterMaxWatts)
        }

        return BatteryCalculations.displayableCounterBackedInputPowerWatts(watts, adapterMaxWatts: adapterMaxWatts)
    }

    private func counterBackedInputPowerCorroboratesNegotiatedPower(_ negotiatedWatts: Int, in properties: [String: Any]) -> Bool {
        guard let systemMilliwatts = counterBackedSystemPowerInMilliwatts(in: properties) else {
            return false
        }

        let negotiatedMilliwatts = Double(negotiatedWatts) * 1_000
        guard isWithinTelemetryTolerance(systemMilliwatts, referenceMilliwatts: negotiatedMilliwatts) else {
            return false
        }

        return liveSystemTelemetryCorroborates(milliwatts: systemMilliwatts, in: properties)
    }

    private func counterBackedSystemPowerInMilliwatts(in properties: [String: Any]) -> Double? {
        guard hasLiveSystemPowerInCounter(in: properties),
              let milliwatts = positiveMilliwatts(for: [.nested("PowerTelemetryData", "SystemPowerIn")], in: properties) else {
            return nil
        }

        return milliwatts
    }

    private func liveSystemTelemetryCorroborates(milliwatts: Double, in properties: [String: Any]) -> Bool {
        guard let corroboratingMilliwatts = liveSystemTelemetryMilliwatts(in: properties) else {
            return false
        }

        return isWithinTelemetryTolerance(corroboratingMilliwatts, referenceMilliwatts: milliwatts)
    }

    private func isWithinTelemetryTolerance(_ milliwatts: Double, referenceMilliwatts: Double) -> Bool {
        let toleranceMilliwatts = max(1_000.0, referenceMilliwatts * 0.05)
        return abs(milliwatts - referenceMilliwatts) <= toleranceMilliwatts
    }

    private func isNearHighAdapterCapability(milliwatts: Double, adapterMaxWatts: Int?) -> Bool {
        guard let adapterMaxWatts = BatteryCalculations.plausibleAdapterWatts(adapterMaxWatts),
              adapterMaxWatts >= 90 else {
            return false
        }

        let adapterMilliwatts = Double(adapterMaxWatts) * 1_000
        return milliwatts >= adapterMilliwatts * 0.95
            && milliwatts <= adapterMilliwatts * 1.15
    }

    private func hasLiveSystemPowerInCounter(in properties: [String: Any]) -> Bool {
        positiveInteger(for: [.nested("PowerTelemetryData", "SystemPowerInAccumulatorCount")], in: properties) != nil
    }

    private func isDistinctFromNegotiatedInputPower(milliwatts: Double, in properties: [String: Any]) -> Bool {
        isDistinct(milliwatts, from: negotiatedInputMilliwatts(in: properties), minimumTolerance: 1, relativeTolerance: 0.02)
    }

    private func isDistinctFromCounterBackedNegotiatedInputPower(milliwatts: Double, in properties: [String: Any]) -> Bool {
        isDistinct(milliwatts, from: negotiatedInputMilliwatts(in: properties), minimumTolerance: 10, relativeTolerance: 0.001)
    }

    private func isDistinctFromAdapterCapability(milliwatts: Double, adapterMaxWatts: Int?) -> Bool {
        let adapterMilliwatts = BatteryCalculations.plausibleAdapterWatts(adapterMaxWatts)
            .map { Double($0) * 1_000 }
        return isDistinct(milliwatts, from: adapterMilliwatts, minimumTolerance: 1, relativeTolerance: 0.02)
    }

    private func isDistinct(
        _ milliwatts: Double,
        from referenceMilliwatts: Double?,
        minimumTolerance: Double,
        relativeTolerance: Double
    ) -> Bool {
        guard let referenceMilliwatts else {
            return true
        }

        let toleranceMilliwatts = max(minimumTolerance, referenceMilliwatts * relativeTolerance)
        return abs(milliwatts - referenceMilliwatts) > toleranceMilliwatts
    }

    private func negotiatedInputMilliwatts(in properties: [String: Any]) -> Double? {
        if let milliwatts = positiveInteger(for: [.nested("PowerDistribution", "IPDInputPower")], in: properties) {
            return Double(milliwatts)
        }

        return milliwattsFrom(
            voltageCandidate: .nested("PowerDistribution", "IPDInputVoltage"),
            currentCandidate: .nested("PowerDistribution", "IPDInputCurrent"),
            in: properties
        )
    }

    private func milliwattsFrom(voltageCandidate: PropertyCandidate, currentCandidate: PropertyCandidate, in properties: [String: Any]) -> Double? {
        guard let voltageMillivolts = plausibleInteger(for: [voltageCandidate], in: properties, transform: {
            BatteryCalculations.plausibleVoltageMillivolts($0)
        }),
              let currentMilliamps = plausibleInteger(for: [currentCandidate], in: properties, transform: {
                  Self.plausibleInputCurrentMagnitudeMilliamps($0)
              }),
              currentMilliamps > 0 else {
            return nil
        }

        let milliwatts = (Double(voltageMillivolts) * Double(currentMilliamps)) / 1_000
        guard milliwatts.isFinite,
              BatteryCalculations.plausibleWatts(milliwatts / 1_000) != nil else {
            return nil
        }

        return milliwatts
    }

    private static func plausibleInputCurrentMagnitudeMilliamps(_ value: Int) -> Int? {
        guard value != Int.min else {
            return nil
        }

        return BatteryCalculations.plausibleCurrentMagnitudeMilliamps(abs(value))
    }

    private func positiveInteger(for candidates: [PropertyCandidate], in properties: [String: Any]) -> Int? {
        plausibleInteger(for: candidates, in: properties) { $0 > 0 ? $0 : nil }
    }

    private func positiveMilliwatts(for candidates: [PropertyCandidate], in properties: [String: Any]) -> Double? {
        guard let milliwatts = positiveInteger(for: candidates, in: properties),
              BatteryCalculations.plausibleWatts(Double(milliwatts) / 1_000) != nil else {
            return nil
        }

        return Double(milliwatts)
    }

    private func boolean(for candidates: [PropertyCandidate], in properties: [String: Any]) -> Bool? {
        firstValue(for: candidates, in: properties, transform: BooleanFlagNormalizer.normalize)
    }

    private func physicalCapacityInteger(
        for candidates: [PropertyCandidate],
        legacyFallbacks: [PropertyCandidate] = [],
        allowsZero: Bool = false,
        in properties: [String: Any]
    ) -> Int? {
        let minimumValue = allowsZero ? 0 : 1
        let primaryCapacity = firstCapacityInteger(
            for: candidates,
            in: properties,
            minimumValue: minimumValue,
            allowsZero: allowsZero
        )
        if let primaryCapacity,
           primaryCapacity != 0 {
            return primaryCapacity
        }

        let legacyCapacity = firstCapacityInteger(for: legacyFallbacks, in: properties, minimumValue: 101, allowsZero: false)
        if let legacyCapacity {
            return legacyCapacity
        }

        return primaryCapacity
    }

    private func firstCapacityInteger(
        for candidates: [PropertyCandidate],
        in properties: [String: Any],
        minimumValue: Int,
        allowsZero: Bool
    ) -> Int? {
        let positiveMinimum = max(1, minimumValue)
        let positiveCapacity: Int? = firstValue(for: candidates, in: properties, transform: { rawValue in
            guard let parsed = SignedIntegerNormalizer.normalize(rawValue),
                  parsed >= positiveMinimum else {
                return nil
            }

            return BatteryCalculations.plausibleCapacityMilliampHours(parsed, allowsZero: false)
        })
        if let positiveCapacity {
            return positiveCapacity
        }

        guard allowsZero, minimumValue == 0 else {
            return nil
        }

        return firstValue(for: candidates, in: properties) { rawValue in
            SignedIntegerNormalizer.normalize(rawValue) == 0 ? 0 : nil
        }
    }

    private func firstValue<Result>(
        for candidates: [PropertyCandidate],
        in properties: [String: Any],
        transform: (Any) -> Result?
    ) -> Result? {
        for candidate in candidates {
            switch candidate {
            case let .root(key):
                if let rawValue = properties[key],
                   let value = transform(rawValue) {
                    return value
                }
            case let .nestedRootOnly(parentKey, childKey):
                if let rawValue = Self.stringDictionary(from: properties[parentKey])?[childKey],
                   let value = transform(rawValue) {
                    return value
                }
            case let .nested(parentKey, childKey):
                if let rawValue = Self.stringDictionary(from: properties[parentKey])?[childKey],
                   let value = transform(rawValue) {
                    return value
                }

                if parentKey == "BatteryData",
                   let packProperties = Self.stringDictionary(from: properties["AppleSmartBatteryPack"]),
                   let rawValue = Self.stringDictionary(from: packProperties["BatteryData"])?[childKey],
                   let value = transform(rawValue) {
                    return value
                }
            }
        }

        return nil
    }

    private func childPackProperties(from service: io_registry_entry_t) -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        while true {
            let child = IOIteratorNext(iterator)
            guard child != 0 else {
                return nil
            }

            let properties = properties(for: child)
            IOObjectRelease(child)

            guard let properties,
                  Self.stringDictionary(from: properties["BatteryData"]) != nil else {
                continue
            }

            return properties
        }
    }

    private func properties(for entry: io_registry_entry_t) -> [String: Any]? {
        var propertiesReference: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(entry, &propertiesReference, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let properties = propertiesReference?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return properties
    }

    private func properties(forFirstServiceMatching className: String) -> [String: Any]? {
        guard let matching = IOServiceMatching(className) else {
            return nil
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return nil
        }

        defer {
            IOObjectRelease(service)
        }

        return properties(for: service)
    }

    private static func stringDictionary(from value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }

        guard let dictionary = value as? NSDictionary else {
            return nil
        }

        var swiftDictionary: [String: Any] = [:]
        dictionary.forEach { key, value in
            if let key = key as? String {
                swiftDictionary[key] = value
            }
        }

        return swiftDictionary
    }

    private func arrayDictionaries(from value: Any?) -> [[String: Any]] {
        if let array = value as? [Any] {
            return array.compactMap { Self.stringDictionary(from: $0) }
        }

        guard let array = value as? NSArray else {
            return []
        }

        return array.compactMap { Self.stringDictionary(from: $0) }
    }
}

private extension Dictionary where Key == String, Value == Any {
    var nilIfEmpty: [String: Any]? {
        isEmpty ? nil : self
    }
}
