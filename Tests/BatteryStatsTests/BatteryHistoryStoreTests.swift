import XCTest
@testable import BatteryStats

@MainActor
final class BatteryHistoryStoreTests: XCTestCase {
    func testStatsAreNilWhenNoHistoryHasBeenRecorded() {
        let store = makeStore()

        XCTAssertNil(store.stats)
        XCTAssertEqual(store.summaryText, "No history recorded yet.")
    }

    func testHistorySampleTextUsesSingularAndPluralForms() {
        XCTAssertEqual(BatteryHistoryTextFormatting.sampleCountText(1), "1 sample")
        XCTAssertEqual(BatteryHistoryTextFormatting.sampleCountText(2), "2 samples")
    }

    func testHistorySummaryTextReflectsStorageDestination() {
        XCTAssertEqual(
            BatteryHistoryTextFormatting.summary(count: 1, syncsToICloud: false),
            "1 sample stored locally."
        )
        XCTAssertEqual(
            BatteryHistoryTextFormatting.summary(count: 2, syncsToICloud: true),
            "2 samples synced with iCloud."
        )
    }

    func testSummaryTextUsesSingularForOneStoredHistorySample() {
        let store = makeStore()
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            chargePercent: 88,
            powerWatts: 10,
            temperatureCelsius: 29.5
        ))

        XCTAssertEqual(store.summaryText, "1 sample stored locally.")
    }

    func testSummaryTextReflectsResolvedICloudHistorySyncPolicy() {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))

        store.record(makeSnapshot(
            timestamp: timestamp,
            chargePercent: 88,
            powerWatts: 10,
            temperatureCelsius: 29.5
        ))

        XCTAssertEqual(store.summaryText, "1 sample synced with iCloud.")

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        XCTAssertEqual(store.summaryText, "1 sample stored locally.")
    }

    func testStatsSummarizeRecordedHistory() throws {
        let store = makeStore()
        let firstTimestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: firstTimestamp, chargePercent: 88, powerWatts: 10, temperatureCelsius: 29.5))
        store.record(makeSnapshot(timestamp: firstTimestamp.addingTimeInterval(301), chargePercent: 81, powerWatts: 15, temperatureCelsius: 32.0))
        store.record(makeSnapshot(timestamp: firstTimestamp.addingTimeInterval(602), chargePercent: 72, powerWatts: 30, temperatureCelsius: 35.2))

        let stats = try XCTUnwrap(store.stats)
        XCTAssertEqual(stats.sampleCount, 3)
        XCTAssertEqual(stats.firstTimestamp, firstTimestamp)
        XCTAssertEqual(stats.latestTimestamp, firstTimestamp.addingTimeInterval(602))
        XCTAssertEqual(try XCTUnwrap(stats.averagePowerWatts), 18.33, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.peakPowerWatts), 30, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.minimumChargePercent), 72, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.maximumChargePercent), 88, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.minimumTemperatureCelsius), 29.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.maximumTemperatureCelsius), 35.2, accuracy: 0.01)
    }

    func testStatsNormalizeDecodedMalformedEntriesBeforeAggregating() throws {
        let data = Data("""
        [
          {
            "timestamp": 1000,
            "powerState": "connectedNotCharging",
            "healthPercent": 115,
            "stateOfChargePercent": 105,
            "displayedTimeMinutes": 120,
            "activePowerWatts": 1500,
            "temperatureCelsius": 180,
            "cycleCount": -1
          },
          {
            "timestamp": 1300,
            "powerState": "onBattery",
            "healthPercent": 83,
            "stateOfChargePercent": 60,
            "displayedTimeMinutes": 90,
            "activePowerWatts": 10,
            "temperatureCelsius": 30,
            "cycleCount": 2
          }
        ]
        """.utf8)
        let entries = try JSONDecoder().decode([BatteryHistoryEntry].self, from: data)

        let stats = try XCTUnwrap(BatteryHistoryStats(entries: entries))

        XCTAssertEqual(stats.sampleCount, 2)
        XCTAssertEqual(try XCTUnwrap(stats.averagePowerWatts), 10, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.peakPowerWatts), 10, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.minimumChargePercent), 60, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.maximumChargePercent), 100, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.minimumTemperatureCelsius), 30, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(stats.maximumTemperatureCelsius), 30, accuracy: 0.01)
    }

    func testCapturedHistoryTextDoesNotCreateRangeForSingleSample() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let stats = try XCTUnwrap(BatteryHistoryStats(entries: [
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: timestamp,
                chargePercent: 88,
                powerWatts: 10,
                temperatureCelsius: 29.5
            ))
        ]))

        let text = HistoryStatsFormatting.capturedText(for: stats)

        XCTAssertEqual(text, HistoryStatsFormatting.dateText(timestamp))
        XCTAssertFalse(text.contains(" - "))
    }

    func testCapturedHistoryTextKeepsCompactSameDayRangeForMultipleSamples() throws {
        let firstTimestamp = Date(timeIntervalSince1970: 1_000)
        let latestTimestamp = firstTimestamp.addingTimeInterval(301)
        let stats = try XCTUnwrap(BatteryHistoryStats(entries: [
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: firstTimestamp,
                chargePercent: 88,
                powerWatts: 10,
                temperatureCelsius: 29.5
            )),
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: latestTimestamp,
                chargePercent: 81,
                powerWatts: 15,
                temperatureCelsius: 32.0
            ))
        ]))

        XCTAssertEqual(
            HistoryStatsFormatting.capturedText(for: stats),
            "\(HistoryStatsFormatting.dateText(firstTimestamp)) - \(HistoryStatsFormatting.timeText(latestTimestamp))"
        )
    }

    func testHistoryKeepsEntriesChronologicalWhenOlderSampleArrivesLater() {
        let store = makeStore()
        let firstTimestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: firstTimestamp.addingTimeInterval(301), chargePercent: 81, powerWatts: 15, temperatureCelsius: 32.0))
        store.record(makeSnapshot(timestamp: firstTimestamp, chargePercent: 88, powerWatts: 10, temperatureCelsius: 29.5))

        XCTAssertEqual(store.entries.map(\.timestamp), [firstTimestamp, firstTimestamp.addingTimeInterval(301)])
    }

    func testHistoryReplacesDuplicateTimestampDuringRecording() {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 70, powerWatts: 15, temperatureCelsius: 32))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.timestamp, timestamp)
        XCTAssertEqual(store.entries.first?.stateOfChargePercent, 70)
    }

    func testHistoryReplacesDuplicateTimestampWhenMissingChargeBecomesAvailable() {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: nil, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.timestamp, timestamp)
        XCTAssertEqual(store.entries.first?.stateOfChargePercent, 80)
    }

    func testHistoryKeepsMoreCompleteDuplicateTimestampWhenLaterSampleIsMissingData() {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: timestamp, chargePercent: nil, powerWatts: 10, temperatureCelsius: 31))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.timestamp, timestamp)
        XCTAssertEqual(store.entries.first?.stateOfChargePercent, 80)
    }

    func testHistoryRecordsNearbySampleWhenChargeAvailabilityImproves() {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: nil, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: timestamp.addingTimeInterval(60), chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        XCTAssertEqual(store.entries.map(\.timestamp), [timestamp, timestamp.addingTimeInterval(60)])
        XCTAssertNil(store.entries.first?.stateOfChargePercent)
        XCTAssertEqual(store.entries.last?.stateOfChargePercent, 80)
    }

    func testHistoryRecordsNearbySampleWhenChargeBecomesUnavailable() {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: timestamp.addingTimeInterval(60), chargePercent: nil, powerWatts: 10, temperatureCelsius: 31))

        XCTAssertEqual(store.entries.map(\.timestamp), [timestamp, timestamp.addingTimeInterval(60)])
        XCTAssertEqual(store.entries.first?.stateOfChargePercent, 80)
        XCTAssertNil(store.entries.last?.stateOfChargePercent)
    }

    func testHistoryRecordsNearbySampleWhenTemperatureChangesSignificantly() {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: timestamp.addingTimeInterval(60), chargePercent: 80, powerWatts: 10, temperatureCelsius: 33.1))

        XCTAssertEqual(store.entries.map(\.timestamp), [timestamp, timestamp.addingTimeInterval(60)])
        XCTAssertEqual(store.stats?.minimumTemperatureCelsius, 31)
        XCTAssertEqual(store.stats?.maximumTemperatureCelsius, 33.1)
    }

    func testHistoryDoesNotRecordNearbySampleForTinyTemperatureDrift() {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: timestamp.addingTimeInterval(60), chargePercent: 80, powerWatts: 10, temperatureCelsius: 32.9))

        XCTAssertEqual(store.entries.map(\.timestamp), [timestamp])
        XCTAssertEqual(store.stats?.minimumTemperatureCelsius, 31)
        XCTAssertEqual(store.stats?.maximumTemperatureCelsius, 31)
    }

    func testHistoryRecordsNearbySampleWhenCycleCountChanges() {
        let store = makeStore()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31, cycleCount: 120))
        store.record(makeSnapshot(timestamp: timestamp.addingTimeInterval(60), chargePercent: 80, powerWatts: 10, temperatureCelsius: 31, cycleCount: 121))

        XCTAssertEqual(store.entries.map(\.timestamp), [timestamp, timestamp.addingTimeInterval(60)])
        XCTAssertEqual(store.entries.map(\.cycleCount), [120, 121])
    }

    func testHistoryRecordsValidOlderSampleWhenNearestEntryIsFarEnoughAway() {
        let store = makeStore()
        let middleTimestamp = Date(timeIntervalSince1970: 1_300)
        let laterTimestamp = Date(timeIntervalSince1970: 1_600)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: laterTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: middleTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        XCTAssertEqual(store.entries.map(\.timestamp), [middleTimestamp, laterTimestamp])
    }

    func testHistoryIgnoresFutureDatedSamplesDuringRecording() {
        let store = makeStore()
        let now = Date()
        let validTimestamp = now.addingTimeInterval(-300)
        let futureTimestamp = now.addingTimeInterval(120)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: validTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.record(makeSnapshot(timestamp: futureTimestamp, chargePercent: 70, powerWatts: 14, temperatureCelsius: 32))

        XCTAssertEqual(store.entries.map(\.timestamp), [validTimestamp])
        XCTAssertEqual(store.stats?.latestTimestamp, validTimestamp)
    }

    func testHistoryCapsEntriesDuringRecording() {
        let store = makeStore()
        let firstTimestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        for offset in 0..<300 {
            store.record(makeSnapshot(
                timestamp: firstTimestamp.addingTimeInterval(Double(offset * 301)),
                chargePercent: Double(100 - (offset % 80)),
                powerWatts: Double(10 + (offset % 20)),
                temperatureCelsius: 30
            ))
        }

        XCTAssertEqual(store.entries.count, 288)
        XCTAssertEqual(store.entries.first?.timestamp, firstTimestamp.addingTimeInterval(Double(12 * 301)))
        XCTAssertEqual(store.entries.last?.timestamp, firstTimestamp.addingTimeInterval(Double(299 * 301)))
    }

    func testDisablingHistoryClearsLocalEntriesAndDisablesCSVExport() throws {
        var copiedStrings: [String] = []
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = BatteryHistoryStore(defaults: defaults, pasteboardCopy: { copiedStrings.append($0) })
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        XCTAssertTrue(store.copyCSV())

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: false, syncsToICloud: false))

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.summaryText, "No history recorded yet.")
        XCTAssertFalse(store.copyCSV())
        XCTAssertEqual(copiedStrings.count, 1)

        let storedString = try XCTUnwrap(defaults.string(forKey: "batteryHistoryEntries"))
        let storedEntries = try JSONDecoder().decode([BatteryHistoryEntry].self, from: Data(storedString.utf8))
        XCTAssertTrue(storedEntries.isEmpty)
    }

    func testDisabledHistoryPolicyClearsStoredEntriesLoadedFromPreviousRun() throws {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let encodedEntries = try XCTUnwrap(String(
            data: JSONEncoder().encode([
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
            ]),
            encoding: .utf8
        ))
        defaults.set(encodedEntries, forKey: "batteryHistoryEntries")
        let store = BatteryHistoryStore(defaults: defaults)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: false, syncsToICloud: false))

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.summaryText, "No history recorded yet.")

        let storedString = try XCTUnwrap(defaults.string(forKey: "batteryHistoryEntries"))
        let storedEntries = try JSONDecoder().decode([BatteryHistoryEntry].self, from: Data(storedString.utf8))
        XCTAssertTrue(storedEntries.isEmpty)
    }

    func testReapplyingDisabledHistoryPolicyDoesNotRewriteEmptyLocalHistory() {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = TrackingUserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("[]", forKey: "batteryHistoryEntries")
        let setCallCountAfterSeeding = defaults.setCallCount
        let store = BatteryHistoryStore(defaults: defaults)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: false, syncsToICloud: false))

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(defaults.setCallCount, setCallCountAfterSeeding)
    }

    func testReapplyingSameHistoryPolicyDoesNotSynchronizeAgain() {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        let synchronizeCountAfterEnabling = cloudStore.synchronizeCallCount
        let setStringCountAfterEnabling = cloudStore.setStringCallCount

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))

        XCTAssertEqual(cloudStore.synchronizeCallCount, synchronizeCountAfterEnabling)
        XCTAssertEqual(cloudStore.setStringCallCount, setStringCountAfterEnabling)
    }

    func testDisablingSyncedHistoryClearsCloudEntries() throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: false, syncsToICloud: false))

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries"), [])
    }

    func testDisablingSyncedHistoryClearsCloudEntriesWhenLocalHistoryIsAlreadyEmpty() throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        try cloudStore.setHistoryEntries([
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: timestamp,
                chargePercent: 80,
                powerWatts: 10,
                temperatureCelsius: 31
            ))
        ])

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: false, syncsToICloud: false))

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries"), [])
    }

    func testDisablingSyncedHistoryDoesNotRewriteAlreadyEmptyCloudHistory() throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        try cloudStore.setHistoryEntries([])

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.flushPendingWrites()
        let setStringCountAfterEmptyCloudSync = cloudStore.setStringCallCount
        let synchronizeCountAfterEmptyCloudSync = cloudStore.synchronizeCallCount

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: false, syncsToICloud: false))

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries"), [])
        XCTAssertEqual(cloudStore.setStringCallCount, setStringCountAfterEmptyCloudSync)
        XCTAssertEqual(cloudStore.synchronizeCallCount, synchronizeCountAfterEmptyCloudSync)
    }

    func testExternalCloudHistoryChangeMergesWhileSyncPolicyIsActive() async throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let localTimestamp = Date(timeIntervalSince1970: 1_000)
        let remoteTimestamp = Date(timeIntervalSince1970: 1_301)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        try cloudStore.setHistoryEntries([
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: remoteTimestamp,
                chargePercent: 74,
                powerWatts: 14,
                temperatureCelsius: 32
            ))
        ])
        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertEqual(store.entries.map(\.timestamp), [localTimestamp, remoteTimestamp])
        XCTAssertEqual(store.entries.last?.stateOfChargePercent, 74)
    }

    func testExternalCloudHistoryChangeDropsFutureDatedEntries() async throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let now = Date()
        let localTimestamp = now.addingTimeInterval(-600)
        let remoteTimestamp = now.addingTimeInterval(-300)
        let futureTimestamp = now.addingTimeInterval(120)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        try cloudStore.setHistoryEntries([
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: remoteTimestamp,
                chargePercent: 74,
                powerWatts: 14,
                temperatureCelsius: 32
            )),
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: futureTimestamp,
                chargePercent: 70,
                powerWatts: 16,
                temperatureCelsius: 33
            ))
        ])
        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertEqual(store.entries.map(\.timestamp), [localTimestamp, remoteTimestamp])
        XCTAssertEqual(store.stats?.latestTimestamp, remoteTimestamp)
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries")?.map(\.timestamp), [localTimestamp, remoteTimestamp])
    }

    func testExternalCloudHistoryChangeRepairsFutureDatedEntryWhenValidCloudHistoryAlreadyMatchesLocalHistory() async throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let now = Date()
        let localTimestamp = now.addingTimeInterval(-600)
        let futureTimestamp = now.addingTimeInterval(120)
        let localEntry = BatteryHistoryEntry(snapshot: makeSnapshot(
            timestamp: localTimestamp,
            chargePercent: 80,
            powerWatts: 10,
            temperatureCelsius: 31
        ))

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        try cloudStore.setHistoryEntries([
            localEntry,
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: futureTimestamp,
                chargePercent: 70,
                powerWatts: 16,
                temperatureCelsius: 33
            ))
        ])
        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertEqual(store.entries.map(\.timestamp), [localTimestamp])
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries")?.map(\.timestamp), [localTimestamp])
    }

    func testExternalCloudHistoryChangeWithOnlyFutureEntriesDoesNotClearLocalHistory() async throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let now = Date()
        let localTimestamp = now.addingTimeInterval(-600)
        let futureTimestamp = now.addingTimeInterval(120)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        try cloudStore.setHistoryEntries([
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: futureTimestamp,
                chargePercent: 70,
                powerWatts: 16,
                temperatureCelsius: 33
            ))
        ])
        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertEqual(store.entries.map(\.timestamp), [localTimestamp])
        XCTAssertEqual(store.summaryText, "1 sample synced with iCloud.")
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries")?.map(\.timestamp), [localTimestamp])
    }

    func testEnablingICloudSyncWithEmptyCloudKeepsLocalHistory() {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let localTimestamp = Date(timeIntervalSince1970: 1_000)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))

        XCTAssertEqual(store.entries.map(\.timestamp), [localTimestamp])
        XCTAssertEqual(store.summaryText, "1 sample synced with iCloud.")
    }

    func testExternalEmptyCloudHistoryChangeClearsLocalHistory() async throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let localTimestamp = Date(timeIntervalSince1970: 1_000)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        try cloudStore.setHistoryEntries([])
        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.summaryText, "No history recorded yet.")
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries"), [])
    }

    func testExternalRemovedCloudHistoryKeyClearsLocalHistory() async {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let localTimestamp = Date(timeIntervalSince1970: 1_000)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))

        cloudStore.removeHistoryEntries()
        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.summaryText, "No history recorded yet.")
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries"), [])
    }

    func testMalformedCloudHistoryChangeRepairsCloudFromLocalHistory() async {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let localTimestamp = Date(timeIntervalSince1970: 1_000)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        cloudStore.setRawString("not-json", forKey: "batteryHistoryEntries")

        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertEqual(store.entries.map(\.timestamp), [localTimestamp])
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries")?.map(\.timestamp), [localTimestamp])
    }

    func testMalformedCloudHistoryChangeRepairsCloudToEmptyHistoryWhenLocalIsEmpty() async {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        cloudStore.setRawString("not-json", forKey: "batteryHistoryEntries")

        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(cloudStore.decodedEntries(forKey: "batteryHistoryEntries"), [])
    }

    func testUnknownCloudHistoryChangeWithoutCloudKeyKeepsLocalHistory() async {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let localTimestamp = Date(timeIntervalSince1970: 1_000)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        cloudStore.removeHistoryEntries()

        cloudStore.sendChange(keys: [])
        await Task.yield()

        XCTAssertEqual(store.entries.map(\.timestamp), [localTimestamp])
    }

    func testExternalCloudHistoryChangesAreIgnoredAfterSyncPolicyTurnsOff() async throws {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let localTimestamp = Date(timeIntervalSince1970: 1_000)
        let remoteTimestamp = Date(timeIntervalSince1970: 1_301)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: localTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        try cloudStore.setHistoryEntries([
            BatteryHistoryEntry(snapshot: makeSnapshot(
                timestamp: remoteTimestamp,
                chargePercent: 74,
                powerWatts: 14,
                temperatureCelsius: 32
            ))
        ])
        cloudStore.sendChange(keys: ["batteryHistoryEntries"])
        await Task.yield()

        XCTAssertEqual(store.entries.map(\.timestamp), [localTimestamp])
        XCTAssertEqual(cloudStore.removeObserverCallCount, 1)
    }

    func testRecordingIdenticalSnapshotDoesNotRewriteHistory() {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let snapshot = makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            chargePercent: 80,
            powerWatts: 10,
            temperatureCelsius: 31
        )

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.record(snapshot)
        let setStringCountAfterFirstRecord = cloudStore.setStringCallCount

        store.record(snapshot)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(cloudStore.setStringCallCount, setStringCountAfterFirstRecord)
    }

    func testHistoryNormalizesPersistedEntriesOnLaunch() throws {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let earlierTimestamp = Date(timeIntervalSince1970: 1_000)
        let laterTimestamp = Date(timeIntervalSince1970: 1_600)
        let encodedEntries = try XCTUnwrap(String(
            data: JSONEncoder().encode([
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: laterTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31)),
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: earlierTimestamp, chargePercent: 90, powerWatts: 12, temperatureCelsius: 29)),
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: laterTimestamp, chargePercent: 70, powerWatts: 14, temperatureCelsius: 32))
            ]),
            encoding: .utf8
        ))
        defaults.set(encodedEntries, forKey: "batteryHistoryEntries")

        let store = BatteryHistoryStore(defaults: defaults)

        XCTAssertEqual(store.entries.map(\.timestamp), [earlierTimestamp, laterTimestamp])
        XCTAssertEqual(store.entries.last?.stateOfChargePercent, 70)
    }

    func testHistoryDropsFutureDatedPersistedEntriesOnLaunch() throws {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let now = Date()
        let validTimestamp = now.addingTimeInterval(-300)
        let futureTimestamp = now.addingTimeInterval(120)
        let encodedEntries = try XCTUnwrap(String(
            data: JSONEncoder().encode([
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: validTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31)),
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: futureTimestamp, chargePercent: 70, powerWatts: 14, temperatureCelsius: 32))
            ]),
            encoding: .utf8
        ))
        defaults.set(encodedEntries, forKey: "batteryHistoryEntries")

        let store = BatteryHistoryStore(defaults: defaults)

        XCTAssertEqual(store.entries.map(\.timestamp), [validTimestamp])
        XCTAssertEqual(store.stats?.latestTimestamp, validTimestamp)

        let rewrittenString = try XCTUnwrap(defaults.string(forKey: "batteryHistoryEntries"))
        let rewrittenEntries = try JSONDecoder().decode([BatteryHistoryEntry].self, from: Data(rewrittenString.utf8))
        XCTAssertEqual(rewrittenEntries.map(\.timestamp), [validTimestamp])
    }

    func testHistoryRewritesNormalizedPersistedEntriesOnLaunch() throws {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let earlierTimestamp = Date(timeIntervalSince1970: 1_000)
        let laterTimestamp = Date(timeIntervalSince1970: 1_600)
        let encodedEntries = try XCTUnwrap(String(
            data: JSONEncoder().encode([
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: laterTimestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31)),
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: earlierTimestamp, chargePercent: 90, powerWatts: 12, temperatureCelsius: 29)),
                BatteryHistoryEntry(snapshot: makeSnapshot(timestamp: laterTimestamp, chargePercent: 70, powerWatts: 14, temperatureCelsius: 32))
            ]),
            encoding: .utf8
        ))
        defaults.set(encodedEntries, forKey: "batteryHistoryEntries")

        _ = BatteryHistoryStore(defaults: defaults)

        let rewrittenString = try XCTUnwrap(defaults.string(forKey: "batteryHistoryEntries"))
        let rewrittenEntries = try JSONDecoder().decode([BatteryHistoryEntry].self, from: Data(rewrittenString.utf8))
        XCTAssertEqual(rewrittenEntries.map(\.timestamp), [earlierTimestamp, laterTimestamp])
        XCTAssertEqual(rewrittenEntries.last?.stateOfChargePercent, 70)
    }

    func testHistoryEntrySanitizesNonFiniteValues() {
        let entry = BatteryHistoryEntry(snapshot: makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            chargePercent: .nan,
            powerWatts: .infinity,
            temperatureCelsius: -.infinity
        ))

        XCTAssertNil(entry.stateOfChargePercent)
        XCTAssertNil(entry.activePowerWatts)
        XCTAssertNil(entry.temperatureCelsius)
    }

    func testHistoryEntrySanitizesOutOfRangeValues() {
        let entry = BatteryHistoryEntry(snapshot: makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            chargePercent: -4,
            powerWatts: .greatestFiniteMagnitude,
            temperatureCelsius: 180,
            healthPercent: 150,
            displayedTimeMinutes: Int.max,
            cycleCount: Int.max
        ))

        XCTAssertNil(entry.healthPercent)
        XCTAssertNil(entry.stateOfChargePercent)
        XCTAssertNil(entry.displayedTimeMinutes)
        XCTAssertNil(entry.activePowerWatts)
        XCTAssertNil(entry.temperatureCelsius)
        XCTAssertNil(entry.cycleCount)
    }

    func testHistoryNormalizesOutOfRangePersistedEntriesOnLaunch() throws {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let encodedEntries = try XCTUnwrap(String(
            data: JSONEncoder().encode([
                LegacyHistoryEntry(
                    timestamp: timestamp,
                    powerState: "bogus",
                    healthPercent: 150,
                    stateOfChargePercent: 105,
                    displayedTimeMinutes: 1_441,
                    activePowerWatts: .greatestFiniteMagnitude,
                    temperatureCelsius: 180,
                    cycleCount: Int.max
                )
            ]),
            encoding: .utf8
        ))
        defaults.set(encodedEntries, forKey: "batteryHistoryEntries")

        let store = BatteryHistoryStore(defaults: defaults)

        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.powerState, BatteryPowerState.unknown.rawValue)
        XCTAssertNil(entry.healthPercent)
        XCTAssertEqual(entry.stateOfChargePercent, 100)
        XCTAssertNil(entry.displayedTimeMinutes)
        XCTAssertNil(entry.activePowerWatts)
        XCTAssertNil(entry.temperatureCelsius)
        XCTAssertNil(entry.cycleCount)

        let rewrittenString = try XCTUnwrap(defaults.string(forKey: "batteryHistoryEntries"))
        XCTAssertNotEqual(rewrittenString, encodedEntries)
    }

    func testHistoryDropsStaleTimeAndKeepsLivePowerForPluggedInPersistedEntriesOnLaunch() throws {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let idleTimestamp = Date(timeIntervalSince1970: 1_000)
        let activeTimestamp = Date(timeIntervalSince1970: 1_301)
        let encodedEntries = try XCTUnwrap(String(
            data: JSONEncoder().encode([
                LegacyHistoryEntry(
                    timestamp: idleTimestamp,
                    powerState: BatteryPowerState.connectedNotCharging.rawValue,
                    healthPercent: 83,
                    stateOfChargePercent: 85,
                    displayedTimeMinutes: 45,
                    activePowerWatts: 14,
                    temperatureCelsius: 32,
                    cycleCount: 120
                ),
                LegacyHistoryEntry(
                    timestamp: activeTimestamp,
                    powerState: BatteryPowerState.onBattery.rawValue,
                    healthPercent: 83,
                    stateOfChargePercent: 84,
                    displayedTimeMinutes: 44,
                    activePowerWatts: 13,
                    temperatureCelsius: 32,
                    cycleCount: 120
                )
            ]),
            encoding: .utf8
        ))
        defaults.set(encodedEntries, forKey: "batteryHistoryEntries")

        let store = BatteryHistoryStore(defaults: defaults)

        let idleEntry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(idleEntry.powerState, BatteryPowerState.connectedNotCharging.rawValue)
        XCTAssertNil(idleEntry.displayedTimeMinutes)
        XCTAssertEqual(idleEntry.activePowerWatts, 14)

        let activeEntry = try XCTUnwrap(store.entries.last)
        XCTAssertEqual(activeEntry.powerState, BatteryPowerState.onBattery.rawValue)
        XCTAssertEqual(activeEntry.displayedTimeMinutes, 44)
        XCTAssertEqual(activeEntry.activePowerWatts, 13)

        let rewrittenString = try XCTUnwrap(defaults.string(forKey: "batteryHistoryEntries"))
        XCTAssertNotEqual(rewrittenString, encodedEntries)
    }

    func testCopyCSVDoesNothingWhenHistoryIsEmpty() {
        var copiedStrings: [String] = []
        let store = makeStore(pasteboardCopy: { copiedStrings.append($0) })

        XCTAssertFalse(store.copyCSV())
        XCTAssertTrue(copiedStrings.isEmpty)
    }

    func testCopyCSVCopiesRecordedHistoryRows() throws {
        var copiedStrings: [String] = []
        let store = makeStore(pasteboardCopy: { copiedStrings.append($0) })
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))

        store.record(makeSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            chargePercent: 88,
            powerWatts: 10,
            temperatureCelsius: 29.5
        ))

        XCTAssertTrue(store.copyCSV())
        let csv = try XCTUnwrap(copiedStrings.last)
        XCTAssertEqual(copiedStrings.count, 1)
        XCTAssertEqual(
            csv,
            """
            timestamp,power_state,health_percent,charge_percent,time_minutes,active_power_watts,temperature_celsius,cycle_count
            1970-01-01T00:16:40.000Z,onBattery,83.00,88.00,150,10.00,29.50,120
            """
        )
    }

    func testCSVValuesUseStableDecimalSeparatorAndRejectNonFiniteValues() {
        XCTAssertEqual(BatteryHistoryStore.csvValue(18.333), "18.33")
        XCTAssertEqual(BatteryHistoryStore.csvValue(18.335), "18.34")
        XCTAssertEqual(BatteryHistoryStore.csvValue(.nan), "")
        XCTAssertEqual(BatteryHistoryStore.csvValue(.infinity), "")
    }

    func testDisablingICloudSyncCancelsPendingCloudSynchronize() async {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore, cloudSynchronizeDelay: .milliseconds(10))
        let timestamp = Date(timeIntervalSince1970: 1_000)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        let synchronizeCountAfterEnabling = cloudStore.synchronizeCallCount
        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(cloudStore.synchronizeCallCount, synchronizeCountAfterEnabling)
    }

    func testDisabledHistoryPolicyCannotKeepCloudSyncActive() {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore)
        let timestamp = Date(timeIntervalSince1970: 1_000)

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: false, syncsToICloud: true))
        store.record(makeSnapshot(timestamp: timestamp, chargePercent: 80, powerWatts: 10, temperatureCelsius: 31))
        store.flushPendingWrites()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(cloudStore.string(forKey: "batteryHistoryEntries"))
        XCTAssertEqual(cloudStore.synchronizeCallCount, 0)
    }

    func testDisablingICloudSyncCancelsFlushScheduledByStaleSynchronizeTask() async {
        let cloudStore = FakeBatteryHistoryCloudStore()
        let store = makeStore(cloudStore: cloudStore, cloudSynchronizeDelay: .milliseconds(20))
        let timestamp = Date(timeIntervalSince1970: 1_000)
        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: true))
        store.flushPendingWrites()
        let synchronizeCountBeforeRecording = cloudStore.synchronizeCallCount
        var scheduledSecondFlush = false

        cloudStore.onSynchronize = {
            guard scheduledSecondFlush == false else {
                return
            }

            scheduledSecondFlush = true
            store.record(self.makeSnapshot(
                timestamp: timestamp.addingTimeInterval(301),
                chargePercent: 79,
                powerWatts: 11,
                temperatureCelsius: 31
            ))
        }

        store.record(makeSnapshot(
            timestamp: timestamp,
            chargePercent: 80,
            powerWatts: 10,
            temperatureCelsius: 31
        ))

        while scheduledSecondFlush == false {
            try? await Task.sleep(for: .milliseconds(1))
        }
        await Task.yield()

        store.updatePolicy(BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(cloudStore.synchronizeCallCount, synchronizeCountBeforeRecording + 1)
    }

    private func makeStore(
        cloudStore: (any BatteryHistoryCloudStoring)? = nil,
        pasteboardCopy: @escaping @MainActor (String) -> Void = { _ in },
        cloudSynchronizeDelay: Duration = .milliseconds(750)
    ) -> BatteryHistoryStore {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return BatteryHistoryStore(
            defaults: defaults,
            cloudStore: cloudStore,
            pasteboardCopy: pasteboardCopy,
            cloudSynchronizeDelay: cloudSynchronizeDelay
        )
    }

    private func makeSnapshot(
        timestamp: Date,
        chargePercent: Double?,
        powerWatts: Double,
        temperatureCelsius: Double,
        healthPercent: Double = 83,
        displayedTimeMinutes: Int? = 150,
        cycleCount: Int? = 120
    ) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: timestamp,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: healthPercent,
            stateOfChargePercent: chargePercent,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: powerWatts,
            rateBasedTimeRemainingMinutes: displayedTimeMinutes,
            systemTimeRemainingMinutes: displayedTimeMinutes,
            timeToFullMinutes: nil,
            cycleCount: cycleCount,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: temperatureCelsius,
            adapterMaxWatts: 70,
            notes: []
        )
    }
}

private struct LegacyHistoryEntry: Codable {
    let timestamp: Date
    let powerState: String
    let healthPercent: Double?
    let stateOfChargePercent: Double?
    let displayedTimeMinutes: Int?
    let activePowerWatts: Double?
    let temperatureCelsius: Double?
    let cycleCount: Int?
}

@MainActor
private final class FakeBatteryHistoryCloudStore: BatteryHistoryCloudStoring {
    private var values: [String: String] = [:]
    private(set) var synchronizeCallCount = 0
    private(set) var setStringCallCount = 0
    private(set) var removeObserverCallCount = 0
    var onSynchronize: (() -> Void)?
    private var changeHandler: (@Sendable ([String]) -> Void)?

    func synchronize() -> Bool {
        synchronizeCallCount += 1
        onSynchronize?()
        return true
    }

    func string(forKey key: String) -> String? {
        values[key]
    }

    func setString(_ value: String, forKey key: String) {
        setStringCallCount += 1
        values[key] = value
    }

    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol {
        changeHandler = handler
        return NSObject()
    }

    func removeObserver(_ token: NSObjectProtocol) {
        removeObserverCallCount += 1
        changeHandler = nil
    }

    func setHistoryEntries(_ entries: [BatteryHistoryEntry], forKey key: String = "batteryHistoryEntries") throws {
        let data = try JSONEncoder().encode(entries)
        values[key] = String(data: data, encoding: .utf8)
    }

    func removeHistoryEntries(forKey key: String = "batteryHistoryEntries") {
        values.removeValue(forKey: key)
    }

    func setRawString(_ value: String, forKey key: String) {
        values[key] = value
    }

    func decodedEntries(forKey key: String) -> [BatteryHistoryEntry]? {
        guard let string = values[key],
              let data = string.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode([BatteryHistoryEntry].self, from: data)
    }

    func sendChange(keys: [String]) {
        changeHandler?(keys)
    }
}

private final class TrackingUserDefaults: UserDefaults {
    private(set) var setCallCount = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        setCallCount += 1
        super.set(value, forKey: defaultName)
    }
}
