import Foundation

struct BatteryWidgetSnapshotStore {
    static let appGroupIdentifier = "group.io.github.agrim.batterystats"
    static let timelineKind = "BatteryStatusWidget"
    static let defaultMaximumAge: TimeInterval = 600
    static let defaultRetentionAge: TimeInterval = 6 * 60 * 60

    private static let snapshotKey = "latestBatteryWidgetSnapshot"

    let defaults: UserDefaults?

    static var shared: BatteryWidgetSnapshotStore {
        BatteryWidgetSnapshotStore(defaults: UserDefaults(suiteName: appGroupIdentifier))
    }

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    func save(_ snapshot: BatterySnapshot) {
        let sanitizedSnapshot = Self.sanitized(snapshot)
        saveSanitized(
            sanitizedSnapshot,
            preservingInvalidPowerRateMarkersFrom: snapshot,
            encodedPowerRateFields: nil
        )
    }

    private func saveSanitized(
        _ sanitizedSnapshot: BatterySnapshot,
        preservingInvalidPowerRateMarkersFrom sourceSnapshot: BatterySnapshot,
        encodedPowerRateFields: (chargeRateWatts: Bool, dischargeRateWatts: Bool)?
    ) {
        guard let defaults else {
            return
        }

        guard let data = try? Self.encodedSnapshotData(
            sanitizedSnapshot,
            preservingInvalidPowerRateMarkersFrom: sourceSnapshot,
            encodedPowerRateFields: encodedPowerRateFields
        ) else {
            clear()
            return
        }

        defaults.set(data, forKey: Self.snapshotKey)
        defaults.synchronize()
    }

    func snapshot(now: Date = .now, maximumAge: TimeInterval = defaultRetentionAge) -> BatterySnapshot? {
        guard maximumAge > 0,
              let defaults,
              let data = defaults.data(forKey: Self.snapshotKey) else {
            return nil
        }

        guard let snapshot = try? JSONDecoder().decode(BatterySnapshot.self, from: data) else {
            clear()
            return nil
        }

        let encodedPowerRateFields = Self.encodedPowerRateFields(in: data)
        let age = now.timeIntervalSince(snapshot.timestamp)
        guard BatterySnapshotFreshnessPolicy.isWithinFutureSkew(updatedAt: snapshot.timestamp, now: now),
              age <= Self.defaultRetentionAge else {
            clear()
            return nil
        }

        let sanitizedSnapshot = Self.sanitized(
            snapshot,
            now: now,
            encodedPowerRateFields: encodedPowerRateFields
        )
        if sanitizedSnapshot != snapshot {
            saveSanitized(
                sanitizedSnapshot,
                preservingInvalidPowerRateMarkersFrom: snapshot,
                encodedPowerRateFields: encodedPowerRateFields
            )
        }

        guard age <= maximumAge else {
            return nil
        }

        return sanitizedSnapshot
    }

    func clear() {
        guard let defaults,
              defaults.object(forKey: Self.snapshotKey) != nil else {
            return
        }

        defaults.removeObject(forKey: Self.snapshotKey)
        defaults.synchronize()
    }

    private static func sanitized(
        _ snapshot: BatterySnapshot,
        now: Date? = nil,
        encodedPowerRateFields: (chargeRateWatts: Bool, dischargeRateWatts: Bool)? = nil
    ) -> BatterySnapshot {
        let timestamp = now.map { min(snapshot.timestamp, $0) } ?? snapshot.timestamp
        let ageReferenceDate = now ?? timestamp
        let manufactureDate = BatteryCalculations.plausibleManufactureDate(snapshot.manufactureDate, now: ageReferenceDate)
        let batteryAgeComponents = BatteryCalculations.batteryAgeComponents(from: manufactureDate, now: ageReferenceDate)
        let fullChargeCapacityMilliampHours = BatteryCalculations.plausibleCapacityMilliampHours(snapshot.fullChargeCapacityMilliampHours, allowsZero: false)
        let designCapacityMilliampHours = BatteryCalculations.plausibleCapacityMilliampHours(snapshot.designCapacityMilliampHours, allowsZero: false)
        let storedHealthPercent = BatteryCalculations.presentationPercent(snapshot.healthPercent, maximumAllowed: 120)
        let derivedHealthPercent = BatteryCalculations.healthPercent(
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            designCapacityMilliampHours: designCapacityMilliampHours
        )
        let healthPercent = derivedHealthPercent ?? storedHealthPercent
        let storedStateOfChargePercent = BatteryCalculations.presentationPercent(snapshot.stateOfChargePercent, maximumAllowed: 105)
        let currentMilliampsSigned = signedCurrentMilliampsForStoredPowerState(
            snapshot.currentMilliampsSigned,
            powerState: snapshot.powerState
        )
        let chargeRateMilliamps = BatteryCalculations.chargeRateMilliamps(from: currentMilliampsSigned)
        let dischargeCurrentMilliamps = BatteryCalculations.dischargeRateMilliamps(from: currentMilliampsSigned)
        let isStoredCharged = reconciledStoredChargedState(
            snapshot: snapshot,
            hasDischargeCurrentEvidence: dischargeCurrentMilliamps != nil,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            storedStateOfChargePercent: storedStateOfChargePercent
        )
        let trustedStateOfChargePercent = isStoredCharged ? 100.0 : storedStateOfChargePercent
        let voltageMillivolts = BatteryCalculations.plausibleVoltageMillivolts(snapshot.voltageMillivolts)
        let currentChargeMilliampHours = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: snapshot.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            publicPercentage: trustedStateOfChargePercent
        )
        let stateOfChargePercent = BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            publicPercentage: trustedStateOfChargePercent
        )
        let storedExternalPowerConnected = snapshot.powerState.knownExternalPowerConnected
            ?? snapshot.isExternalPowerConnected
        let derivedPowerState = BatteryCalculations.derivePowerState(
            isCharging: snapshot.isCharging || snapshot.powerState == .charging,
            isCharged: isStoredCharged,
            isExternalPowerConnected: storedExternalPowerConnected,
            signedCurrentMilliamps: currentMilliampsSigned,
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        )
        let powerState = reconciledStoredPowerState(
            originalPowerState: snapshot.powerState,
            derivedPowerState: derivedPowerState,
            isCharging: snapshot.isCharging,
            isStoredCharged: isStoredCharged,
            isExternalPowerConnected: storedExternalPowerConnected,
            hasCurrentEvidence: chargeRateMilliamps != nil || dischargeCurrentMilliamps != nil
        )
        let flags = BatteryCalculations.normalizedPowerFlags(for: powerState)
        let storedDischargeRateMilliamps = BatteryCalculations.plausibleDischargeRateMilliamps(snapshot.dischargeRateMilliamps)
        let dischargeRateMilliamps = powerState.isBatteryDischarging
            ? storedDischargeRateMilliamps
            : nil
        let adapterMaxWatts = BatteryReadingService.displayableAdapterMaxWatts(
            snapshot.adapterMaxWatts,
            powerState: powerState
        )
        let computedChargeRateWatts = BatteryReadingService.chargeRateWattsWithinAdapterContract(
            voltageMillivolts: voltageMillivolts,
            signedCurrentMilliamps: currentMilliampsSigned,
            adapterMaxWatts: adapterMaxWatts
        )
        let computedDischargeRateWatts = BatteryCalculations.dischargeRateWatts(
            voltageMillivolts: voltageMillivolts,
            signedCurrentMilliamps: currentMilliampsSigned
        )
        let powerRates = BatteryReadingService.displayablePowerRates(
            powerState: powerState,
            chargeRateWatts: correctedStoredPowerRate(
                stored: snapshot.chargeRateWatts,
                computed: computedChargeRateWatts,
                encodedFieldWasPresent: encodedPowerRateFields?.chargeRateWatts,
                hasCurrentEvidence: chargeRateMilliamps != nil,
                validatesInputPower: true,
                adapterMaxWatts: adapterMaxWatts
            ),
            dischargeRateWatts: correctedStoredPowerRate(
                stored: snapshot.dischargeRateWatts,
                computed: computedDischargeRateWatts,
                encodedFieldWasPresent: encodedPowerRateFields?.dischargeRateWatts,
                hasCurrentEvidence: dischargeCurrentMilliamps != nil
            )
        )
        let inputPowerWatts = BatteryReadingService.displayableInputPowerWatts(
            snapshot.inputPowerWatts,
            evidence: snapshot.inputPowerEvidence,
            adapterMaxWatts: adapterMaxWatts,
            powerState: powerState
        )
        let timing = BatteryReadingService.displayableTiming(
            powerState: powerState,
            rateBasedTimeRemainingMinutes: rateBasedTimeRemainingMinutes(
                snapshot.rateBasedTimeRemainingMinutes,
                currentChargeMilliampHours: currentChargeMilliampHours,
                dischargeRateMilliamps: dischargeRateMilliamps,
                stateOfChargePercent: stateOfChargePercent
            ),
            systemTimeRemainingMinutes: timeToEmptyMinutes(
                snapshot.systemTimeRemainingMinutes,
                currentChargeMilliampHours: currentChargeMilliampHours,
                stateOfChargePercent: stateOfChargePercent
            ),
            timeToFullMinutes: timeToFullMinutes(
                snapshot.timeToFullMinutes,
                currentChargeMilliampHours: currentChargeMilliampHours,
                fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
                stateOfChargePercent: stateOfChargePercent,
                chargeRateMilliamps: chargeRateMilliamps
            )
        )

        return BatterySnapshot(
            timestamp: timestamp,
            powerState: powerState,
            isCharging: flags.isCharging,
            isExternalPowerConnected: flags.isExternalPowerConnected,
            currentChargeMilliampHours: currentChargeMilliampHours,
            currentChargeWattHours: derivedWattHours(
                milliampHours: currentChargeMilliampHours,
                voltageMillivolts: voltageMillivolts,
                allowsZero: true
            ),
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            fullChargeCapacityWattHours: derivedWattHours(
                milliampHours: fullChargeCapacityMilliampHours,
                voltageMillivolts: voltageMillivolts,
                allowsZero: false
            ),
            designCapacityMilliampHours: designCapacityMilliampHours,
            designCapacityWattHours: derivedWattHours(
                milliampHours: designCapacityMilliampHours,
                voltageMillivolts: voltageMillivolts,
                allowsZero: false
            ),
            healthPercent: healthPercent,
            stateOfChargePercent: stateOfChargePercent,
            voltageMillivolts: voltageMillivolts,
            currentMilliampsSigned: currentMilliampsSigned,
            dischargeRateMilliamps: dischargeRateMilliamps,
            chargeRateWatts: powerRates.chargeRateWatts,
            inputPowerWatts: inputPowerWatts,
            inputPowerEvidence: inputPowerWatts == nil ? nil : snapshot.inputPowerEvidence,
            dischargeRateWatts: powerRates.dischargeRateWatts,
            rateBasedTimeRemainingMinutes: timing.rateBasedTimeRemainingMinutes,
            systemTimeRemainingMinutes: timing.systemTimeRemainingMinutes,
            timeToFullMinutes: timing.timeToFullMinutes,
            cycleCount: BatteryCalculations.plausibleCycleCount(snapshot.cycleCount),
            manufactureDate: manufactureDate,
            batteryAgeComponents: batteryAgeComponents,
            temperatureCelsius: BatteryCalculations.plausibleTemperatureCelsius(snapshot.temperatureCelsius),
            adapterMaxWatts: adapterMaxWatts,
            notes: snapshot.notes
        )
    }

    private static func correctedStoredPowerRate(
        stored: Double?,
        computed: Double?,
        encodedFieldWasPresent: Bool?,
        hasCurrentEvidence: Bool,
        validatesInputPower: Bool = false,
        adapterMaxWatts: Int? = nil
    ) -> Double? {
        guard let stored else {
            return encodedFieldWasPresent == true ? nil : computed
        }

        if let computed {
            return computed
        }

        guard hasCurrentEvidence else {
            return nil
        }

        guard let storedPowerRate = BatteryCalculations.plausibleWatts(stored) else {
            return nil
        }

        guard validatesInputPower else {
            return storedPowerRate
        }

        return BatteryCalculations.displayableLiveMeasuredInputPowerWatts(
            storedPowerRate,
            adapterMaxWatts: adapterMaxWatts
        )
    }

    private static func encodedSnapshotData(
        _ snapshot: BatterySnapshot,
        preservingInvalidPowerRateMarkersFrom sourceSnapshot: BatterySnapshot,
        encodedPowerRateFields: (chargeRateWatts: Bool, dischargeRateWatts: Bool)?
    ) throws -> Data {
        let encodedData = try JSONEncoder().encode(snapshot)
        let shouldPreserveChargeMarker = snapshot.chargeRateWatts == nil
            && (sourceSnapshot.chargeRateWatts != nil || encodedPowerRateFields?.chargeRateWatts == true)
        let shouldPreserveDischargeMarker = snapshot.dischargeRateWatts == nil
            && (sourceSnapshot.dischargeRateWatts != nil || encodedPowerRateFields?.dischargeRateWatts == true)
        guard shouldPreserveChargeMarker || shouldPreserveDischargeMarker else {
            return encodedData
        }

        guard var dictionary = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any] else {
            return encodedData
        }

        if shouldPreserveChargeMarker {
            dictionary["chargeRateWatts"] = NSNull()
        }

        if shouldPreserveDischargeMarker {
            dictionary["dischargeRateWatts"] = NSNull()
        }

        return try JSONSerialization.data(withJSONObject: dictionary)
    }

    private static func encodedPowerRateFields(in data: Data) -> (chargeRateWatts: Bool, dischargeRateWatts: Bool)? {
        guard let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return (
            chargeRateWatts: dictionary.keys.contains("chargeRateWatts"),
            dischargeRateWatts: dictionary.keys.contains("dischargeRateWatts")
        )
    }

    private static func derivedWattHours(
        milliampHours: Int?,
        voltageMillivolts: Int?,
        allowsZero: Bool
    ) -> Double? {
        guard let value = BatteryCalculations.wattHours(
            milliampHours: milliampHours,
            voltageMillivolts: voltageMillivolts
        ),
              allowsZero || value > 0 else {
            return nil
        }

        return value
    }

    private static func rateBasedTimeRemainingMinutes(
        _ minutes: Int?,
        currentChargeMilliampHours: Int?,
        dischargeRateMilliamps: Int?,
        stateOfChargePercent: Double?
    ) -> Int? {
        guard let minutes = BatteryCalculations.plausibleDurationMinutes(minutes) else {
            return nil
        }

        guard minutes == 0 else {
            return minutes
        }

        if BatteryCalculations.isEffectivelyEmpty(
            currentChargeMilliampHours: currentChargeMilliampHours,
            stateOfChargePercent: stateOfChargePercent
        ) {
            return 0
        }

        return BatteryCalculations.timeRemainingMinutes(
            currentChargeMilliampHours: currentChargeMilliampHours,
            dischargeRateMilliamps: dischargeRateMilliamps
        )
    }

    private static func timeToEmptyMinutes(
        _ minutes: Int?,
        currentChargeMilliampHours: Int?,
        stateOfChargePercent: Double?
    ) -> Int? {
        guard let minutes = BatteryCalculations.plausibleDurationMinutes(minutes) else {
            return nil
        }

        guard minutes == 0 else {
            return minutes
        }

        return BatteryCalculations.isEffectivelyEmpty(
            currentChargeMilliampHours: currentChargeMilliampHours,
            stateOfChargePercent: stateOfChargePercent
        ) ? 0 : nil
    }

    private static func timeToFullMinutes(
        _ minutes: Int?,
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?,
        stateOfChargePercent: Double?,
        chargeRateMilliamps: Int?
    ) -> Int? {
        let reportedMinutes = BatteryCalculations.plausibleDurationMinutes(minutes)
        let computedMinutes = BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            chargeCurrentMilliamps: chargeRateMilliamps,
            reportedTimeToFullMinutes: nil
        )
        let isFull = BatteryCalculations.isEffectivelyFull(
            currentChargeMilliampHours: currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            stateOfChargePercent: stateOfChargePercent
        )

        if reportedMinutes == 0, isFull {
            return 0
        }

        return BatteryReadingService.preferredTimeToFullMinutes(
            computedTimeToFullMinutes: computedMinutes,
            reportedTimeToFullMinutes: reportedMinutes == 0 ? nil : reportedMinutes
        )
    }

    private static func reconciledStoredChargedState(
        snapshot: BatterySnapshot,
        hasDischargeCurrentEvidence: Bool,
        fullChargeCapacityMilliampHours: Int?,
        storedStateOfChargePercent: Double?
    ) -> Bool {
        guard snapshot.powerState == .fullOnAC,
              hasDischargeCurrentEvidence == false else {
            return false
        }

        if let capacityEvidence = BatteryCalculations.chargedCapacityEvidence(
            currentChargeMilliampHours: snapshot.currentChargeMilliampHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        ) {
            return capacityEvidence
        }

        if let storedStateOfChargePercent {
            return storedStateOfChargePercent >= 95
        }

        return true
    }

    private static func reconciledStoredPowerState(
        originalPowerState: BatteryPowerState,
        derivedPowerState: BatteryPowerState,
        isCharging: Bool,
        isStoredCharged: Bool,
        isExternalPowerConnected: Bool,
        hasCurrentEvidence: Bool
    ) -> BatteryPowerState {
        guard originalPowerState == .unknown,
              isCharging == false,
              isStoredCharged == false,
              isExternalPowerConnected == false,
              hasCurrentEvidence == false else {
            return derivedPowerState
        }

        return .unknown
    }

    private static func signedCurrentMilliampsForStoredPowerState(
        _ value: Int?,
        powerState: BatteryPowerState
    ) -> Int? {
        let value = BatteryCalculations.plausibleSignedCurrentMilliamps(value)

        switch powerState {
        case .connectedNotCharging, .fullOnAC:
            return nil
        case .onBattery, .connectedDischarging:
            return BatteryCalculations.chargeRateMilliamps(from: value) == nil ? value : nil
        case .charging, .unknown:
            return value
        }
    }

}

enum BatteryWidgetMetricFormatting {
    static func percentText(_ value: Double?) -> String {
        guard let percent = BatteryCalculations.presentationPercent(value, maximumAllowed: 105) else {
            return "—"
        }

        return "\(percent.formatted(.number.precision(.fractionLength(0))))%"
    }

    static func timeText(for snapshot: BatterySnapshot?) -> String {
        snapshot?.displayedTimeMinutes.map { BatteryFormatting.compactWidgetDuration(minutes: $0) } ?? "—"
    }

    static func timeProgress(for snapshot: BatterySnapshot?) -> Double? {
        guard let displayedMinutes = snapshot?.displayedTimeMinutes else {
            return nil
        }

        guard displayedMinutes > 0 else {
            return 0
        }

        let normalizedHours = Double(displayedMinutes) / (24 * 60)
        return max(0.15, min(1, normalizedHours))
    }

    static func powerText(for snapshot: BatterySnapshot?) -> String {
        snapshot?.activePowerWatts.map { BatteryFormatting.watts($0) } ?? "—"
    }

    static func clampedProgress(_ value: Double?) -> Double? {
        BatteryCalculations.presentationPercent(value, maximumAllowed: 105).map { $0 / 100 }
    }
}

enum BatteryPowerDisplayRole {
    case power
    case inputPower
    case chargeRate
    case batteryDrain

    var title: String {
        switch self {
        case .power:
            return "Power"
        case .inputPower:
            return "Input Power"
        case .chargeRate:
            return "Charge Rate"
        case .batteryDrain:
            return "Battery Drain"
        }
    }

    var accessibilityNoun: String {
        switch self {
        case .power:
            return "power"
        case .inputPower:
            return "input power"
        case .chargeRate:
            return "charge rate"
        case .batteryDrain:
            return "drain"
        }
    }

    static func role(for snapshot: BatterySnapshot?) -> BatteryPowerDisplayRole {
        guard let snapshot else {
            return .power
        }

        if snapshot.visibleInputPowerWatts != nil {
            return .inputPower
        }

        switch snapshot.powerState {
        case .charging:
            return .chargeRate
        case .connectedDischarging:
            return .batteryDrain
        case .connectedNotCharging, .fullOnAC, .onBattery, .unknown:
            return .power
        }
    }
}

enum BatteryWidgetUpdateFormatting {
    static func statusText(updatedAt: Date?, now: Date = .now) -> String {
        guard let updatedAt else {
            return "No update"
        }

        guard BatterySnapshotFreshnessPolicy.isWithinFutureSkew(updatedAt: updatedAt, now: now) else {
            return "Waiting for update"
        }

        let relativeText = BatterySnapshotFreshnessPolicy.relativeUpdateText(updatedAt: updatedAt, now: now)
        let prefix = BatterySnapshotFreshnessPolicy.isLive(updatedAt: updatedAt, now: now) ? "Updated" : "Stale"
        return "\(prefix) \(relativeText)"
    }

    static func nextStatusChangeDate(updatedAt: Date?, now: Date) -> Date {
        guard let updatedAt else {
            return now.addingTimeInterval(300)
        }

        let statusDate = BatterySnapshotFreshnessPolicy.nextStatusChangeDate(updatedAt: updatedAt, now: now)
        let retentionDate = updatedAt.addingTimeInterval(BatteryWidgetSnapshotStore.defaultRetentionAge + 1)
        guard retentionDate > now else {
            return statusDate
        }

        guard statusDate > now else {
            return retentionDate
        }

        return min(statusDate, retentionDate)
    }
}

enum BatterySnapshotFreshnessPolicy {
    static let allowableFutureSkew: TimeInterval = 60
    static let maximumLiveAge: TimeInterval = BatteryWidgetSnapshotStore.defaultMaximumAge

    static func isLive(updatedAt: Date, now: Date) -> Bool {
        isWithinFutureSkew(updatedAt: updatedAt, now: now)
            && now.timeIntervalSince(updatedAt) <= maximumLiveAge
    }

    static func isWithinFutureSkew(updatedAt: Date, now: Date) -> Bool {
        updatedAt.timeIntervalSince(now) <= allowableFutureSkew
    }

    static func nextRelativeUpdateBoundary(updatedAt: Date, now: Date) -> Date {
        if updatedAt.timeIntervalSince(now) > allowableFutureSkew {
            return updatedAt.addingTimeInterval(-allowableFutureSkew)
        }

        return nextRelativeUpdateDate(updatedAt: updatedAt, now: now)
    }

    static func nextStatusChangeDate(updatedAt: Date, now: Date) -> Date {
        let nextRelativeDate = nextRelativeUpdateBoundary(updatedAt: updatedAt, now: now)
        let liveExpiryDate = updatedAt.addingTimeInterval(maximumLiveAge + 1)

        guard nextRelativeDate > now else {
            return liveExpiryDate > now ? liveExpiryDate : nextRelativeDate
        }

        guard liveExpiryDate > now else {
            return nextRelativeDate
        }

        return min(nextRelativeDate, liveExpiryDate)
    }

    static func relativeUpdateText(updatedAt: Date, now: Date) -> String {
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(updatedAt).rounded(.down)))
        if elapsedSeconds < 60 {
            return "just now"
        }

        let elapsedMinutes = elapsedSeconds / 60
        if elapsedMinutes < 60 {
            return "\(elapsedMinutes)m ago"
        }

        let elapsedHours = elapsedMinutes / 60
        if elapsedHours < 24 {
            return "\(elapsedHours)h ago"
        }

        let elapsedDays = elapsedHours / 24
        return "\(elapsedDays)d ago"
    }

    private static func nextRelativeUpdateDate(updatedAt: Date, now: Date) -> Date {
        let elapsedSeconds = max(0, now.timeIntervalSince(updatedAt))
        if elapsedSeconds < 60 {
            return updatedAt.addingTimeInterval(60)
        }

        if elapsedSeconds < 60 * 60 {
            let elapsedMinute = floor(elapsedSeconds / 60)
            return updatedAt.addingTimeInterval((elapsedMinute + 1) * 60)
        }

        if elapsedSeconds < 24 * 60 * 60 {
            let elapsedHour = floor(elapsedSeconds / (60 * 60))
            return updatedAt.addingTimeInterval((elapsedHour + 1) * 60 * 60)
        }

        let elapsedDay = floor(elapsedSeconds / (24 * 60 * 60))
        return updatedAt.addingTimeInterval((elapsedDay + 1) * 24 * 60 * 60)
    }
}
