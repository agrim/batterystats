import XCTest
@testable import BatteryStats

@MainActor
final class BatteryHistoryStoreTests: XCTestCase {
    func testStatsAreNilWhenNoHistoryHasBeenRecorded() {
        let store = makeStore()

        XCTAssertNil(store.stats)
        XCTAssertEqual(store.summaryText, "No history recorded yet.")
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

    private func makeStore() -> BatteryHistoryStore {
        let suiteName = "BatteryHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return BatteryHistoryStore(defaults: defaults)
    }

    private func makeSnapshot(
        timestamp: Date,
        chargePercent: Double,
        powerWatts: Double,
        temperatureCelsius: Double
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
            healthPercent: 83,
            stateOfChargePercent: chargePercent,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: powerWatts,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: temperatureCelsius,
            adapterMaxWatts: 70,
            notes: []
        )
    }
}
