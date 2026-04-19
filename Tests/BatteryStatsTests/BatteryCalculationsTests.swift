import XCTest
@testable import BatteryStats

final class BatteryCalculationsTests: XCTestCase {
    func testHealthPercentCalculation() throws {
        let percent = try XCTUnwrap(BatteryCalculations.healthPercent(
            fullChargeCapacityMilliampHours: 5_338,
            designCapacityMilliampHours: 6_559
        ))

        XCTAssertEqual(percent, 81.38435737155054, accuracy: 0.0001)
    }

    func testTimeRemainingCalculation() {
        let minutes = BatteryCalculations.timeRemainingMinutes(
            currentChargeMilliampHours: 3_000,
            dischargeRateMilliamps: 1_000
        )

        XCTAssertEqual(minutes, 180)
    }

    func testWattHourCalculation() throws {
        let wattHours = try XCTUnwrap(BatteryCalculations.wattHours(milliampHours: 5_338, voltageMillivolts: 12_780))

        XCTAssertEqual(wattHours, 68.21964, accuracy: 0.00001)
    }

    func testTemperatureConversionDefaultsToHundredthsCelsius() throws {
        let temperature = try XCTUnwrap(BatteryCalculations.temperatureCelsius(fromRaw: 3_420))

        XCTAssertEqual(temperature, 34.2, accuracy: 0.0001)
    }

    func testSmoothedDischargeRateUsesRecentSamples() {
        let smoothedRate = BatteryCalculations.smoothedDischargeRate([1_200, 1_100, 1_050, 980], fallback: nil)

        XCTAssertEqual(smoothedRate, 1_083)
    }

    func testEstimatedTimeToFullUsesChargeTaper() throws {
        let estimated = try XCTUnwrap(BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: 4_031,
            fullChargeCapacityMilliampHours: 5_338,
            chargeCurrentMilliamps: 1_721,
            reportedTimeToFullMinutes: nil
        ))

        XCTAssertGreaterThan(estimated, 45)
        XCTAssertLessThan(estimated, 90)
    }

    func testEstimatedTimeToFullFallsBackToReportedValue() {
        let estimated = BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: nil,
            fullChargeCapacityMilliampHours: 5_338,
            chargeCurrentMilliamps: 1_721,
            reportedTimeToFullMinutes: 52
        )

        XCTAssertEqual(estimated, 52)
    }
}
