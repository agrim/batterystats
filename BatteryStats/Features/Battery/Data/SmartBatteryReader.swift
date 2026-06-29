import Foundation
import IOKit
import OSLog

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
        case firstArrayDictionary(String, String)
    }

    func read() -> SmartBatteryDetails? {
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            Logger.batteryReader.debug("AppleSmartBattery matching dictionary unavailable")
            return nil
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            Logger.batteryReader.debug("AppleSmartBattery service not found")
            return nil
        }

        defer {
            IOObjectRelease(service)
        }

        var propertiesReference: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propertiesReference, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let rawProperties = propertiesReference?.takeRetainedValue() as? [String: Any] else {
            Logger.batteryReader.debug("Unable to read AppleSmartBattery properties, kern result \(result)")
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

            for (key, value) in packBatteryData where mergedBatteryData[key] == nil && Self.canMergePackBatteryDataKey(key) {
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
        for candidate in candidates {
            for rawValue in values(for: candidate, in: properties) {
                guard let parsed = SignedIntegerNormalizer.normalize(rawValue),
                      let value = transform(parsed) else {
                    continue
                }

                return value
            }
        }

        return nil
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
        plausibleInteger(for: candidates, in: properties) {
            ManufactureDateDecoder.decode(rawValue: $0) == nil ? nil : $0
        }.flatMap {
            ManufactureDateDecoder.decode(rawValue: $0)
        }
    }

    private struct InputPowerReading {
        let watts: Double
        let evidence: BatteryInputPowerEvidence?
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
            reportedWatts: normalizedAdapterWatts(adapterDetails["Watts"]),
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

        return adapterWatts(fromMilliwatts: milliwatts)
    }

    private func corroboratedIPDInputPowerMilliwatts(in properties: [String: Any]) -> Double? {
        guard hasLiveSystemPowerInCounter(in: properties),
              let ipdInputPower = plausibleInteger(
                  for: [.nested("PowerDistribution", "IPDInputPower")],
                  in: properties,
                  transform: { $0 > 0 ? $0 : nil }
              ),
              let systemPowerIn = plausibleInteger(
                  for: [.nested("PowerTelemetryData", "SystemPowerIn")],
                  in: properties,
                  transform: { $0 > 0 ? $0 : nil }
              ) else {
            return nil
        }

        let negotiatedMilliwatts = Double(ipdInputPower)
        let systemMilliwatts = Double(systemPowerIn)
        let toleranceMilliwatts = max(1_000.0, negotiatedMilliwatts * 0.05)
        guard abs(negotiatedMilliwatts - systemMilliwatts) <= toleranceMilliwatts else {
            return nil
        }

        return negotiatedMilliwatts
    }

    private func adapterWatts(fromMilliwatts milliwatts: Double) -> Int? {
        let watts = milliwatts / 1_000
        guard watts.isFinite,
              watts >= 0,
              watts <= Double(Int.max) else {
            return nil
        }

        return BatteryCalculations.plausibleAdapterWatts(Int(watts.rounded(.toNearestOrAwayFromZero)))
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

        let comparisonWatts = max(reportedWatts.watts, negotiatedWatts)
        let staleReportTolerance = max(2, Int((Double(comparisonWatts) * 0.05).rounded(.up)))
        if abs(negotiatedWatts - reportedWatts.watts) > staleReportTolerance {
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
        switch (rawWatts, adapterDetailsWatts) {
        case let (.some(rawWatts), .some(adapterDetailsWatts)):
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
        case let (.some(rawWatts), .none):
            return rawWatts
        case let (.none, .some(adapterDetailsWatts)):
            return adapterDetailsWatts
        case (.none, .none):
            return nil
        }
    }

    private func reconciledAdapterWatts(reportedWatts: Int?, derivedWatts: Int?) -> AdapterWattsReading? {
        guard let reportedWatts else {
            return derivedWatts.map { AdapterWattsReading(watts: $0, hasDerivedEvidence: true) }
        }

        guard let derivedWatts else {
            return AdapterWattsReading(watts: reportedWatts, hasDerivedEvidence: false)
        }

        let comparisonWatts = max(reportedWatts, derivedWatts)
        let staleReportTolerance = max(2, Int((Double(comparisonWatts) * 0.05).rounded(.up)))
        if abs(reportedWatts - derivedWatts) > staleReportTolerance {
            return AdapterWattsReading(watts: derivedWatts, hasDerivedEvidence: true)
        }

        return AdapterWattsReading(watts: reportedWatts, hasDerivedEvidence: true)
    }

    private func normalizedAdapterWatts(_ value: Any?) -> Int? {
        guard let watts = SignedIntegerNormalizer.normalize(value) else {
            return nil
        }

        return BatteryCalculations.plausibleAdapterWatts(watts)
    }

    private func derivedAdapterWatts(from adapterDetails: [String: Any]) -> Int? {
        guard let voltageMillivolts = firstPlausibleVoltageMillivolts(
            for: ["Voltage", "AdapterVoltage"],
            in: adapterDetails
        ),
              let currentMilliamps = firstPlausibleInputCurrentMilliamps(
                  for: ["Current", "AdapterCurrent"],
                  in: adapterDetails
              ) else {
            return nil
        }

        let watts = (Double(voltageMillivolts) * Double(currentMilliamps)) / 1_000_000
        guard watts.isFinite,
              watts >= 0,
              watts <= Double(Int.max) else {
            return nil
        }

        return BatteryCalculations.plausibleAdapterWatts(Int(watts.rounded(.toNearestOrAwayFromZero)))
    }

    private func firstPlausibleVoltageMillivolts(for keys: [String], in dictionary: [String: Any]) -> Int? {
        for key in keys {
            guard let parsed = SignedIntegerNormalizer.normalize(dictionary[key]),
                  let voltage = BatteryCalculations.plausibleVoltageMillivolts(parsed) else {
                continue
            }

            return voltage
        }

        return nil
    }

    private func firstPlausibleInputCurrentMilliamps(for keys: [String], in dictionary: [String: Any]) -> Int? {
        for key in keys {
            guard let parsed = SignedIntegerNormalizer.normalize(dictionary[key]),
                  let current = Self.plausibleInputCurrentMagnitudeMilliamps(parsed),
                  current > 0 else {
                continue
            }

            return current
        }

        return nil
    }

    private func inputPower(in properties: [String: Any], adapterMaxWatts: Int?) -> InputPowerReading? {
        if let watts = wattsFromCorroboratedSystemPowerIn(in: properties, adapterMaxWatts: adapterMaxWatts) {
            return InputPowerReading(watts: watts, evidence: .counterBacked)
        }

        if let watts = inputWattsWithinAdapterCapability(
            liveSystemTelemetryWatts(in: properties, adapterMaxWatts: adapterMaxWatts),
            adapterMaxWatts: adapterMaxWatts
        ) {
            return InputPowerReading(watts: watts, evidence: nil)
        }

        return nil
    }

    private func inputWattsWithinAdapterCapability(_ watts: Double?, adapterMaxWatts: Int?) -> Double? {
        BatteryCalculations.displayableInputPowerWatts(watts, adapterMaxWatts: adapterMaxWatts)
    }

    private func wattsFromCorroboratedSystemPowerIn(in properties: [String: Any], adapterMaxWatts: Int?) -> Double? {
        guard hasLiveSystemPowerInCounter(in: properties) else {
            return nil
        }

        guard let milliwatts = plausibleInteger(
            for: [.nested("PowerTelemetryData", "SystemPowerIn")],
            in: properties,
            transform: { value in
                guard value > 0,
                      BatteryCalculations.plausibleWatts(Double(value) / 1_000) != nil else {
                    return nil
                }

                return value
            }
        ) else {
            return nil
        }

        let watts = Double(milliwatts) / 1_000
        guard isDistinctFromCounterBackedNegotiatedInputPower(milliwatts: Double(milliwatts), in: properties),
              isTrustedCounterBackedSystemPowerIn(milliwatts: Double(milliwatts), in: properties, adapterMaxWatts: adapterMaxWatts),
              let displayableWatts = displayableCorroboratedSystemPowerInWatts(
                  watts,
                  milliwatts: Double(milliwatts),
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
            return displayableLiveCorroboratedCounterBackedInputPowerWatts(watts, adapterMaxWatts: adapterMaxWatts)
        }

        return BatteryCalculations.displayableCounterBackedInputPowerWatts(watts, adapterMaxWatts: adapterMaxWatts)
    }

    private func displayableLiveCorroboratedCounterBackedInputPowerWatts(_ watts: Double, adapterMaxWatts: Int?) -> Double? {
        guard let watts = BatteryCalculations.plausibleInputPowerWatts(watts, adapterMaxWatts: adapterMaxWatts) else {
            return nil
        }

        guard BatteryCalculations.plausibleAdapterWatts(adapterMaxWatts) != nil || watts < 90 else {
            return nil
        }

        guard isDistinctFromExactAdapterCapabilityEcho(watts, adapterMaxWatts: adapterMaxWatts) else {
            return nil
        }

        return watts
    }

    private func isDistinctFromExactAdapterCapabilityEcho(_ watts: Double, adapterMaxWatts: Int?) -> Bool {
        guard let adapterMaxWatts = BatteryCalculations.plausibleAdapterWatts(adapterMaxWatts) else {
            return true
        }

        return abs(watts - Double(adapterMaxWatts)) > 0.1
    }

    private func counterBackedInputPowerCorroboratesNegotiatedPower(_ negotiatedWatts: Int, in properties: [String: Any]) -> Bool {
        guard hasLiveSystemPowerInCounter(in: properties),
              let systemPowerIn = plausibleInteger(
                  for: [.nested("PowerTelemetryData", "SystemPowerIn")],
                  in: properties,
                  transform: { value in
                      guard value > 0,
                            BatteryCalculations.plausibleWatts(Double(value) / 1_000) != nil else {
                          return nil
                      }

                      return value
                  }
              ) else {
            return false
        }

        let negotiatedMilliwatts = Double(negotiatedWatts) * 1_000
        let systemMilliwatts = Double(systemPowerIn)
        let toleranceMilliwatts = max(1_000.0, negotiatedMilliwatts * 0.05)
        guard abs(systemMilliwatts - negotiatedMilliwatts) <= toleranceMilliwatts else {
            return false
        }

        return liveSystemTelemetryCorroborates(milliwatts: systemMilliwatts, in: properties)
    }

    private func liveSystemTelemetryCorroborates(milliwatts: Double, in properties: [String: Any]) -> Bool {
        guard let corroboratingMilliwatts = liveSystemTelemetryMilliwatts(in: properties) else {
            return false
        }

        let toleranceMilliwatts = max(1_000.0, milliwatts * 0.05)
        return abs(milliwatts - corroboratingMilliwatts) <= toleranceMilliwatts
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
        plausibleInteger(
            for: [.nested("PowerTelemetryData", "SystemPowerInAccumulatorCount")],
            in: properties,
            transform: { $0 > 0 ? $0 : nil }
        ) != nil
    }

    private func isDistinctFromNegotiatedInputPower(milliwatts: Int, in properties: [String: Any]) -> Bool {
        isDistinctFromNegotiatedInputPower(milliwatts: Double(milliwatts), in: properties)
    }

    private func isDistinctFromNegotiatedInputPower(milliwatts: Double, in properties: [String: Any]) -> Bool {
        guard let negotiatedMilliwatts = negotiatedInputMilliwatts(in: properties) else {
            return true
        }

        let toleranceMilliwatts = max(1, negotiatedMilliwatts * 0.02)
        return abs(milliwatts - negotiatedMilliwatts) > toleranceMilliwatts
    }

    private func isDistinctFromCounterBackedNegotiatedInputPower(milliwatts: Double, in properties: [String: Any]) -> Bool {
        guard let negotiatedMilliwatts = negotiatedInputMilliwatts(in: properties) else {
            return true
        }

        let toleranceMilliwatts = max(10, negotiatedMilliwatts * 0.001)
        return abs(milliwatts - negotiatedMilliwatts) > toleranceMilliwatts
    }

    private func isDistinctFromAdapterCapability(milliwatts: Double, adapterMaxWatts: Int?) -> Bool {
        guard let adapterMaxWatts = BatteryCalculations.plausibleAdapterWatts(adapterMaxWatts) else {
            return true
        }

        let adapterMilliwatts = Double(adapterMaxWatts) * 1_000
        let toleranceMilliwatts = max(1, adapterMilliwatts * 0.02)
        return abs(milliwatts - adapterMilliwatts) > toleranceMilliwatts
    }

    private func negotiatedInputMilliwatts(in properties: [String: Any]) -> Double? {
        if let milliwatts = plausibleInteger(
            for: [.nested("PowerDistribution", "IPDInputPower")],
            in: properties,
            transform: { $0 > 0 ? $0 : nil }
        ) {
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

    private func boolean(for candidates: [PropertyCandidate], in properties: [String: Any]) -> Bool? {
        for candidate in candidates {
            for rawValue in values(for: candidate, in: properties) {
                if let value = Self.booleanValue(from: rawValue) {
                    return value
                }
            }
        }

        return nil
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
        var zeroFallback: Int?
        for candidate in candidates {
            for rawValue in values(for: candidate, in: properties) {
                guard let parsed = SignedIntegerNormalizer.normalize(rawValue),
                      parsed >= minimumValue,
                      let capacity = BatteryCalculations.plausibleCapacityMilliampHours(parsed, allowsZero: allowsZero) else {
                    continue
                }

                if allowsZero, capacity == 0 {
                    zeroFallback = zeroFallback ?? capacity
                    continue
                }

                return capacity
            }
        }

        return zeroFallback
    }

    private func values(for candidate: PropertyCandidate, in properties: [String: Any]) -> [Any] {
        switch candidate {
        case let .root(key):
            return properties[key].map { [$0] } ?? []
        case let .nestedRootOnly(parentKey, childKey):
            guard let dictionary = Self.stringDictionary(from: properties[parentKey]) else {
                return []
            }

            return dictionary[childKey].map { [$0] } ?? []
        case let .nested(parentKey, childKey):
            var values: [Any] = []
            if let dictionary = Self.stringDictionary(from: properties[parentKey]) {
                values.append(contentsOf: dictionary[childKey].map { [$0] } ?? [])
            }

            if parentKey == "BatteryData",
               let packProperties = Self.stringDictionary(from: properties["AppleSmartBatteryPack"]),
               let packBatteryData = Self.stringDictionary(from: packProperties["BatteryData"]) {
                values.append(contentsOf: packBatteryData[childKey].map { [$0] } ?? [])
            }

            return values
        case let .firstArrayDictionary(parentKey, childKey):
            return arrayDictionaries(from: properties[parentKey]).compactMap { $0[childKey] }
        }
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

    private static func canMergePackBatteryDataKey(_ key: String) -> Bool {
        key != "ManufactureDate"
    }

    private static func booleanValue(from value: Any?) -> Bool? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }

            if number.doubleValue == 0 || number.doubleValue == 1 {
                return number.doubleValue == 1
            }

            return nil
        }

        return value as? Bool
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
