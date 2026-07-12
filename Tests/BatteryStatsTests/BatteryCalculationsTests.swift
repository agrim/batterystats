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

    func testHealthPercentClampsSmallOverDesignCapacity() throws {
        let percent = try XCTUnwrap(BatteryCalculations.healthPercent(
            fullChargeCapacityMilliampHours: 4_641,
            designCapacityMilliampHours: 4_629
        ))

        XCTAssertEqual(percent, 100, accuracy: 0.0001)
    }

    func testHealthPercentRejectsImpossibleCapacityRatio() {
        XCTAssertNil(BatteryCalculations.healthPercent(
            fullChargeCapacityMilliampHours: 15_000,
            designCapacityMilliampHours: 4_500
        ))
        XCTAssertNil(BatteryCalculations.healthPercent(
            fullChargeCapacityMilliampHours: -1,
            designCapacityMilliampHours: 4_500
        ))
    }

    func testStateOfChargeUsesSmartCapacityWhenConsistentWithPublicPercent() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 4_912,
            fullChargeCapacityMilliampHours: 5_338,
            publicPercentage: 92
        ))

        XCTAssertEqual(percent, 92, accuracy: 0.1)
    }

    func testStateOfChargeFallsBackToPublicPercentWhenSmartCapacityIsTransientlyWrong() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 5_338,
            publicPercentage: 92
        ))

        XCTAssertEqual(percent, 92, accuracy: 0.001)
    }

    func testStateOfChargeUsesStablePublicPercentWhenRawCapacityDriftsFromSystemPercent() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 4_220,
            fullChargeCapacityMilliampHours: 4_575,
            publicPercentage: 97
        ))

        XCTAssertEqual(percent, 97, accuracy: 0.001)
    }

    func testStateOfChargePrefersSmartCapacityWhenPublicPercentIsTransientlyEmpty() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 0
        ))

        XCTAssertEqual(percent, 80, accuracy: 0.001)
    }

    func testStateOfChargePrefersSmartCapacityWhenPublicPercentIsTransientlyLow() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 6
        ))

        XCTAssertEqual(percent, 80, accuracy: 0.001)
    }

    func testStateOfChargePrefersSmartFullCapacityWhenPublicPercentIsTransientlyEmpty() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 5_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 0
        ))

        XCTAssertEqual(percent, 100, accuracy: 0.001)
    }

    func testStateOfChargePrefersSmartCapacityWhenPublicPercentIsTransientlyFull() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 100
        ))

        XCTAssertEqual(percent, 60, accuracy: 0.001)
    }

    func testStateOfChargeUsesFullPublicPercentWhenSmartCapacityIsTransientlyEmpty() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 100
        ))

        XCTAssertEqual(percent, 100, accuracy: 0.001)
    }

    func testStateOfChargeRejectsImpossibleCalculatedPercent() throws {
        let percent = try XCTUnwrap(BatteryCalculations.stateOfChargePercent(
            currentChargeMilliampHours: 6_500,
            fullChargeCapacityMilliampHours: 5_338,
            publicPercentage: 99
        ))

        XCTAssertEqual(percent, 99, accuracy: 0.001)
    }

    func testReconciledCurrentChargeUsesPublicPercentWhenSmartCurrentIsTransientlyWrong() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 92
        )

        XCTAssertEqual(currentCharge, 4_600)
    }

    func testReconciledCurrentChargeUsesStablePublicPercentWhenRawCapacityDriftsFromSystemPercent() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 4_220,
            fullChargeCapacityMilliampHours: 4_575,
            publicPercentage: 97
        )

        XCTAssertEqual(currentCharge, 4_438)
    }

    func testReconciledCurrentChargeKeepsSmartCurrentWhenPublicPercentIsTransientlyEmpty() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 0
        )

        XCTAssertEqual(currentCharge, 4_000)
    }

    func testReconciledCurrentChargeKeepsSmartCurrentWhenPublicPercentIsTransientlyLow() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 6
        )

        XCTAssertEqual(currentCharge, 4_000)
    }

    func testReconciledCurrentChargeKeepsSmartFullCurrentWhenPublicPercentIsTransientlyEmpty() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 5_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 0
        )

        XCTAssertEqual(currentCharge, 5_000)
    }

    func testReconciledCurrentChargeKeepsSmartCurrentWhenPublicPercentIsTransientlyFull() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 100
        )

        XCTAssertEqual(currentCharge, 3_000)
    }

    func testReconciledCurrentChargeUsesFullPublicPercentWhenSmartCurrentIsTransientlyEmpty() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 100
        )

        XCTAssertEqual(currentCharge, 5_000)
    }

    func testReconciledCurrentChargeKeepsSmartCurrentWhenItMatchesPublicPercent() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 4_550,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 92
        )

        XCTAssertEqual(currentCharge, 4_550)
    }

    func testReconciledCurrentChargeDerivesCurrentWhenSmartCurrentIsMissing() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: nil,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: 92
        )

        XCTAssertEqual(currentCharge, 4_600)
    }

    func testReconciledCurrentChargeKeepsPlausibleSmartCurrentWhenPublicPercentIsMissing() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: nil
        )

        XCTAssertEqual(currentCharge, 4_000)
    }

    func testReconciledCurrentChargeRejectsImpossibleSmartCurrentWhenPublicPercentIsMissing() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 6_000,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: nil
        )

        XCTAssertNil(currentCharge)
    }

    func testReconciledCurrentChargeClampsSmallSmartOverfullValue() {
        let currentCharge = BatteryCalculations.reconciledCurrentChargeMilliampHours(
            smartCurrentChargeMilliampHours: 5_050,
            fullChargeCapacityMilliampHours: 5_000,
            publicPercentage: nil
        )

        XCTAssertEqual(currentCharge, 5_000)
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

    func testWattHourCalculationRejectsImpossibleInputs() {
        XCTAssertNil(BatteryCalculations.wattHours(milliampHours: -1, voltageMillivolts: 12_780))
        XCTAssertNil(BatteryCalculations.wattHours(milliampHours: 5_338, voltageMillivolts: -12_780))
        XCTAssertNil(BatteryCalculations.wattHours(milliampHours: 5_338, voltageMillivolts: 250_000))
        XCTAssertNil(BatteryCalculations.wattHours(milliampHours: Int.max, voltageMillivolts: 12_780))
    }

    func testCurrentAndWattCalculationsRejectExtremeSentinelValues() {
        XCTAssertNil(BatteryCalculations.dischargeRateMilliamps(from: .min))
        XCTAssertNil(BatteryCalculations.dischargeRateWatts(voltageMillivolts: 12_780, signedCurrentMilliamps: .min))
        XCTAssertNil(BatteryCalculations.chargeRateMilliamps(from: .max))
        XCTAssertNil(BatteryCalculations.chargeRateWatts(voltageMillivolts: 12_780, signedCurrentMilliamps: .max))
    }

    func testDischargeCalculationsIgnoreTinyNegativeCurrentNoise() {
        XCTAssertNil(BatteryCalculations.dischargeRateMilliamps(from: -1))
        XCTAssertNil(BatteryCalculations.dischargeRateWatts(voltageMillivolts: 12_780, signedCurrentMilliamps: -1))
    }

    func testChargeCalculationsIgnoreTinyPositiveCurrentNoise() {
        XCTAssertNil(BatteryCalculations.chargeRateMilliamps(from: 1))
        XCTAssertNil(BatteryCalculations.chargeRateWatts(voltageMillivolts: 12_780, signedCurrentMilliamps: 1))
    }

    func testPlausibleDischargeRateRejectsInvalidMagnitudes() {
        XCTAssertEqual(BatteryCalculations.plausibleDischargeRateMilliamps(41), 41)
        XCTAssertNil(BatteryCalculations.plausibleDischargeRateMilliamps(40))
        XCTAssertNil(BatteryCalculations.plausibleDischargeRateMilliamps(-1))
        XCTAssertNil(BatteryCalculations.plausibleDischargeRateMilliamps(Int.max))
    }

    func testPlausiblePhysicalMetricsRejectAbsurdPositiveValues() {
        XCTAssertEqual(BatteryCalculations.plausibleCapacityMilliampHours(5_000), 5_000)
        XCTAssertNil(BatteryCalculations.plausibleCapacityMilliampHours(Int.max))
        XCTAssertEqual(BatteryCalculations.plausibleVoltageMillivolts(12_000), 12_000)
        XCTAssertNil(BatteryCalculations.plausibleVoltageMillivolts(250_000))
        XCTAssertEqual(BatteryCalculations.plausibleWattHours(65.0), 65.0)
        XCTAssertNil(BatteryCalculations.plausibleWattHours(.greatestFiniteMagnitude))
        XCTAssertNil(BatteryCalculations.plausibleWatts(0))
        XCTAssertNil(BatteryCalculations.plausibleWatts(0.09))
        XCTAssertEqual(BatteryCalculations.plausibleWatts(0.1), 0.1)
        XCTAssertEqual(BatteryCalculations.plausibleWatts(96.0), 96.0)
        XCTAssertEqual(BatteryCalculations.plausibleWatts(1_000.0), 1_000.0)
        XCTAssertNil(BatteryCalculations.plausibleWatts(1_000.1))
        XCTAssertNil(BatteryCalculations.plausibleWatts(.greatestFiniteMagnitude))
        XCTAssertEqual(BatteryCalculations.plausibleInputPowerWatts(80.5, adapterMaxWatts: 70), 80.5)
        XCTAssertNil(BatteryCalculations.plausibleInputPowerWatts(100, adapterMaxWatts: 70))
        XCTAssertEqual(BatteryCalculations.plausibleInputPowerWatts(100, adapterMaxWatts: nil), 100)
        XCTAssertEqual(BatteryCalculations.displayableInputPowerWatts(39.8, adapterMaxWatts: nil), 39.8)
        XCTAssertNil(BatteryCalculations.displayableInputPowerWatts(100, adapterMaxWatts: nil))
        XCTAssertNil(BatteryCalculations.displayableInputPowerWatts(100, adapterMaxWatts: 70))
        XCTAssertNil(BatteryCalculations.displayableInputPowerWatts(100, adapterMaxWatts: 100))
        XCTAssertNil(BatteryCalculations.displayableInputPowerWatts(99, adapterMaxWatts: 100))
        XCTAssertEqual(BatteryCalculations.displayableInputPowerWatts(97.9, adapterMaxWatts: 100), 97.9)
        XCTAssertNil(BatteryCalculations.displayableCounterBackedInputPowerWatts(100, adapterMaxWatts: 100))
        XCTAssertNil(BatteryCalculations.displayableCounterBackedInputPowerWatts(99.95, adapterMaxWatts: 100))
        XCTAssertNil(BatteryCalculations.displayableCounterBackedInputPowerWatts(99.8, adapterMaxWatts: 100))
        XCTAssertNil(BatteryCalculations.displayableCounterBackedInputPowerWatts(99.4, adapterMaxWatts: 100))
        XCTAssertNil(BatteryCalculations.displayableCounterBackedInputPowerWatts(95.0, adapterMaxWatts: 100))
        XCTAssertEqual(BatteryCalculations.displayableCounterBackedInputPowerWatts(94.9, adapterMaxWatts: 100), 94.9)
        XCTAssertEqual(BatteryCalculations.displayableCounterBackedInputPowerWatts(69.42, adapterMaxWatts: 70), 69.42)
        XCTAssertEqual(BatteryCalculations.plausibleAdapterWatts(140), 140)
        XCTAssertNil(BatteryCalculations.plausibleAdapterWatts(Int.max))
        XCTAssertEqual(BatteryCalculations.plausibleCycleCount(1_000), 1_000)
        XCTAssertNil(BatteryCalculations.plausibleCycleCount(Int.max))
    }

    func testTemperatureConversionDefaultsToHundredthsCelsius() throws {
        let temperature = try XCTUnwrap(BatteryCalculations.temperatureCelsius(fromRaw: 3_420))

        XCTAssertEqual(temperature, 34.2, accuracy: 0.0001)
    }

    func testTemperatureConversionRejectsImplausibleRawValues() {
        XCTAssertNil(BatteryCalculations.temperatureCelsius(fromRaw: 50_000))
    }

    func testPlausibleTemperatureRejectsNonFiniteAndOutOfRangeValues() {
        XCTAssertEqual(BatteryCalculations.plausibleTemperatureCelsius(34.2), 34.2)
        XCTAssertNil(BatteryCalculations.plausibleTemperatureCelsius(.nan))
        XCTAssertNil(BatteryCalculations.plausibleTemperatureCelsius(-30))
        XCTAssertNil(BatteryCalculations.plausibleTemperatureCelsius(180))
    }

    func testBatteryAgeRejectsFutureManufactureDate() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(BatteryCalculations.plausibleManufactureDate(now.addingTimeInterval(60), now: now))
        XCTAssertNil(BatteryCalculations.batteryAgeComponents(
            from: now.addingTimeInterval(60),
            now: now
        ))
    }

    func testBatteryAgeRejectsImplausiblyOldManufactureDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let oldManufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2005, month: 12, day: 31)))
        let supportedManufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2006, month: 1, day: 1)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28)))

        XCTAssertNil(BatteryCalculations.plausibleManufactureDate(oldManufactureDate, now: now))
        XCTAssertNil(BatteryCalculations.batteryAgeComponents(from: oldManufactureDate, now: now))
        XCTAssertEqual(BatteryCalculations.plausibleManufactureDate(supportedManufactureDate, now: now), supportedManufactureDate)
    }

    func testBatteryAgeComponentsUseGregorianCalendarByDefault() throws {
        let calendar = Calendar(identifier: .gregorian)
        let manufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2023, month: 9, day: 12)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28)))

        let components = try XCTUnwrap(BatteryCalculations.batteryAgeComponents(from: manufactureDate, now: now))

        XCTAssertEqual(components.year, 2)
        XCTAssertEqual(components.month, 9)
    }

    func testBatteryAgeUsesManufactureDayInsteadOfRawTimeOfDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let manufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2023,
            month: 9,
            day: 12,
            hour: 22
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2023,
            month: 10,
            day: 12,
            hour: 1
        )))

        let components = try XCTUnwrap(BatteryCalculations.batteryAgeComponents(
            from: manufactureDate,
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(components.year, 0)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 0)
    }

    func testBatteryAgeDoesNotRejectLaterTimeOnSameManufactureDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let manufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 28,
            hour: 18
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 28,
            hour: 9
        )))

        XCTAssertEqual(BatteryCalculations.plausibleManufactureDate(manufactureDate, now: now), manufactureDate)

        let components = try XCTUnwrap(BatteryCalculations.batteryAgeComponents(
            from: manufactureDate,
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(components.year, 0)
        XCTAssertEqual(components.month, 0)
        XCTAssertEqual(components.day, 0)
    }

    func testDisplayableBatteryAgeRejectsMalformedComponents() {
        XCTAssertNil(BatteryCalculations.displayableBatteryAgeComponents(DateComponents(year: -1, month: 2)))
        XCTAssertNil(BatteryCalculations.displayableBatteryAgeComponents(DateComponents(year: 1, month: -2)))
        XCTAssertNil(BatteryCalculations.displayableBatteryAgeComponents(DateComponents(year: 1, month: 12)))
        XCTAssertNil(BatteryCalculations.displayableBatteryAgeComponents(DateComponents(year: 1, month: 2, day: -1)))
        XCTAssertNil(BatteryCalculations.displayableBatteryAgeMonthCount(DateComponents(year: Int.max, month: 1)))

        XCTAssertEqual(
            BatteryCalculations.displayableBatteryAgeMonthCount(DateComponents(year: 2, month: 3, day: 30)),
            27
        )
    }

    func testDerivedCurrentChargeUsesNormalizedPublicPercent() {
        XCTAssertEqual(
            BatteryCalculations.deriveCurrentChargeMilliampHours(
                publicPercentage: 105,
                fullChargeCapacityMilliampHours: 5_000
            ),
            5_000
        )
    }

    func testDerivedCurrentChargeRejectsImpossiblePublicPercent() {
        XCTAssertNil(BatteryCalculations.deriveCurrentChargeMilliampHours(
            publicPercentage: -1,
            fullChargeCapacityMilliampHours: 5_000
        ))
        XCTAssertNil(BatteryCalculations.deriveCurrentChargeMilliampHours(
            publicPercentage: 106,
            fullChargeCapacityMilliampHours: 5_000
        ))
        XCTAssertNil(BatteryCalculations.deriveCurrentChargeMilliampHours(
            publicPercentage: 50,
            fullChargeCapacityMilliampHours: 0
        ))
    }

    func testSmoothedDischargeRateUsesRecentSamples() {
        let now = Date(timeIntervalSince1970: 1_060)
        let samples = [
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_000), milliamps: 1_200),
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_020), milliamps: 1_100),
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_040), milliamps: 1_050),
            BatteryDischargeRateSample(timestamp: now, milliamps: 980)
        ]

        XCTAssertEqual(BatteryCalculations.confidentSmoothedDischargeRate(samples, now: now), 1_083)
    }

    func testSmoothedDischargeRateIgnoresAbsurdSamples() {
        let now = Date(timeIntervalSince1970: 1_060)
        let samples = [
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_000), milliamps: Int.max),
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_030), milliamps: 1_000),
            BatteryDischargeRateSample(timestamp: now, milliamps: 900)
        ]

        XCTAssertNil(BatteryCalculations.confidentSmoothedDischargeRate(samples, now: now))
    }

    func testConfidentDischargeRateRequiresRecentStableTimestampedSamples() {
        let now = Date(timeIntervalSince1970: 1_060)
        let stableSamples = [
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_000), milliamps: 1_200),
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_030), milliamps: 1_180),
            BatteryDischargeRateSample(timestamp: now, milliamps: 1_220)
        ]

        XCTAssertEqual(
            BatteryCalculations.confidentSmoothedDischargeRate(stableSamples, now: now),
            1_200
        )
        XCTAssertNil(
            BatteryCalculations.confidentSmoothedDischargeRate(Array(stableSamples.prefix(2)), now: now)
        )
        XCTAssertNil(
            BatteryCalculations.confidentSmoothedDischargeRate(
                stableSamples,
                now: now.addingTimeInterval(181)
            )
        )
    }

    func testConfidentDischargeRateRejectsUnstableOrCompressedSamples() {
        let now = Date(timeIntervalSince1970: 1_060)
        let unstableSamples = [
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_000), milliamps: 600),
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_030), milliamps: 1_200),
            BatteryDischargeRateSample(timestamp: now, milliamps: 2_400)
        ]
        let compressedSamples = [
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_058), milliamps: 1_200),
            BatteryDischargeRateSample(timestamp: Date(timeIntervalSince1970: 1_059), milliamps: 1_190),
            BatteryDischargeRateSample(timestamp: now, milliamps: 1_210)
        ]

        XCTAssertNil(BatteryCalculations.confidentSmoothedDischargeRate(unstableSamples, now: now))
        XCTAssertNil(BatteryCalculations.confidentSmoothedDischargeRate(compressedSamples, now: now))
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

    func testEstimatedTimeToFullReturnsZeroWhenCapacityIsFullWithoutCurrentTelemetry() {
        let estimated = BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: 5_338,
            fullChargeCapacityMilliampHours: 5_338,
            chargeCurrentMilliamps: nil,
            reportedTimeToFullMinutes: nil
        )

        XCTAssertEqual(estimated, 0)
    }

    func testEstimatedTimeToFullKeepsReportedTopOffTimeAtFullCapacity() {
        XCTAssertEqual(
            BatteryCalculations.estimatedTimeToFullMinutes(
                currentChargeMilliampHours: 5_338,
                fullChargeCapacityMilliampHours: 5_338,
                chargeCurrentMilliamps: nil,
                reportedTimeToFullMinutes: 12
            ),
            12
        )
    }

    func testEstimatedTimeToFullDoesNotClaimZeroDuringActiveTopOffCharging() {
        XCTAssertNil(
            BatteryCalculations.estimatedTimeToFullMinutes(
                currentChargeMilliampHours: 5_338,
                fullChargeCapacityMilliampHours: 5_338,
                chargeCurrentMilliamps: 500,
                reportedTimeToFullMinutes: nil
            )
        )
    }

    func testEstimatedTimeToFullRejectsInvalidCapacityBeforeReportingFull() {
        XCTAssertEqual(
            BatteryCalculations.estimatedTimeToFullMinutes(
                currentChargeMilliampHours: 0,
                fullChargeCapacityMilliampHours: 0,
                chargeCurrentMilliamps: 1_721,
                reportedTimeToFullMinutes: 52
            ),
            52
        )

        XCTAssertEqual(
            BatteryCalculations.estimatedTimeToFullMinutes(
                currentChargeMilliampHours: -1,
                fullChargeCapacityMilliampHours: 5_338,
                chargeCurrentMilliamps: 1_721,
                reportedTimeToFullMinutes: 52
            ),
            52
        )
    }

    func testEstimatedTimeToFullRejectsAbsurdReportedFallback() {
        XCTAssertNil(BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: 0,
            fullChargeCapacityMilliampHours: 0,
            chargeCurrentMilliamps: 1_721,
            reportedTimeToFullMinutes: Int.max
        ))
    }

    func testPlausibleDurationRejectsAbsurdValues() {
        XCTAssertEqual(BatteryCalculations.plausibleDurationMinutes(0), 0)
        XCTAssertEqual(BatteryCalculations.plausibleDurationMinutes(1_440), 1_440)
        XCTAssertNil(BatteryCalculations.plausibleDurationMinutes(-1))
        XCTAssertNil(BatteryCalculations.plausibleDurationMinutes(1_441))
        XCTAssertNil(BatteryCalculations.plausibleDurationMinutes(Int.max))
    }

    func testPowerStateUsesChargedFlagWhenCapacityDetailsAreMissing() {
        let powerState = BatteryCalculations.derivePowerState(
            isCharging: false,
            isCharged: true,
            isExternalPowerConnected: true,
            signedCurrentMilliamps: nil,
            currentChargeMilliampHours: nil,
            fullChargeCapacityMilliampHours: nil
        )

        XCTAssertEqual(powerState, .fullOnAC)
    }

    func testPowerStateDoesNotShowChargingWhenExternalPowerIsDisconnected() {
        let powerState = BatteryCalculations.derivePowerState(
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: false,
            signedCurrentMilliamps: nil,
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000
        )

        XCTAssertEqual(powerState, .onBattery)
    }

    func testPowerStateUsesSignedChargeCurrentWhenPublicPowerStateIsStale() {
        let powerState = BatteryCalculations.derivePowerState(
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: false,
            signedCurrentMilliamps: 1_200,
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000
        )

        XCTAssertEqual(powerState, .charging)
    }

    func testPowerStateShowsConnectedDischargingWhenExternalPowerIsDrainingBattery() {
        let powerState = BatteryCalculations.derivePowerState(
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: true,
            signedCurrentMilliamps: -900,
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000
        )

        XCTAssertEqual(powerState, .connectedDischarging)
    }

    func testPowerStatePrefersSignedDischargeCurrentOverChargingFlagWhenDisconnected() {
        let powerState = BatteryCalculations.derivePowerState(
            isCharging: true,
            isCharged: false,
            isExternalPowerConnected: false,
            signedCurrentMilliamps: -900,
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000
        )

        XCTAssertEqual(powerState, .onBattery)
    }

    func testNormalizedPowerFlagsFollowDerivedPowerState() {
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .charging).isCharging, true)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .charging).isExternalPowerConnected, true)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .connectedDischarging).isCharging, false)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .connectedDischarging).isExternalPowerConnected, true)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .connectedNotCharging).isCharging, false)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .connectedNotCharging).isExternalPowerConnected, true)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .fullOnAC).isCharging, false)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .fullOnAC).isExternalPowerConnected, true)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .onBattery).isCharging, false)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .onBattery).isExternalPowerConnected, false)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .unknown).isCharging, false)
        XCTAssertEqual(BatteryCalculations.normalizedPowerFlags(for: .unknown).isExternalPowerConnected, false)
    }

    func testPowerStateIgnoresTinyNegativeCurrentNoiseWhenConnectedToAC() {
        let powerState = BatteryCalculations.derivePowerState(
            isCharging: false,
            isCharged: false,
            isExternalPowerConnected: true,
            signedCurrentMilliamps: -1,
            currentChargeMilliampHours: 4_000,
            fullChargeCapacityMilliampHours: 5_000
        )

        XCTAssertEqual(powerState, .connectedNotCharging)
    }
}
