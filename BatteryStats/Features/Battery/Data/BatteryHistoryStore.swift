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
        guard entries.isEmpty == false,
              let firstTimestamp = entries.map(\.timestamp).min(),
              let latestTimestamp = entries.map(\.timestamp).max() else {
            return nil
        }

        let powerValues = entries.compactMap(\.activePowerWatts)
        let chargeValues = entries.compactMap(\.stateOfChargePercent)
        let temperatureValues = entries.compactMap(\.temperatureCelsius)

        self.sampleCount = entries.count
        self.firstTimestamp = firstTimestamp
        self.latestTimestamp = latestTimestamp
        averagePowerWatts = Self.average(powerValues)
        peakPowerWatts = powerValues.max()
        minimumChargePercent = chargeValues.min()
        maximumChargePercent = chargeValues.max()
        minimumTemperatureCelsius = temperatureValues.min()
        maximumTemperatureCelsius = temperatureValues.max()
    }

    private static func average(_ values: [Double]) -> Double? {
        guard values.isEmpty == false else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
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
        self.policy = policy

        guard policy.isEnabled else {
            return
        }

        if policy.syncsToICloud {
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
        entries = Array(entries.sorted { $0.timestamp < $1.timestamp }.suffix(288))
        persist()
    }

    func copyCSV() {
        PasteboardCopying.copy(csvString)
    }

    private var csvString: String {
        let header = "timestamp,power_state,health_percent,charge_percent,time_minutes,active_power_watts,temperature_celsius,cycle_count"
        let rows = entries.map { entry in
            [
                Self.isoString(from: entry.timestamp),
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
            cloudStore.synchronize()
        }
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

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
