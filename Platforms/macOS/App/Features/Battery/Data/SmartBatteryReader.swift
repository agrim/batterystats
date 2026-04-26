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
    let rawTemperature: Int?
    let temperatureCelsius: Double?
    let manufactureDate: Date?
    let adapterMaxWatts: Int?
    let rawProperties: [String: Any]
}

final class SmartBatteryReader {
    private enum PropertyCandidate {
        case root(String)
        case nested(String, String)
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

        return parse(properties: rawProperties)
    }

    func parse(properties rawProperties: [String: Any]) -> SmartBatteryDetails {
        let currentChargeMilliampHours = integer(for: [.root("AppleRawCurrentCapacity"), .root("CurrentCapacity")], in: rawProperties)
        let fullChargeCapacityMilliampHours = integer(for: [.root("AppleRawMaxCapacity"), .root("NominalChargeCapacity"), .root("MaxCapacity")], in: rawProperties)
        let designCapacityMilliampHours = integer(for: [.root("DesignCapacity")], in: rawProperties)
        let cycleCount = integer(for: [.root("CycleCount"), .nested("LegacyBatteryInfo", "Cycle Count")], in: rawProperties)
        let voltageMillivolts = integer(for: [.root("Voltage"), .nested("BatteryData", "Voltage"), .nested("LegacyBatteryInfo", "Voltage")], in: rawProperties)
        let signedCurrentMilliamps = integer(for: [.root("InstantAmperage"), .nested("LegacyBatteryInfo", "Amperage"), .root("Amperage")], in: rawProperties)
        let rawTemperature = integer(for: [.root("Temperature")], in: rawProperties)
        let manufactureDate = ManufactureDateDecoder.decode(rawValue: integer(for: [.root("ManufactureDate")], in: rawProperties))
        let adapterMaxWatts = integer(for: [.nested("AdapterDetails", "Watts"), .firstArrayDictionary("AppleRawAdapterDetails", "Watts")], in: rawProperties)

        return SmartBatteryDetails(
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            designCapacityMilliampHours: designCapacityMilliampHours,
            cycleCount: cycleCount,
            voltageMillivolts: voltageMillivolts,
            signedCurrentMilliamps: signedCurrentMilliamps,
            rawTemperature: rawTemperature,
            temperatureCelsius: BatteryCalculations.temperatureCelsius(fromRaw: rawTemperature),
            manufactureDate: manufactureDate,
            adapterMaxWatts: adapterMaxWatts,
            rawProperties: rawProperties
        )
    }

    private func integer(for candidates: [PropertyCandidate], in properties: [String: Any]) -> Int? {
        for candidate in candidates {
            guard let rawValue = value(for: candidate, in: properties) else {
                continue
            }

            if let parsed = SignedIntegerNormalizer.normalize(rawValue) {
                return parsed
            }
        }

        return nil
    }

    private func value(for candidate: PropertyCandidate, in properties: [String: Any]) -> Any? {
        switch candidate {
        case let .root(key):
            return properties[key]
        case let .nested(parentKey, childKey):
            if let dictionary = properties[parentKey] as? [String: Any] {
                return dictionary[childKey]
            }

            if let dictionary = properties[parentKey] as? NSDictionary {
                return dictionary[childKey]
            }

            return nil
        case let .firstArrayDictionary(parentKey, childKey):
            if let dictionaries = properties[parentKey] as? [[String: Any]] {
                return dictionaries.first?[childKey]
            }

            if let dictionaries = properties[parentKey] as? [NSDictionary] {
                return dictionaries.first?[childKey]
            }

            return nil
        }
    }
}
