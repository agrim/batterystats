import Foundation
import Observation

enum BatteryHistoryPowerRole: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case batteryDrain
    case batteryCharge
    case inputPower
    case unknown

    static let comparableCases: [BatteryHistoryPowerRole] = [.batteryDrain, .batteryCharge, .inputPower]

    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct BatteryHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var id: Date { timestamp }

    let timestamp: Date
    let powerState: String
    let healthPercent: Double?
    let stateOfChargePercent: Double?
    let displayedTimeMinutes: Int?
    let activePowerWatts: Double?
    let powerRole: BatteryHistoryPowerRole?
    let temperatureCelsius: Double?
    let cycleCount: Int?

    func normalized() -> BatteryHistoryEntry {
        let powerState = BatteryPowerState(rawValue: powerState) ?? .unknown
        let activePowerWatts = Self.activePowerWatts(activePowerWatts, powerState: powerState)
        return BatteryHistoryEntry(
            timestamp: timestamp,
            powerState: powerState.rawValue,
            healthPercent: BatteryCalculations.presentationPercent(healthPercent, maximumAllowed: 120),
            stateOfChargePercent: BatteryCalculations.presentationPercent(stateOfChargePercent, maximumAllowed: 105),
            displayedTimeMinutes: Self.displayedTimeMinutes(displayedTimeMinutes, powerState: powerState),
            activePowerWatts: activePowerWatts,
            powerRole: Self.normalizedPowerRole(
                powerRole,
                powerState: powerState,
                activePowerWatts: activePowerWatts
            ),
            temperatureCelsius: BatteryCalculations.plausibleTemperatureCelsius(temperatureCelsius),
            cycleCount: BatteryCalculations.plausibleCycleCount(cycleCount)
        )
    }

    private static func displayedTimeMinutes(_ value: Int?, powerState: BatteryPowerState) -> Int? {
        guard powerState == .charging || powerState.isBatteryDischarging else {
            return nil
        }

        return BatteryCalculations.plausibleDurationMinutes(value)
    }

    private static func activePowerWatts(_ value: Double?, powerState: BatteryPowerState) -> Double? {
        guard powerState != .unknown else {
            return nil
        }

        return BatteryCalculations.plausibleWatts(value)
    }

    private static func powerRole(
        for snapshot: BatterySnapshot,
        activePowerWatts: Double?
    ) -> BatteryHistoryPowerRole? {
        guard activePowerWatts != nil else {
            return nil
        }

        if snapshot.visibleInputPowerWatts != nil {
            return .inputPower
        }

        switch snapshot.powerState {
        case .charging:
            return .batteryCharge
        case .onBattery, .connectedDischarging:
            return .batteryDrain
        case .connectedNotCharging, .fullOnAC, .unknown:
            return nil
        }
    }

    private static func normalizedPowerRole(
        _ storedRole: BatteryHistoryPowerRole?,
        powerState: BatteryPowerState,
        activePowerWatts: Double?
    ) -> BatteryHistoryPowerRole? {
        guard activePowerWatts != nil else {
            return nil
        }

        if let storedRole,
           storedRole != .unknown,
           storedRole.isCompatible(with: powerState) {
            return storedRole
        }

        switch powerState {
        case .onBattery:
            return .batteryDrain
        case .connectedNotCharging, .fullOnAC:
            return .inputPower
        case .charging, .connectedDischarging, .unknown:
            // Legacy active-power values are ambiguous in these states because
            // they may represent either adapter input or a battery-side rate.
            return nil
        }
    }
}

extension BatteryHistoryEntry {
    init(snapshot: BatterySnapshot) {
        let powerState = snapshot.powerState
        let activePowerWatts = Self.activePowerWatts(snapshot.activePowerWatts, powerState: powerState)
        self.init(
            timestamp: snapshot.timestamp,
            powerState: powerState.rawValue,
            healthPercent: BatteryCalculations.presentationPercent(snapshot.healthPercent, maximumAllowed: 120),
            stateOfChargePercent: BatteryCalculations.presentationPercent(snapshot.stateOfChargePercent, maximumAllowed: 105),
            displayedTimeMinutes: Self.displayedTimeMinutes(snapshot.displayedTimeMinutes, powerState: powerState),
            activePowerWatts: activePowerWatts,
            powerRole: Self.powerRole(for: snapshot, activePowerWatts: activePowerWatts),
            temperatureCelsius: BatteryCalculations.plausibleTemperatureCelsius(snapshot.temperatureCelsius),
            cycleCount: BatteryCalculations.plausibleCycleCount(snapshot.cycleCount)
        )
    }
}

struct BatteryHistoryPowerStats: Equatable, Sendable {
    let role: BatteryHistoryPowerRole
    let sampleCount: Int
    let observedDuration: TimeInterval
    let timeWeightedAverageWatts: Double?
    let peakWatts: Double
}

struct BatteryHistoryStats: Equatable, Sendable {
    private static let maximumContinuousPowerObservationInterval: TimeInterval = 10 * 60

    let sampleCount: Int
    let firstTimestamp: Date
    let latestTimestamp: Date
    let powerStats: [BatteryHistoryPowerStats]
    let minimumChargePercent: Double?
    let maximumChargePercent: Double?
    let minimumTemperatureCelsius: Double?
    let maximumTemperatureCelsius: Double?

    init?(entries: [BatteryHistoryEntry]) {
        guard entries.isEmpty == false else {
            return nil
        }

        let normalizedEntries = entries
            .map { $0.normalized() }
            .sorted { $0.timestamp < $1.timestamp }

        self.sampleCount = normalizedEntries.count
        self.firstTimestamp = normalizedEntries[0].timestamp
        self.latestTimestamp = normalizedEntries[normalizedEntries.count - 1].timestamp
        var powerAccumulators: [BatteryHistoryPowerRole: BatteryHistoryPowerAccumulator] = [:]
        var minimumChargePercent: Double?
        var maximumChargePercent: Double?
        var minimumTemperatureCelsius: Double?
        var maximumTemperatureCelsius: Double?
        var previousEntry: BatteryHistoryEntry?

        // Each value describes the state until the next observation. The final
        // point therefore affects the peak but not the weighted mean.
        for entry in normalizedEntries {
            if let previousEntry {
                let duration = entry.timestamp.timeIntervalSince(previousEntry.timestamp)
                if let measurement = previousEntry.powerMeasurement,
                   duration > 0,
                   duration.isFinite,
                   duration <= Self.maximumContinuousPowerObservationInterval {
                    var accumulator = powerAccumulators[measurement.role] ?? BatteryHistoryPowerAccumulator()
                    accumulator.record(watts: measurement.watts, duration: duration)
                    powerAccumulators[measurement.role] = accumulator
                }
            }

            if let measurement = entry.powerMeasurement {
                var accumulator = powerAccumulators[measurement.role] ?? BatteryHistoryPowerAccumulator()
                accumulator.observe(watts: measurement.watts)
                powerAccumulators[measurement.role] = accumulator
            }

            if let chargePercent = entry.stateOfChargePercent, chargePercent.isFinite {
                minimumChargePercent = min(minimumChargePercent ?? chargePercent, chargePercent)
                maximumChargePercent = max(maximumChargePercent ?? chargePercent, chargePercent)
            }

            if let temperatureCelsius = entry.temperatureCelsius, temperatureCelsius.isFinite {
                minimumTemperatureCelsius = min(minimumTemperatureCelsius ?? temperatureCelsius, temperatureCelsius)
                maximumTemperatureCelsius = max(maximumTemperatureCelsius ?? temperatureCelsius, temperatureCelsius)
            }

            previousEntry = entry
        }

        self.powerStats = BatteryHistoryPowerRole.comparableCases.compactMap { role in
            powerAccumulators[role]?.stats(for: role)
        }
        self.minimumChargePercent = minimumChargePercent
        self.maximumChargePercent = maximumChargePercent
        self.minimumTemperatureCelsius = minimumTemperatureCelsius
        self.maximumTemperatureCelsius = maximumTemperatureCelsius
    }

    func powerStats(for role: BatteryHistoryPowerRole) -> BatteryHistoryPowerStats? {
        powerStats.first { $0.role == role }
    }
}

private extension BatteryHistoryPowerRole {
    func isCompatible(with powerState: BatteryPowerState) -> Bool {
        switch self {
        case .batteryDrain:
            return powerState.isBatteryDischarging
        case .batteryCharge:
            return powerState == .charging
        case .inputPower:
            return powerState.isExternallyPowered
        case .unknown:
            return false
        }
    }
}

private extension BatteryHistoryEntry {
    var powerMeasurement: (role: BatteryHistoryPowerRole, watts: Double)? {
        guard let powerRole,
              powerRole != .unknown,
              let activePowerWatts,
              activePowerWatts.isFinite else {
            return nil
        }

        return (powerRole, activePowerWatts)
    }
}

private struct BatteryHistoryPowerAccumulator {
    private(set) var sampleCount = 0
    private(set) var observedDuration: TimeInterval = 0
    private(set) var weightedPowerSeconds = 0.0
    private(set) var peakWatts: Double?

    mutating func observe(watts: Double) {
        sampleCount += 1
        peakWatts = max(peakWatts ?? watts, watts)
    }

    mutating func record(watts: Double, duration: TimeInterval) {
        let weightedValue = watts * duration
        guard weightedValue.isFinite else {
            return
        }

        observedDuration += duration
        weightedPowerSeconds += weightedValue
    }

    func stats(for role: BatteryHistoryPowerRole) -> BatteryHistoryPowerStats? {
        guard let peakWatts else {
            return nil
        }

        let average = observedDuration > 0 && weightedPowerSeconds.isFinite
            ? weightedPowerSeconds / observedDuration
            : nil
        return BatteryHistoryPowerStats(
            role: role,
            sampleCount: sampleCount,
            observedDuration: observedDuration,
            timeWeightedAverageWatts: average,
            peakWatts: peakWatts
        )
    }
}

enum BatteryHistoryTextFormatting {
    static func sampleCountText(_ count: Int) -> String {
        count == 1 ? "1 sample" : "\(count) samples"
    }

    static func summary(count: Int, syncsToICloud: Bool) -> String {
        let storageText = syncsToICloud ? "synced with iCloud" : "stored locally"
        return "\(sampleCountText(count)) \(storageText)."
    }
}

@MainActor
protocol BatteryHistoryCloudStoring: AnyObject {
    func synchronize() -> Bool
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol
    func removeObserver(_ token: NSObjectProtocol)
}

extension NSUbiquitousKeyValueStore: BatteryHistoryCloudStoring {
    func setString(_ value: String, forKey key: String) {
        set(value, forKey: key)
    }

    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self,
            queue: .main
        ) { notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            handler(keys)
        }
    }

    func removeObserver(_ token: NSObjectProtocol) {
        NotificationCenter.default.removeObserver(token)
    }
}

@MainActor
@Observable
final class BatteryHistoryStore {
    private enum Key {
        static let localEntries = "batteryHistoryEntries"
        static let cloudEntries = "batteryHistoryEntries"
    }

    private static let significantTemperatureChangeThresholdCelsius = 2.0

    var entries: [BatteryHistoryEntry] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cloudStore: (any BatteryHistoryCloudStoring)?
    @ObservationIgnored private let pasteboardCopy: @MainActor (String) -> Void
    @ObservationIgnored private let cloudSynchronizeDelay: Duration
    private var policy = BatteryHistoryPolicy.disabled
    @ObservationIgnored private var cloudSynchronizeTask: Task<Void, Never>?
    @ObservationIgnored private var cloudObserverToken: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        cloudStore: (any BatteryHistoryCloudStoring)? = nil,
        pasteboardCopy: @escaping @MainActor (String) -> Void = PasteboardCopying.copy,
        cloudSynchronizeDelay: Duration = .milliseconds(750)
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
        self.pasteboardCopy = pasteboardCopy
        self.cloudSynchronizeDelay = cloudSynchronizeDelay

        let storedEntries = defaults.string(forKey: Key.localEntries)
        entries = Self.decodeHistoryEntries(from: storedEntries)?.entries ?? []
        rewriteNormalizedLocalEntriesIfNeeded(previouslyStoredEntries: storedEntries)
    }

    isolated deinit {
        stopObservingCloudEntries()
        cancelCloudSynchronize()
    }

    var summaryText: String {
        guard entries.isEmpty == false else {
            return "No history recorded yet."
        }

        return BatteryHistoryTextFormatting.summary(count: entries.count, syncsToICloud: policy.syncsToICloud)
    }

    var stats: BatteryHistoryStats? {
        BatteryHistoryStats(entries: entries)
    }

    @discardableResult
    func updatePolicy(_ policy: BatteryHistoryPolicy) -> Bool {
        let previousPolicy = self.policy
        let resolvedPolicy = BatteryHistoryPolicy(
            isEnabled: policy.isEnabled,
            syncsToICloud: policy.isEnabled && policy.syncsToICloud && canUseCloudStore
        )

        guard resolvedPolicy != previousPolicy else {
            if resolvedPolicy.isEnabled == false {
                clearHistory(syncsToCloud: false)
            }
            return false
        }

        self.policy = resolvedPolicy

        if self.policy.syncsToICloud == false {
            stopObservingCloudEntries()
            cancelCloudSynchronize()
        }

        guard self.policy.isEnabled else {
            clearHistory(syncsToCloud: previousPolicy.syncsToICloud)
            return false
        }

        if self.policy.syncsToICloud {
            startObservingCloudEntries()
            _ = mergeCloudEntries(
                allowsEmptyCloudReplacement: false,
                allowsMissingCloudReplacement: false
            )
        }

        persist()
        return previousPolicy.isEnabled == false
    }

    private func clearHistory(syncsToCloud: Bool) {
        if entries.isEmpty == false {
            entries = []
        }

        let encodedEntries = "[]"
        if defaults.string(forKey: Key.localEntries) != encodedEntries {
            defaults.set(encodedEntries, forKey: Key.localEntries)
        }

        guard syncsToCloud else {
            return
        }

        let cloudStore = resolvedCloudStore
        guard cloudStore.string(forKey: Key.cloudEntries) != encodedEntries else {
            return
        }

        cloudStore.setString(encodedEntries, forKey: Key.cloudEntries)
        _ = cloudStore.synchronize()
    }

    func record(_ snapshot: BatterySnapshot) {
        guard policy.isEnabled else {
            return
        }

        let entry = BatteryHistoryEntry(snapshot: snapshot)
        guard shouldRecord(entry) else {
            return
        }

        let normalizedEntries = Self.normalizedEntries(entries + [entry])
        guard normalizedEntries != entries else {
            return
        }

        entries = normalizedEntries
        persist()
    }

    @discardableResult
    func copyCSV() -> Bool {
        guard entries.isEmpty == false else {
            return false
        }

        pasteboardCopy(csvString)
        return true
    }

    private var csvString: String {
        let header = "timestamp,power_state,health_percent,charge_percent,time_minutes,power_role,active_power_watts,temperature_celsius,cycle_count"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows = entries.map { entry in
            [
                formatter.string(from: entry.timestamp),
                entry.powerState,
                Self.csvValue(entry.healthPercent),
                Self.csvValue(entry.stateOfChargePercent),
                entry.displayedTimeMinutes.map(String.init) ?? "",
                entry.powerRole?.rawValue ?? "",
                Self.csvValue(entry.activePowerWatts),
                Self.csvValue(entry.temperatureCelsius),
                entry.cycleCount.map(String.init) ?? ""
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    private func shouldRecord(_ entry: BatteryHistoryEntry) -> Bool {
        guard let comparisonEntry = nearestEntry(to: entry.timestamp) else {
            return true
        }

        if entry.timestamp == comparisonEntry.timestamp {
            return true
        }

        if abs(entry.timestamp.timeIntervalSince(comparisonEntry.timestamp)) >= 300 {
            return true
        }

        if entry.powerState != comparisonEntry.powerState {
            return true
        }

        if entry.powerRole != comparisonEntry.powerRole {
            return true
        }

        if BatteryRefreshPolicy.isSignificantEnergyChange(
            previous: comparisonEntry.activePowerWatts,
            current: entry.activePowerWatts,
            thresholdPercent: 35
        ) {
            return true
        }

        if let previousCharge = comparisonEntry.stateOfChargePercent,
           let currentCharge = entry.stateOfChargePercent,
           abs(currentCharge - previousCharge) >= 2 {
            return true
        }

        if let previousTemperature = comparisonEntry.temperatureCelsius,
           let currentTemperature = entry.temperatureCelsius,
           abs(currentTemperature - previousTemperature) >= Self.significantTemperatureChangeThresholdCelsius {
            return true
        }

        if let previousCycleCount = comparisonEntry.cycleCount,
           let currentCycleCount = entry.cycleCount,
           previousCycleCount != currentCycleCount {
            return true
        }

        if (comparisonEntry.healthPercent == nil) != (entry.healthPercent == nil)
            || (comparisonEntry.stateOfChargePercent == nil) != (entry.stateOfChargePercent == nil)
            || (comparisonEntry.displayedTimeMinutes == nil) != (entry.displayedTimeMinutes == nil)
            || (comparisonEntry.activePowerWatts == nil) != (entry.activePowerWatts == nil)
            || (comparisonEntry.temperatureCelsius == nil) != (entry.temperatureCelsius == nil)
            || (comparisonEntry.cycleCount == nil) != (entry.cycleCount == nil) {
            return true
        }

        return false
    }

    private func nearestEntry(to timestamp: Date) -> BatteryHistoryEntry? {
        entries.min { first, second in
            abs(first.timestamp.timeIntervalSince(timestamp)) < abs(second.timestamp.timeIntervalSince(timestamp))
        }
    }

    @discardableResult
    private func mergeCloudEntries(
        allowsEmptyCloudReplacement: Bool,
        allowsMissingCloudReplacement: Bool
    ) -> Bool {
        let cloudStore = resolvedCloudStore
        _ = cloudStore.synchronize()

        guard let cloudHistoryString = cloudStore.string(forKey: Key.cloudEntries) else {
            guard allowsMissingCloudReplacement, entries.isEmpty == false else {
                return false
            }

            entries = []
            return true
        }

        guard let decodedCloudEntries = Self.decodeHistoryEntries(from: cloudHistoryString) else {
            repairMalformedCloudEntries(cloudStore: cloudStore)
            return false
        }
        let normalizedCloudHistoryString = Self.encodeEntries(decodedCloudEntries.entries)
        let cloudHistoryNeedsRepair = normalizedCloudHistoryString != cloudHistoryString

        if decodedCloudEntries.entries.isEmpty {
            guard decodedCloudEntries.rawEntryCount == 0 else {
                repairMalformedCloudEntries(cloudStore: cloudStore)
                return false
            }

            guard allowsEmptyCloudReplacement, entries.isEmpty == false else {
                return false
            }

            entries = []
            return true
        }

        let mergedEntries = Self.normalizedEntries(entries + decodedCloudEntries.entries)
        guard mergedEntries != entries else {
            return cloudHistoryNeedsRepair
        }

        entries = mergedEntries
        return true
    }

    private func persist() {
        guard let encodedEntries = Self.encodeEntries(entries) else {
            return
        }

        defaults.set(encodedEntries, forKey: Key.localEntries)

        if policy.syncsToICloud {
            let cloudStore = resolvedCloudStore
            cloudStore.setString(encodedEntries, forKey: Key.cloudEntries)
            scheduleCloudSynchronize()
        }
    }

    private func repairMalformedCloudEntries(cloudStore: any BatteryHistoryCloudStoring) {
        guard let encodedEntries = Self.encodeEntries(entries) else {
            return
        }

        cloudStore.setString(encodedEntries, forKey: Key.cloudEntries)
        scheduleCloudSynchronize()
    }

    private func rewriteNormalizedLocalEntriesIfNeeded(previouslyStoredEntries: String?) {
        guard let previouslyStoredEntries,
              let normalizedEntries = Self.encodeEntries(entries),
              normalizedEntries != previouslyStoredEntries else {
            return
        }

        defaults.set(normalizedEntries, forKey: Key.localEntries)
    }

    func flushPendingWrites() {
        cancelCloudSynchronize()

        guard policy.syncsToICloud else {
            return
        }

        _ = resolvedCloudStore.synchronize()
    }

    private func scheduleCloudSynchronize() {
        cancelCloudSynchronize()
        cloudSynchronizeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: cloudSynchronizeDelay)
            guard Task.isCancelled == false,
                  policy.syncsToICloud else {
                return
            }

            _ = resolvedCloudStore.synchronize()
            cloudSynchronizeTask = nil
        }
    }

    private func cancelCloudSynchronize() {
        cloudSynchronizeTask?.cancel()
        cloudSynchronizeTask = nil
    }

    private func startObservingCloudEntries() {
        guard cloudObserverToken == nil else {
            return
        }

        cloudObserverToken = resolvedCloudStore.observeChanges { [weak self] changedKeys in
            Task { @MainActor in
                self?.handleCloudEntriesChanged(keys: changedKeys)
            }
        }
    }

    private func stopObservingCloudEntries() {
        guard let cloudObserverToken else {
            return
        }

        resolvedCloudStore.removeObserver(cloudObserverToken)
        self.cloudObserverToken = nil
    }

    private func handleCloudEntriesChanged(keys: [String]) {
        guard policy.syncsToICloud else {
            return
        }

        guard keys.isEmpty || keys.contains(Key.cloudEntries) else {
            return
        }

        if mergeCloudEntries(
            allowsEmptyCloudReplacement: true,
            allowsMissingCloudReplacement: keys.contains(Key.cloudEntries)
        ) {
            persist()
        }
    }

    private var canUseCloudStore: Bool {
        cloudStore != nil || ICloudKeyValueStoreAvailability.isAvailable
    }

    private var resolvedCloudStore: any BatteryHistoryCloudStoring {
        if let cloudStore {
            return cloudStore
        }

        let store = NSUbiquitousKeyValueStore.default
        cloudStore = store
        return store
    }

    private struct DecodedHistoryEntries {
        let entries: [BatteryHistoryEntry]
        let rawEntryCount: Int
    }

    private static func decodeHistoryEntries(from string: String?) -> DecodedHistoryEntries? {
        guard let string,
              let data = string.data(using: .utf8),
              let entries = try? JSONDecoder().decode([BatteryHistoryEntry].self, from: data) else {
            return nil
        }

        return DecodedHistoryEntries(
            entries: normalizedEntries(entries),
            rawEntryCount: entries.count
        )
    }

    private static func encodeEntries(_ entries: [BatteryHistoryEntry]) -> String? {
        guard let data = try? JSONEncoder().encode(entries) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func csvValue(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return ""
        }

        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func normalizedEntries(_ entries: [BatteryHistoryEntry], now: Date = Date()) -> [BatteryHistoryEntry] {
        Array(entries
            .reduce(into: [Date: BatteryHistoryEntry]()) { partialResult, entry in
                let normalizedEntry = entry.normalized()
                guard BatterySnapshotFreshnessPolicy.isWithinFutureSkew(updatedAt: normalizedEntry.timestamp, now: now) else {
                    return
                }

                if let existingEntry = partialResult[normalizedEntry.timestamp],
                   normalizedEntry.completenessScore < existingEntry.completenessScore {
                    return
                }

                partialResult[normalizedEntry.timestamp] = normalizedEntry
            }
            .values
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(288))
    }

}

private extension BatteryHistoryEntry {
    var completenessScore: Int {
        var score = powerState == BatteryPowerState.unknown.rawValue ? 0 : 1
        score += healthPercent == nil ? 0 : 1
        score += stateOfChargePercent == nil ? 0 : 1
        score += displayedTimeMinutes == nil ? 0 : 1
        score += activePowerWatts == nil ? 0 : 1
        score += powerRole == nil || powerRole == .unknown ? 0 : 1
        score += temperatureCelsius == nil ? 0 : 1
        score += cycleCount == nil ? 0 : 1
        return score
    }
}
