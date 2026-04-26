import Foundation

struct BatteryReadResult {
    let snapshot: BatterySnapshot?
    let rawSnapshotText: String
    let parsedSnapshotText: String
}

struct BatteryReadingService {
    let powerSourceReader: PowerSourceReader
    let smartBatteryReader: SmartBatteryReader

    init(powerSourceReader: PowerSourceReader = PowerSourceReader(), smartBatteryReader: SmartBatteryReader = SmartBatteryReader()) {
        self.powerSourceReader = powerSourceReader
        self.smartBatteryReader = smartBatteryReader
    }

    func makeNotificationToken(handler: @escaping () -> Void) -> PowerSourceReader.NotificationToken? {
        powerSourceReader.makeNotificationToken(handler: handler)
    }

    func read(at now: Date = .now) -> BatteryReadResult {
        let publicSnapshot = powerSourceReader.read()
        let smartBattery = smartBatteryReader.read()

        guard let publicSnapshot = publicSnapshot ?? fallbackPublicSnapshot(from: smartBattery) else {
            return BatteryReadResult(snapshot: nil, rawSnapshotText: "No internal battery detected.", parsedSnapshotText: "Unsupported")
        }

        guard publicSnapshot.isPresent, publicSnapshot.isInternalBattery else {
            return BatteryReadResult(snapshot: nil, rawSnapshotText: prettyRawSnapshot(publicSnapshot: publicSnapshot, smartBattery: smartBattery), parsedSnapshotText: "Unsupported")
        }

        var notes: [String] = []
        if smartBattery == nil {
            notes.append("Detailed AppleSmartBattery properties were unavailable, so the app is showing public power-source data only.")
        }

        let currentChargeMilliampHours = smartBattery?.currentChargeMilliampHours
            ?? BatteryCalculations.deriveCurrentChargeMilliampHours(
                publicPercentage: publicSnapshot.stateOfChargePercent,
                fullChargeCapacityMilliampHours: smartBattery?.fullChargeCapacityMilliampHours
            )

        let fullChargeCapacityMilliampHours = smartBattery?.fullChargeCapacityMilliampHours
        let designCapacityMilliampHours = smartBattery?.designCapacityMilliampHours
        let voltageMillivolts = smartBattery?.voltageMillivolts
        let signedCurrentMilliamps = smartBattery?.signedCurrentMilliamps
        let reportedTimeToFullMinutes = sanitized(publicSnapshot.timeToFullMinutes)

        let powerState = BatteryCalculations.derivePowerState(
            isCharging: publicSnapshot.isCharging,
            isExternalPowerConnected: publicSnapshot.isExternalPowerConnected,
            signedCurrentMilliamps: signedCurrentMilliamps,
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        )

        if smartBattery?.temperatureCelsius == nil,
           smartBattery?.rawTemperature != nil {
            notes.append("Battery temperature was present but could not be converted confidently.")
        }

        let snapshot = BatterySnapshot(
            timestamp: now,
            powerState: powerState,
            isCharging: publicSnapshot.isCharging,
            isExternalPowerConnected: publicSnapshot.isExternalPowerConnected,
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
                publicPercentage: publicSnapshot.stateOfChargePercent
            ),
            voltageMillivolts: voltageMillivolts,
            currentMilliampsSigned: signedCurrentMilliamps,
            dischargeRateMilliamps: BatteryCalculations.dischargeRateMilliamps(from: signedCurrentMilliamps),
            chargeRateWatts: BatteryCalculations.chargeRateWatts(voltageMillivolts: voltageMillivolts, signedCurrentMilliamps: signedCurrentMilliamps),
            dischargeRateWatts: BatteryCalculations.dischargeRateWatts(voltageMillivolts: voltageMillivolts, signedCurrentMilliamps: signedCurrentMilliamps),
            rateBasedTimeRemainingMinutes: BatteryCalculations.timeRemainingMinutes(
                currentChargeMilliampHours: currentChargeMilliampHours,
                dischargeRateMilliamps: BatteryCalculations.dischargeRateMilliamps(from: signedCurrentMilliamps)
            ),
            systemTimeRemainingMinutes: sanitized(publicSnapshot.systemTimeRemainingMinutes),
            timeToFullMinutes: BatteryCalculations.estimatedTimeToFullMinutes(
                currentChargeMilliampHours: currentChargeMilliampHours,
                fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
                chargeCurrentMilliamps: BatteryCalculations.chargeRateMilliamps(from: signedCurrentMilliamps),
                reportedTimeToFullMinutes: reportedTimeToFullMinutes
            ),
            cycleCount: smartBattery?.cycleCount,
            manufactureDate: smartBattery?.manufactureDate,
            batteryAgeComponents: BatteryCalculations.batteryAgeComponents(from: smartBattery?.manufactureDate, now: now),
            temperatureCelsius: smartBattery?.temperatureCelsius,
            adapterMaxWatts: smartBattery?.adapterMaxWatts,
            notes: notes
        )

        return BatteryReadResult(
            snapshot: snapshot,
            rawSnapshotText: prettyRawSnapshot(publicSnapshot: publicSnapshot, smartBattery: smartBattery),
            parsedSnapshotText: snapshot.debugSummary
        )
    }

    private func fallbackPublicSnapshot(from smartBattery: SmartBatteryDetails?) -> PublicPowerSourceSnapshot? {
        guard smartBattery != nil else {
            return nil
        }

        return PublicPowerSourceSnapshot(
            isPresent: true,
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            isInternalBattery: true,
            stateOfChargePercent: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            powerSourceState: nil,
            rawDescription: [:]
        )
    }

    private func sanitized(_ minutes: Int?) -> Int? {
        guard let minutes, minutes >= 0 else {
            return nil
        }

        return minutes
    }

    private func prettyRawSnapshot(publicSnapshot: PublicPowerSourceSnapshot?, smartBattery: SmartBatteryDetails?) -> String {
        var sections: [String] = []

        sections.append("Public power source")
        sections.append(render(value: publicSnapshot?.rawDescription ?? [:]))
        sections.append("")
        sections.append("AppleSmartBattery")
        sections.append(render(value: smartBattery?.rawProperties ?? [:]))

        return sections.joined(separator: "\n")
    }

    private func render(value: Any, indentLevel: Int = 0) -> String {
        let indent = String(repeating: "  ", count: indentLevel)

        switch value {
        case let dictionary as [String: Any]:
            if dictionary.isEmpty {
                return "\(indent){}"
            }

            return dictionary.keys.sorted().map { key in
                let renderedValue = render(value: dictionary[key] ?? "nil", indentLevel: indentLevel + 1)
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
            return render(value: swiftDictionary, indentLevel: indentLevel)
        case let array as [Any]:
            if array.isEmpty {
                return "\(indent)[]"
            }

            return array.map { item in
                let rendered = render(value: item, indentLevel: indentLevel + 1)
                return "\(indent)- \(rendered.trimmingCharacters(in: .whitespacesAndNewlines))"
            }.joined(separator: "\n")
        case let number as NSNumber:
            return "\(indent)\(number)"
        case let string as String:
            return "\(indent)\(string)"
        case let boolean as Bool:
            return "\(indent)\(boolean)"
        default:
            return "\(indent)\(String(describing: value))"
        }
    }
}
