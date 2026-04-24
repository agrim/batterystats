import XCTest
@testable import BatteryStats

final class RefreshPolicyTests: XCTestCase {
    func testFixedRefreshCadenceUsesSelectedInterval() {
        let policy = BatteryRefreshPolicy(cadence: .fiveMinutes, energyChangeSensitivity: .balanced)

        XCTAssertEqual(policy.refreshInterval(for: .previewDischarging), 300)
        XCTAssertTrue(policy.usesEnergyChangeProbe)
    }

    func testShortFixedRefreshCadenceDoesNotNeedEnergyProbe() {
        let policy = BatteryRefreshPolicy(cadence: .fifteenSeconds, energyChangeSensitivity: .balanced)

        XCTAssertEqual(policy.refreshInterval(for: .previewDischarging), 15)
        XCTAssertFalse(policy.usesEnergyChangeProbe)
    }

    func testDynamicRefreshCadenceRespondsToPowerState() {
        let policy = BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced)

        XCTAssertEqual(policy.refreshInterval(for: .previewDischarging), 60)
        XCTAssertEqual(policy.refreshInterval(for: makeSnapshot(powerState: .fullOnAC, chargePercent: 100)), 300)
        XCTAssertEqual(policy.refreshInterval(for: makeSnapshot(powerState: .onBattery, chargePercent: 12)), 30)
    }

    func testEnergyChangeThresholdDetectsLargeRelativeChanges() {
        XCTAssertTrue(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 10, current: 14, thresholdPercent: 35))
        XCTAssertTrue(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 10, current: 6, thresholdPercent: 35))
        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 10, current: 12, thresholdPercent: 35))
        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: nil, current: 12, thresholdPercent: 35))
    }

    private func makeSnapshot(powerState: BatteryPowerState, chargePercent: Double) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: .now,
            powerState: powerState,
            isCharging: powerState == .charging,
            isExternalPowerConnected: powerState != .onBattery,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: chargePercent,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: powerState == .charging ? 1_200 : -1_200,
            dischargeRateMilliamps: powerState == .onBattery ? 1_200 : nil,
            chargeRateWatts: powerState == .charging ? 14.4 : nil,
            dischargeRateWatts: powerState == .onBattery ? 14.4 : nil,
            rateBasedTimeRemainingMinutes: powerState == .onBattery ? 150 : nil,
            systemTimeRemainingMinutes: powerState == .onBattery ? 145 : nil,
            timeToFullMinutes: powerState == .charging ? 50 : nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )
    }
}
