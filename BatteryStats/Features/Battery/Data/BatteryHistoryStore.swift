import Foundation
import Observation

struct BatteryHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var id: Date { timestamp }

    let timestamp: Date
    let powerState: String
    let healthPercent: Double?
    let stateOfChargePercent: Double?
    let displayedTimeMinutes: Int?
    let activePowerWatts: Double?
    let temperatureCelsius: Double?
    let cycleCount: Int?

    init(snapshot: BatterySnapshot) {
        timestamp = snapshot.timestamp
        powerState = snapshot.powerState.rawValue
        healthPercent = snapshot.healthPercent
        stateOfChargePercent = snapshot.stateOfChargePercent
        displayedTimeMinutes = snapshot.displayedTimeMinutes
        activePowerWatts = snapshot.activePowerWatts
        temperatureCelsius = snapshot.temperatureCelsius
        cycleCount = snapshot.cycleCount
    }
}

struct BatteryHistoryStats: Equatable, Sendable {
    let sampleCount: Int
    let firstTimestamp: Date
    let latestTimestamp: Date
    let averagePowerWatts: Double?
    let peakPowerWatts: Double?
    let minimumChargePercent: Double?
    let maximumChargePercent: Double?
    let minimumTemperatureCelsius: Double?
    let maximumTemperatureCelsius: Double?

    init?(entries: [BatteryHistoryEntry]) {
        guard let firstEntry = entries.first else {
            return nil
        }

        self.sampleCount = entries.count
        var firstTimestamp = firstEntry.timestamp
        var latestTimestamp = firstEntry.timestamp
        var powerTotal = 0.0
        var powerCount = 0
        var peakPowerWatts: Double?
        var minimumChargePercent: Double?
        var maximumChargePercent: Double?
        var minimumTemperatureCelsius: Double?
        var maximumTemperatureCelsius: Double?

        for entry in entries {
            firstTimestamp = min(firstTimestamp, entry.timestamp)
            latestTimestamp = max(latestTimestamp, entry.timestamp)

            if let activePowerWatts = entry.activePowerWatts {
                powerTotal += activePowerWatts
                powerCount += 1
                peakPowerWatts = max(peakPowerWatts ?? activePowerWatts, activePowerWatts)
            }

            if let chargePercent = entry.stateOfChargePercent {
                minimumChargePercent = min(minimumChargePercent ?? chargePercent, chargePercent)
                maximumChargePercent = max(maximumChargePercent ?? chargePercent, chargePercent)
            }

            if let temperatureCelsius = entry.temperatureCelsius {
                minimumTemperatureCelsius = min(minimumTemperatureCelsius ?? temperatureCelsius, temperatureCelsius)
                maximumTemperatureCelsius = max(maximumTemperatureCelsius ?? temperatureCelsius, temperatureCelsius)
            }
        }

        self.firstTimestamp = firstTimestamp
        self.latestTimestamp = latestTimestamp
        self.averagePowerWatts = powerCount == 0 ? nil : powerTotal / Double(powerCount)
        self.peakPowerWatts = peakPowerWatts
        self.minimumChargePercent = minimumChargePercent
        self.maximumChargePercent = maximumChargePercent
        self.minimumTemperatureCelsius = minimumTemperatureCelsius
        self.maximumTemperatureCelsius = maximumTemperatureCelsius
    }
}

@MainActor
@Observable
final class BatteryHistoryStore {
    private enum Key {
        static let localEntries = "batteryHistoryEntries"
        static let cloudEntries = "batteryHistoryEntries"
    }

    var entries: [BatteryHistoryEntry] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cloudStore: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var policy = BatteryHistoryPolicy.disabled
    @ObservationIgnored private var cloudSynchronizeTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, cloudStore: NSUbiquitousKeyValueStore? = nil) {
        self.defaults = defaults
        self.cloudStore = cloudStore
        entries = Self.decodeEntries(from: defaults.string(forKey: Key.localEntries))
    }

    var summaryText: String {
        guard entries.isEmpty == false else {
            return "No history recorded yet."
        }

        return "\(entries.count) samples stored locally."
    }

    var stats: BatteryHistoryStats? {
        BatteryHistoryStats(entries: entries)
    }

    func updatePolicy(_ policy: BatteryHistoryPolicy) {
        self.policy = BatteryHistoryPolicy(
            isEnabled: policy.isEnabled,
            syncsToICloud: policy.syncsToICloud && canUseCloudStore
        )

        guard self.policy.isEnabled else {
            return
        }

        if self.policy.syncsToICloud {
            mergeCloudEntries()
        }

        persist()
    }

    func record(_ snapshot: BatterySnapshot) {
        guard policy.isEnabled else {
            return
        }

        let entry = BatteryHistoryEntry(snapshot: snapshot)
        guard shouldRecord(entry) else {
            return
        }

        entries.append(entry)
        trimAndSortIfNeeded()
        persist()
    }

    func copyCSV() {
        PasteboardCopying.copy(csvString)
    }

    private var csvString: String {
        let header = "timestamp,power_state,health_percent,charge_percent,time_minutes,active_power_watts,temperature_celsius,cycle_count"
        let formatter = Self.makeISOFormatter()
        let rows = entries.map { entry in
            [
                Self.isoString(from: entry.timestamp, formatter: formatter),
                entry.powerState,
                Self.csvValue(entry.healthPercent),
                Self.csvValue(entry.stateOfChargePercent),
                entry.displayedTimeMinutes.map(String.init) ?? "",
                Self.csvValue(entry.activePowerWatts),
                Self.csvValue(entry.temperatureCelsius),
                entry.cycleCount.map(String.init) ?? ""
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    private func shouldRecord(_ entry: BatteryHistoryEntry) -> Bool {
        guard let previous = entries.last else {
            return true
        }

        if entry.timestamp.timeIntervalSince(previous.timestamp) >= 300 {
            return true
        }

        if entry.powerState != previous.powerState {
            return true
        }

        if BatteryRefreshPolicy.isSignificantEnergyChange(
            previous: previous.activePowerWatts,
            current: entry.activePowerWatts,
            thresholdPercent: 35
        ) {
            return true
        }

        if let previousCharge = previous.stateOfChargePercent,
           let currentCharge = entry.stateOfChargePercent,
           abs(currentCharge - previousCharge) >= 2 {
            return true
        }

        return false
    }

    private func mergeCloudEntries() {
        let cloudStore = resolvedCloudStore
        cloudStore.synchronize()
        let cloudEntries = Self.decodeEntries(from: cloudStore.string(forKey: Key.cloudEntries))
        guard cloudEntries.isEmpty == false else {
            return
        }

        entries = Array((entries + cloudEntries)
            .reduce(into: [Date: BatteryHistoryEntry]()) { partialResult, entry in
                partialResult[entry.timestamp] = entry
            }
            .values
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(288))
    }

    private func persist() {
        guard let encodedEntries = Self.encodeEntries(entries) else {
            return
        }

        defaults.set(encodedEntries, forKey: Key.localEntries)

        if policy.syncsToICloud {
            let cloudStore = resolvedCloudStore
            cloudStore.set(encodedEntries, forKey: Key.cloudEntries)
            scheduleCloudSynchronize()
        }
    }

    private func trimAndSortIfNeeded() {
        if let previous = entries.dropLast().last,
           let latest = entries.last,
           latest.timestamp < previous.timestamp {
            entries.sort { $0.timestamp < $1.timestamp }
        }

        if entries.count > 288 {
            entries.removeFirst(entries.count - 288)
        }
    }

    func flushPendingWrites() {
        cloudSynchronizeTask?.cancel()
        cloudSynchronizeTask = nil

        guard policy.syncsToICloud else {
            return
        }

        resolvedCloudStore.synchronize()
    }

    private func scheduleCloudSynchronize() {
        cloudSynchronizeTask?.cancel()
        cloudSynchronizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard Task.isCancelled == false else {
                return
            }

            self?.resolvedCloudStore.synchronize()
            self?.cloudSynchronizeTask = nil
        }
    }

    private var canUseCloudStore: Bool {
        cloudStore != nil || ICloudKeyValueStoreAvailability.isAvailable
    }

    private var resolvedCloudStore: NSUbiquitousKeyValueStore {
        if let cloudStore {
            return cloudStore
        }

        let store = NSUbiquitousKeyValueStore.default
        cloudStore = store
        return store
    }

    private static func decodeEntries(from string: String?) -> [BatteryHistoryEntry] {
        guard let string,
              let data = string.data(using: .utf8),
              let entries = try? JSONDecoder().decode([BatteryHistoryEntry].self, from: data) else {
            return []
        }

        return entries
    }

    private static func encodeEntries(_ entries: [BatteryHistoryEntry]) -> String? {
        guard let data = try? JSONEncoder().encode(entries) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func csvValue(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? ""
    }

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func isoString(from date: Date, formatter: ISO8601DateFormatter) -> String {
        return formatter.string(from: date)
    }
}
