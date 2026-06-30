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

    func testDefaultMonitoringDemandDoesNotRequestEnergyProbe() {
        XCTAssertFalse(BatteryMonitoringDemand().needsEnergyChangeAwareness)
        XCTAssertFalse(BatteryMonitoringDemand().needsLightningRefresh)
    }

    func testMonitoringDemandCombinesLightningRefresh() {
        let backgroundDemand = BatteryMonitoringDemand(needsEnergyChangeAwareness: true)
        let lightningDemand = BatteryMonitoringDemand(needsLightningRefresh: true)

        XCTAssertEqual(
            backgroundDemand.combined(with: lightningDemand),
            BatteryMonitoringDemand(needsEnergyChangeAwareness: true, needsLightningRefresh: true)
        )
    }

    func testLightningRefreshOverridesSelectedCadence() {
        let policy = BatteryRefreshPolicy(cadence: .fiveMinutes, energyChangeSensitivity: .balanced)

        XCTAssertEqual(
            policy.refreshInterval(
                for: .previewDischarging,
                demand: BatteryMonitoringDemand(needsLightningRefresh: true)
            ),
            policy.lightningRefreshInterval
        )
    }

    func testDynamicRefreshCadenceRespondsToPowerState() {
        let policy = BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced)

        XCTAssertEqual(policy.refreshInterval(for: .previewDischarging), 60)
        XCTAssertEqual(policy.refreshInterval(for: makeSnapshot(powerState: .fullOnAC, chargePercent: 100)), 300)
        XCTAssertEqual(policy.refreshInterval(for: makeSnapshot(powerState: .onBattery, chargePercent: 12)), 30)
        XCTAssertEqual(policy.refreshInterval(for: makeSnapshot(powerState: .connectedDischarging, chargePercent: 12)), 30)
    }

    func testDynamicRefreshCadenceIgnoresInvalidNegativeChargePercent() {
        let policy = BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced)

        XCTAssertEqual(policy.refreshInterval(for: makeSnapshot(powerState: .onBattery, chargePercent: -1)), 60)
    }

    func testEnergyChangeThresholdDetectsLargeRelativeChanges() {
        XCTAssertTrue(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 10, current: 14, thresholdPercent: 35))
        XCTAssertTrue(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 10, current: 6, thresholdPercent: 35))
        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 10, current: 12, thresholdPercent: 35))
    }

    func testEnergyChangeThresholdDetectsAvailabilityTransitions() {
        XCTAssertTrue(BatteryRefreshPolicy.isSignificantEnergyChange(previous: nil, current: 12, thresholdPercent: 35))
        XCTAssertTrue(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 12, current: nil, thresholdPercent: 35))
        XCTAssertTrue(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 0, current: 12, thresholdPercent: 35))
        XCTAssertTrue(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 12, current: 0, thresholdPercent: 35))
        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: nil, current: nil, thresholdPercent: 35))
        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: .nan, current: .infinity, thresholdPercent: 35))
    }

    private func makeSnapshot(powerState: BatteryPowerState, chargePercent: Double) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: .now,
            powerState: powerState,
            isCharging: powerState == .charging,
            isExternalPowerConnected: powerState != .onBattery && powerState != .unknown,
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
            dischargeRateMilliamps: (powerState == .onBattery || powerState == .connectedDischarging) ? 1_200 : nil,
            chargeRateWatts: powerState == .charging ? 14.4 : nil,
            dischargeRateWatts: (powerState == .onBattery || powerState == .connectedDischarging) ? 14.4 : nil,
            rateBasedTimeRemainingMinutes: (powerState == .onBattery || powerState == .connectedDischarging) ? 150 : nil,
            systemTimeRemainingMinutes: (powerState == .onBattery || powerState == .connectedDischarging) ? 145 : nil,
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
