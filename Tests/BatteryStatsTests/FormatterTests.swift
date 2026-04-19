import XCTest
@testable import BatteryStats

final class FormatterTests: XCTestCase {
    func testFormatsMilliampHours() {
        XCTAssertEqual(BatteryFormatting.milliampHours(5_338), "5,338 mAh")
    }

    func testFormatsCompactCapacityPair() {
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 4_912, maximum: 5_338),
            "4,912 / 5,338 mAh"
        )
    }

    func testFormatsPercentWithOneDecimal() {
        XCTAssertEqual(BatteryFormatting.percent(81.38, decimals: 1), "81.4%")
    }

    func testFormatsCompactDuration() {
        XCTAssertEqual(BatteryFormatting.compactDuration(minutes: 125), "2h 5m")
        XCTAssertEqual(BatteryFormatting.compactDuration(minutes: 45), "45m")
    }

    func testFormatsFahrenheitTemperature() {
        XCTAssertEqual(BatteryFormatting.temperature(34.2, unitPreference: .fahrenheit), "93.6 °F")
    }

    func testFormatsAge() {
        let formattedAge = BatteryFormatting.age(DateComponents(year: 2, month: 3))

        XCTAssertTrue(formattedAge.contains("2"))
        XCTAssertTrue(formattedAge.contains("3"))
    }

    func testSnapshotUsesChargeForStatusAndMenuBarIcon() {
        let lowPowerSnapshot = makeSnapshot(stateOfChargePercent: 15, powerState: .onBattery)
        XCTAssertEqual(lowPowerSnapshot.statusDisplayTitle, "On Battery Low Power")
        XCTAssertEqual(lowPowerSnapshot.batterySymbolName, "battery.25")

        let halfChargedSnapshot = makeSnapshot(stateOfChargePercent: 55, powerState: .charging)
        XCTAssertEqual(halfChargedSnapshot.statusDisplayTitle, "Charging")
        XCTAssertEqual(halfChargedSnapshot.batterySymbolName, "battery.50")
    }

    func testSnapshotUsesRequestedHealthAndChargeThresholdBands() {
        let redSnapshot = makeSnapshot(stateOfChargePercent: 8, healthPercent: 79.5, powerState: .onBattery)
        XCTAssertEqual(redSnapshot.healthTone, .red)
        XCTAssertEqual(redSnapshot.chargeTone, .red)

        let yellowSnapshot = makeSnapshot(stateOfChargePercent: 15, healthPercent: 82, powerState: .onBattery)
        XCTAssertEqual(yellowSnapshot.healthTone, .yellow)
        XCTAssertEqual(yellowSnapshot.chargeTone, .yellow)

        let greenYellowSnapshot = makeSnapshot(stateOfChargePercent: 35, healthPercent: 88, powerState: .onBattery)
        XCTAssertEqual(greenYellowSnapshot.healthTone, .greenYellow)
        XCTAssertEqual(greenYellowSnapshot.chargeTone, .greenYellow)

        let midGreenSnapshot = makeSnapshot(stateOfChargePercent: 55, healthPercent: 93, powerState: .onBattery)
        XCTAssertEqual(midGreenSnapshot.healthTone, .midGreen)
        XCTAssertEqual(midGreenSnapshot.chargeTone, .midGreen)

        let greenSnapshot = makeSnapshot(stateOfChargePercent: 76, healthPercent: 97, powerState: .onBattery)
        XCTAssertEqual(greenSnapshot.healthTone, .green)
        XCTAssertEqual(greenSnapshot.chargeTone, .green)
    }

    private func makeSnapshot(stateOfChargePercent: Double, healthPercent: Double = 83.3, powerState: BatteryPowerState) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: .now,
            powerState: powerState,
            isCharging: powerState == .charging,
            isExternalPowerConnected: powerState != .onBattery,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78.0,
            healthPercent: healthPercent,
            stateOfChargePercent: stateOfChargePercent,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: powerState == .charging ? 1_200 : -1_200,
            dischargeRateMilliamps: powerState == .onBattery ? 1_200 : nil,
            chargeRateWatts: powerState == .charging ? 18.0 : nil,
            dischargeRateWatts: powerState == .onBattery ? 14.0 : nil,
            rateBasedTimeRemainingMinutes: powerState == .onBattery ? 150 : nil,
            systemTimeRemainingMinutes: powerState == .onBattery ? 145 : nil,
            timeToFullMinutes: powerState == .charging ? 50 : nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )
    }
}
