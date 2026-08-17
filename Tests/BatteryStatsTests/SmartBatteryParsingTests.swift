import XCTest
@testable import BatteryStats

final class SmartBatteryParsingTests: XCTestCase {
    func testReaderParsesPrimarySmartBatteryKeys() throws {
        let properties: [String: Any] = [
            "AppleRawCurrentCapacity": 4_912,
            "AppleRawMaxCapacity": 5_338,
            "DesignCapacity": 6_559,
            "CycleCount": 247,
            "Voltage": 12_780,
            "InstantAmperage": "18446744073709549095",
            "Temperature": 3_420,
            "ManufactureDate": 22_316,
            "PowerDistribution": [
                "IPDInputPower": 39_800
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 1_562
            ],
            "AdapterDetails": [
                "Watts": 70
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 4_912)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 5_338)
        XCTAssertEqual(details.designCapacityMilliampHours, 6_559)
        XCTAssertEqual(details.signedCurrentMilliamps, -2_521)
        XCTAssertEqual(try XCTUnwrap(details.temperatureCelsius), 34.2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 31.24, accuracy: 0.001)
        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertNotNil(details.manufactureDate)
    }

    func testReaderParsesObservedAppleSiliconInputTelemetryWithoutUsingAdapterCeiling() throws {
        let properties: [String: Any] = [
            "CurrentCapacity": 50,
            "MaxCapacity": 100,
            "Voltage": 12_277,
            "InstantAmperage": 4_235,
            "AdapterDetails": [
                "Watts": 65
            ],
            "PowerDistribution": [
                "IPDInputPower": 65_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_250
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 19_381,
                "SystemCurrentIn": 3_158,
                "SystemPowerIn": 61_211,
                "SystemPowerInAccumulatorCount": 2_100,
                "BatteryPower": 51_600
            ],
            "ManufacturerData": Data([
                0x00, 0x00, 0x00, 0x00,
                0x0b, 0x00, 0x01, 0x00,
                0x55, 0x1d, 0x00, 0x00
            ])
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 65)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 61.211, accuracy: 0.001)
        XCTAssertNotEqual(details.inputPowerWatts, Double(details.adapterMaxWatts ?? 0))
        XCTAssertEqual(details.signedCurrentMilliamps, 4_235)
        XCTAssertNil(details.manufactureDate)
    }

    func testReaderUsesCounterBackedSystemPowerInForCurrentChargerSpeed() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 65
            ],
            "PowerDistribution": [
                "IPDInputPower": 65_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_250
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 15_090,
                "SystemPowerInAccumulatorCount": 5_454,
                "SystemVoltageIn": 19_916,
                "SystemCurrentIn": 757
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 65)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 15.09, accuracy: 0.001)
        XCTAssertNotEqual(details.inputPowerWatts, Double(details.adapterMaxWatts ?? 0))
    }

    func testReaderUsesCounterBackedSystemPowerInNearAdapterCapability() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 70
            ],
            "PowerDistribution": [
                "IPDInputPower": 70_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345,
                "SystemVoltageIn": 19_834,
                "SystemCurrentIn": 3_500
            ]
        ])

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderUsesNegotiatedAdapterPowerWhenReportedAdapterDetailsAreMissing() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ])

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderUsesLiveSystemPowerInAsCurrentInputBelowNegotiatedContract() throws {
        let details = SmartBatteryReader().parse(properties: [
            "ExternalConnected": true,
            "AdapterDetails": [
                "Watts": 45,
                "AdapterVoltage": 20_000,
                "Current": 2_240
            ],
            "PowerDistribution": [
                "IPDInputPower": 44_800,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 2_240
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 8_594,
                "SystemPowerInAccumulatorCount": 20_269,
                "SystemVoltageIn": 20_005,
                "SystemCurrentIn": 430
            ],
            "ChargerData": [
                "IsCharging": false
            ]
        ])

        XCTAssertEqual(details.adapterMaxWatts, 45)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 8.594, accuracy: 0.001)
        XCTAssertNotEqual(details.inputPowerWatts, Double(details.adapterMaxWatts ?? 0))
        XCTAssertEqual(details.isCharging, false)
        XCTAssertEqual(details.isExternalPowerConnected, true)
    }

    func testReaderPrefersNegotiatedSeventyWattContractOverStaleHundredWattAdapterReport() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 100
            ],
            "PowerDistribution": [
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 64_200,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ])

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 64.2, accuracy: 0.001)
        XCTAssertNotEqual(details.inputPowerWatts, Double(details.adapterMaxWatts ?? 0))
    }

    func testReaderRejectsCounterBackedSystemPowerInThatExactlyMirrorsAdapterCapability() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 100
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 100_000,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ])

        XCTAssertEqual(details.adapterMaxWatts, 100)
        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderFallsBackToLegacyNestedKeys() {
        let properties: [String: Any] = [
            "CurrentCapacity": 4_100,
            "NominalChargeCapacity": 5_200,
            "LegacyBatteryInfo": [
                "Cycle Count": 120,
                "Amperage": -1_500,
                "Voltage": 12_800
            ],
            "BatteryData": [
                "Voltage": 12_900
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 4_100)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 5_200)
        XCTAssertEqual(details.cycleCount, 120)
        XCTAssertEqual(details.signedCurrentMilliamps, -1_500)
        XCTAssertEqual(details.voltageMillivolts, 12_900)
        XCTAssertNil(details.temperatureCelsius)
        XCTAssertNil(details.manufactureDate)
    }

    func testReaderParsesNestedTemperatureAndManufactureDate() throws {
        let properties: [String: Any] = [
            "BatteryData": [
                "Temperature": 3_330,
                "ManufactureDate": 22_316
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(try XCTUnwrap(details.temperatureCelsius), 33.3, accuracy: 0.0001)
        XCTAssertNotNil(details.manufactureDate)
    }

    func testReaderSkipsInvalidTemperatureCandidateAndUsesNextValidValue() throws {
        let details = SmartBatteryReader().parse(properties: [
            "Temperature": Int.max,
            "BatteryData": [
                "Temperature": 3_210
            ]
        ])

        XCTAssertEqual(details.rawTemperature, 3_210)
        XCTAssertEqual(try XCTUnwrap(details.temperatureCelsius), 32.1, accuracy: 0.0001)
    }

    func testReaderSkipsInvalidManufactureDateCandidateAndUsesNextValidValue() throws {
        let details = SmartBatteryReader().parse(properties: [
            "ManufactureDate": 0x353131313333,
            "BatteryData": [
                "ManufactureDate": 22_316
            ]
        ])

        let manufactureDate = try XCTUnwrap(details.manufactureDate)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: manufactureDate)
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 12)
    }

    func testReaderAcceptsPreAppleSiliconManufactureDateCandidate() throws {
        let decemberThirtyFirst2019 = packedManufactureDate(year: 2019, month: 12, day: 31)
        let details = SmartBatteryReader().parse(properties: [
            "ManufactureDate": decemberThirtyFirst2019,
            "BatteryData": [
                "ManufactureDate": 22_316
            ]
        ])

        let manufactureDate = try XCTUnwrap(details.manufactureDate)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: manufactureDate)
        XCTAssertEqual(components.year, 2019)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 31)
    }

    func testReaderSkipsFutureManufactureDateCandidateAndUsesNextValidValue() throws {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let futureDate = packedManufactureDate(year: currentYear + 1, month: 1, day: 1)
        let details = SmartBatteryReader().parse(properties: [
            "ManufactureDate": futureDate,
            "BatteryData": [
                "ManufactureDate": 22_316
            ]
        ])

        let manufactureDate = try XCTUnwrap(details.manufactureDate)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: manufactureDate)
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 12)
    }

    func testReaderDoesNotTreatStructuredManufacturerDataCellRevisionAsManufactureDate() throws {
        let details = SmartBatteryReader().parse(properties: [
            "BatteryData": [
                "ManufactureDate": 0x353131313333
            ],
            "ManufacturerData": Data([
                0x00, 0x00, 0x00, 0x00,
                0x0b, 0x00, 0x01, 0x00,
                0x55, 0x1d, 0x00, 0x00
            ])
        ])

        XCTAssertNil(details.manufactureDate)
    }

    func testReaderPrefersExplicitManufactureDateOverManufacturerDataCellRevision() throws {
        let directDate = packedManufactureDate(year: 2023, month: 9, day: 12)
        let details = SmartBatteryReader().parse(properties: [
            "ManufactureDate": directDate,
            "ManufacturerData": Data([
                0x00, 0x00, 0x00, 0x00,
                0x0b, 0x00, 0x01, 0x00,
                0x55, 0x1d, 0x00, 0x00
            ])
        ])

        let manufactureDate = try XCTUnwrap(details.manufactureDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: manufactureDate)
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 12)
    }

    func testReaderDoesNotTreatNestedPackMfgDataCellRevisionAsManufactureDate() throws {
        let details = SmartBatteryReader().parse(properties: [
            "BatteryData": [
                "ManufactureDate": 0x353131313333,
                "MfgData": Data([
                    0x00, 0x00, 0x00, 0x00,
                    0x0b, 0x00, 0x01, 0x00,
                    0x55, 0x1d, 0x00, 0x00
                ])
            ]
        ])

        XCTAssertNil(details.manufactureDate)
    }

    func testReaderDoesNotUsePackBatteryDataManufactureDateAsUserVisibleManufactureDate() throws {
        let details = SmartBatteryReader().parse(properties: [
            "BatteryData": [
                "CurrentCapacity": 51
            ],
            "AppleSmartBatteryPack": [
                "BatteryData": [
                    "ManufactureDate": 22_316
                ]
            ]
        ])

        XCTAssertNil(details.manufactureDate)
    }

    func testReaderDoesNotUseMergedPackBatteryDataManufactureDateAsUserVisibleManufactureDate() throws {
        let mergedProperties = SmartBatteryReader.mergedProperties(
            rootProperties: [
                "BatteryData": [
                    "CurrentCapacity": 51
                ]
            ],
            packProperties: [
                "BatteryData": [
                    "ManufactureDate": 22_316,
                    "AppleRawCurrentCapacity": 3_623
                ]
            ]
        )

        let details = SmartBatteryReader().parse(properties: mergedProperties)

        XCTAssertNil(details.manufactureDate)
        XCTAssertEqual(details.currentChargeMilliampHours, 3_623)
    }

    func testReaderDoesNotTreatLiveStyleManufacturerDataBlobAsManufactureDate() throws {
        let details = SmartBatteryReader().parse(properties: [
            "ManufacturerData": Data([
                0x00, 0x00, 0x00, 0x00,
                0x0b, 0x00, 0x01, 0x00,
                0x55, 0x1d, 0x00, 0x00,
                0x04, 0x33, 0x33, 0x35,
                0x31, 0x33, 0x03, 0x30,
                0x30, 0x41, 0x03, 0x41,
                0x54, 0x4c, 0x00, 0x21
            ])
        ])

        XCTAssertNil(details.manufactureDate)
    }

    func testReaderDoesNotScanArbitraryManufacturerDataForDateCandidates() {
        let details = SmartBatteryReader().parse(properties: [
            "ManufacturerData": Data([
                0x55, 0x1d, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00
            ])
        ])

        XCTAssertNil(details.manufactureDate)
    }

    func testReaderDoesNotTreatAggregateInputPowerAsLiveInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputPower": 59_800
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 38_651
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderFallsBackToCorroboratedSystemPowerInForLiveInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 65
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 40_310,
                "SystemPowerInAccumulatorCount": 34_669
            ]
        ])

        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 40.31, accuracy: 0.001)
        XCTAssertEqual(details.adapterMaxWatts, 65)
    }

    func testReaderRejectsCorroboratedSystemPowerInAboveAdapterCapability() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 70
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 100_000,
                "SystemPowerInAccumulatorCount": 34_669
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
        XCTAssertEqual(details.adapterMaxWatts, 70)
    }

    func testReaderRejectsLiveVoltageCurrentAboveAdapterCapability() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 70
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 5_000
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
        XCTAssertEqual(details.adapterMaxWatts, 70)
    }

    func testReaderRejectsUnverifiedHundredWattLiveInputPowerWithoutAdapterCapability() throws {
        let voltageCurrentDetails = SmartBatteryReader().parse(properties: [
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 5_000
            ]
        ])
        let counterDetails = SmartBatteryReader().parse(properties: [
            "PowerTelemetryData": [
                "SystemPowerIn": 100_000,
                "SystemPowerInAccumulatorCount": 34_669
            ]
        ])

        XCTAssertNil(voltageCurrentDetails.inputPowerWatts)
        XCTAssertNil(voltageCurrentDetails.adapterMaxWatts)
        XCTAssertNil(counterDetails.inputPowerWatts)
        XCTAssertNil(counterDetails.adapterMaxWatts)
    }

    func testReaderRejectsChargerPowerAboveAdapterCapability() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 70
            ],
            "AppleChargerData": [
                "ChargerPower": 100_000
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
        XCTAssertEqual(details.adapterMaxWatts, 70)
    }

    func testReaderRejectsSystemPowerInThatMirrorsNegotiatedInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 100
            ],
            "PowerDistribution": [
                "IPDInputPower": 100_000
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 100_000,
                "SystemPowerInAccumulatorCount": 34_669
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderRejectsSystemPowerInThatNearlyMirrorsNegotiatedInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "Watts": 100
            ],
            "PowerDistribution": [
                "IPDInputPower": 100_000
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 99_996,
                "SystemPowerInAccumulatorCount": 34_669
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderDoesNotTreatNegotiatedInputPowerAsLiveInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputPower": 59_800
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": Int.max
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderPrefersLiveInputVoltageAndCurrentOverNegotiatedInputLimit() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputPower": 100_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 2_990
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 19_758,
                "SystemCurrentIn": 1_956
            ]
        ])

        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 38.646648, accuracy: 0.001)
    }

    func testReaderRejectsSystemVoltageAndCurrentThatMirrorNegotiatedInputPower() throws {
        let exactDetails = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputPower": 100_000
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 5_000
            ],
            "AdapterDetails": [
                "Watts": 100
            ]
        ])

        XCTAssertNil(exactDetails.inputPowerWatts)

        let nearDetails = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputPower": 100_000
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 4_950
            ],
            "AdapterDetails": [
                "Watts": 100
            ]
        ])

        XCTAssertNil(nearDetails.inputPowerWatts)
    }

    func testReaderRejectsSystemVoltageAndCurrentThatMirrorAdapterCapability() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 5_000
            ],
            "AdapterDetails": [
                "Watts": 100
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
        XCTAssertEqual(details.adapterMaxWatts, 100)
    }

    func testReaderRejectsSystemVoltageAndCurrentThatMirrorNegotiatedVoltageAndCurrent() throws {
        let exactDetails = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 5_000
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 5_000
            ],
            "AdapterDetails": [
                "Watts": 100
            ]
        ])

        XCTAssertNil(exactDetails.inputPowerWatts)

        let nearDetails = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 5_000
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 4_950
            ],
            "AdapterDetails": [
                "Watts": 100
            ]
        ])

        XCTAssertNil(nearDetails.inputPowerWatts)
    }

    func testReaderAcceptsLiveVoltageAndCurrentDistinctFromNegotiatedVoltageAndCurrent() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 5_000
            ],
            "PowerTelemetryData": [
                "SystemVoltageIn": 19_758,
                "SystemCurrentIn": 1_956
            ],
            "AdapterDetails": [
                "Watts": 100
            ]
        ])

        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 38.646648, accuracy: 0.001)
    }

    func testReaderPrefersLiveInputVoltageAndCurrentOverAggregateInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerTelemetryData": [
                "SystemPowerIn": 100_000,
                "SystemVoltageIn": 19_758,
                "SystemCurrentIn": 1_956
            ]
        ])

        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 38.646648, accuracy: 0.001)
    }

    func testReaderDoesNotTreatChargerBusVoltageAndCurrentAsLiveInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AppleChargerData": [
                "ChargerVBUS": 19_750,
                "ChargerIBUS": 1_950
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderIgnoresChargerPowerBecauseItCanBeNegotiatedCapacity() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AppleChargerData": [
                "ChargerPower": 38_500
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderDoesNotShowNegotiatedChargerPowerAsHundredWattInput() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AppleChargerData": [
                "ChargerPower": 100_000
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderRejectsChargerPowerThatMirrorsNegotiatedInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputPower": 100_000
            ],
            "AppleChargerData": [
                "ChargerPower": 100_000
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderRejectsChargerPowerThatNearlyMirrorsNegotiatedInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputPower": 100_000
            ],
            "AppleChargerData": [
                "ChargerPower": 99_996
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderUsesPowerTelemetryAndIgnoresChargerBusCapability() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerTelemetryData": [
                "SystemVoltageIn": 19_000,
                "SystemCurrentIn": 1_000
            ],
            "AppleChargerData": [
                "ChargerVBUS": 20_000,
                "ChargerIBUS": 4_000
            ]
        ])

        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 19, accuracy: 0.001)
    }

    func testReaderAcceptsSignedLiveInputCurrentAsMagnitude() throws {
        let signedDetails = SmartBatteryReader().parse(properties: [
            "PowerTelemetryData": [
                "SystemVoltageIn": 19_758,
                "SystemCurrentIn": -1_956
            ]
        ])

        XCTAssertEqual(try XCTUnwrap(signedDetails.inputPowerWatts), 38.646648, accuracy: 0.001)

        let unsignedEncodedDetails = SmartBatteryReader().parse(properties: [
            "PowerTelemetryData": [
                "SystemVoltageIn": 19_758,
                "SystemCurrentIn": "18446744073709549660"
            ]
        ])

        XCTAssertEqual(try XCTUnwrap(unsignedEncodedDetails.inputPowerWatts), 38.646648, accuracy: 0.001)
    }

    func testReaderDoesNotTreatNegotiatedInputVoltageAndCurrentAsLiveInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerDistribution": [
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 2_990
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderIgnoresLiveInputVoltageAndCurrentThatWouldRenderAsZeroWatts() throws {
        let details = SmartBatteryReader().parse(properties: [
            "PowerTelemetryData": [
                "SystemVoltageIn": 20_000,
                "SystemCurrentIn": 4
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderDoesNotTreatAdapterCapabilityAsLiveInputPower() throws {
        let details = SmartBatteryReader().parse(properties: [
            "AdapterDetails": [
                "AdapterVoltage": 20_000,
                "Current": 5_000,
                "Watts": 100
            ]
        ])

        XCTAssertNil(details.inputPowerWatts)
        XCTAssertEqual(details.adapterMaxWatts, 100)
    }

    func testReaderMergesAppleChargerDataWithoutTreatingBusAsInputPower() throws {
        let mergedProperties = SmartBatteryReader.mergedProperties(
            rootProperties: [:],
            packProperties: nil,
            chargerProperties: [
                "ChargerData": [
                    "ChargerVBUS": 19_750,
                    "ChargerIBUS": 1_950
                ]
            ]
        )

        let details = SmartBatteryReader().parse(properties: mergedProperties)

        XCTAssertNil(details.inputPowerWatts)
        XCTAssertNotNil(mergedProperties["AppleChargerData"])
    }

    func testReaderMergesAppleChargerDataChargingFlag() throws {
        let mergedProperties = SmartBatteryReader.mergedProperties(
            rootProperties: [:],
            packProperties: nil,
            chargerProperties: [
                "ChargerData": [
                    "IsCharging": NSNumber(value: true)
                ]
            ]
        )

        let details = SmartBatteryReader().parse(properties: mergedProperties)

        XCTAssertEqual(details.isCharging, true)
    }

    func testReaderMergesRootAppleChargerDataChargingFlag() throws {
        let mergedProperties = SmartBatteryReader.mergedProperties(
            rootProperties: [:],
            packProperties: nil,
            chargerProperties: [
                "IsCharging": NSNumber(value: true)
            ]
        )

        let details = SmartBatteryReader().parse(properties: mergedProperties)

        XCTAssertEqual(details.isCharging, true)
    }

    func testReaderFallsBackToRootAppleChargerDataWhenNestedChargerDataIsEmpty() throws {
        let mergedProperties = SmartBatteryReader.mergedProperties(
            rootProperties: [:],
            packProperties: nil,
            chargerProperties: [
                "ChargerData": [:],
                "IsCharging": NSNumber(value: true)
            ]
        )

        let details = SmartBatteryReader().parse(properties: mergedProperties)

        XCTAssertEqual(details.isCharging, true)
    }

    func testReaderMergesPackBatteryDataWhenParentBatteryDataIsSparse() throws {
        let rootProperties: [String: Any] = [
            "BatteryData": [
                "RemainingCapacity": 258,
                "FullChargeCapacity": 4_630,
                "DesignCapacity": 4_629,
                "CurrentCapacity": 6,
                "MaxCapacity": 100
            ]
        ]
        let packProperties: [String: Any] = [
            "BatteryData": [
                "Temperature": 2_700,
                "AppleRawCurrentCapacity": 258,
                "AppleRawMaxCapacity": 4_630,
                "NominalChargeCapacity": 4_757
            ]
        ]
        let mergedProperties = SmartBatteryReader.mergedProperties(
            rootProperties: rootProperties,
            packProperties: packProperties
        )

        let details = SmartBatteryReader().parse(properties: mergedProperties)

        XCTAssertEqual(details.currentChargeMilliampHours, 258)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 4_630)
        XCTAssertEqual(try XCTUnwrap(details.temperatureCelsius), 27.0, accuracy: 0.0001)
        XCTAssertNotNil(mergedProperties["AppleSmartBatteryPack"])
    }

    func testReaderKeepsParentBatteryDataWhenPackRepeatsAKey() throws {
        let mergedProperties = SmartBatteryReader.mergedProperties(
            rootProperties: [
                "BatteryData": [
                    "Temperature": 3_300
                ]
            ],
            packProperties: [
                "BatteryData": [
                    "Temperature": 2_700
                ]
            ]
        )

        let details = SmartBatteryReader().parse(properties: mergedProperties)

        XCTAssertEqual(try XCTUnwrap(details.temperatureCelsius), 33.0, accuracy: 0.0001)
    }

    func testReaderFallsBackToPackBatteryDataWhenParentRepeatedKeyIsInvalid() {
        let mergedProperties = SmartBatteryReader.mergedProperties(
            rootProperties: [
                "BatteryData": [
                    "AppleRawCurrentCapacity": 0,
                    "AppleRawMaxCapacity": 0,
                    "DesignCapacity": Int.max,
                    "CycleCount": Int.max,
                    "Voltage": Int.max,
                    "InstantAmperage": Int.max
                ]
            ],
            packProperties: [
                "BatteryData": [
                    "AppleRawCurrentCapacity": 258,
                    "AppleRawMaxCapacity": 4_630,
                    "DesignCapacity": 4_629,
                    "CycleCount": 7,
                    "Voltage": 12_711,
                    "InstantAmperage": -900
                ]
            ]
        )

        let details = SmartBatteryReader().parse(properties: mergedProperties)

        XCTAssertEqual(details.currentChargeMilliampHours, 258)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 4_630)
        XCTAssertEqual(details.designCapacityMilliampHours, 4_629)
        XCTAssertEqual(details.cycleCount, 7)
        XCTAssertEqual(details.voltageMillivolts, 12_711)
        XCTAssertEqual(details.signedCurrentMilliamps, -900)
    }

    func testReaderParsesNestedCurrentAndCycleCount() {
        let properties: [String: Any] = [
            "BatteryData": [
                "InstantAmperage": "18446744073709550716",
                "CycleCount": 321
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.signedCurrentMilliamps, -900)
        XCTAssertEqual(details.cycleCount, 321)
    }

    func testReaderParsesSmartTimeToFullWhenPublicEstimateIsMissing() {
        let properties: [String: Any] = [
            "InstantAmperage": 4_387,
            "TimeRemaining": 112,
            "AvgTimeToEmpty": 65_535,
            "AvgTimeToFull": 112
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.reportedTimeToFullMinutes, 112)
        XCTAssertNil(details.reportedTimeToEmptyMinutes)
    }

    func testReaderUsesGenericSmartTimeRemainingForDischargeOnlyWhenSpecificEstimateIsMissing() {
        let properties: [String: Any] = [
            "InstantAmperage": -900,
            "TimeRemaining": 180
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.reportedTimeToEmptyMinutes, 180)
        XCTAssertNil(details.reportedTimeToFullMinutes)
    }

    func testReaderParsesSmartPowerStateBooleans() {
        let properties: [String: Any] = [
            "ExternalConnected": NSNumber(value: true),
            "ChargerData": [
                "IsCharging": NSNumber(value: 1)
            ],
            "BatteryData": [
                "FullyCharged": NSNumber(value: 0)
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.isExternalPowerConnected, true)
        XCTAssertEqual(details.isCharging, true)
        XCTAssertEqual(details.isFullyCharged, false)
    }

    func testReaderIgnoresInvalidSmartPowerStateNumbers() {
        let properties: [String: Any] = [
            "ExternalConnected": NSNumber(value: 2),
            "IsCharging": NSNumber(value: -1),
            "FullyCharged": NSNumber(value: 42)
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertNil(details.isExternalPowerConnected)
        XCTAssertNil(details.isCharging)
        XCTAssertNil(details.isFullyCharged)
    }

    func testReaderRejectsBooleanNumericMetrics() {
        let properties: [String: Any] = [
            "Voltage": NSNumber(value: true),
            "CycleCount": NSNumber(value: true),
            "InstantAmperage": NSNumber(value: false),
            "AdapterDetails": [
                "Watts": NSNumber(value: true)
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertNil(details.voltageMillivolts)
        XCTAssertNil(details.cycleCount)
        XCTAssertNil(details.signedCurrentMilliamps)
        XCTAssertNil(details.adapterMaxWatts)
    }

    func testReaderIgnoresFractionalSmartPowerStateNumbers() {
        let properties: [String: Any] = [
            "ExternalConnected": NSNumber(value: 0.5),
            "IsCharging": NSNumber(value: 1.9),
            "FullyCharged": NSNumber(value: -0.1)
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertNil(details.isExternalPowerConnected)
        XCTAssertNil(details.isCharging)
        XCTAssertNil(details.isFullyCharged)
    }

    func testReaderPrefersOS27PhysicalBatteryDataOverPercentageCapacities() {
        let properties: [String: Any] = [
            "CurrentCapacity": 80,
            "MaxCapacity": 100,
            "BatteryData": [
                "RemainingCapacity": 3_506,
                "FullChargeCapacity": 4_436,
                "NominalChargeCapacity": 4_563,
                "DesignCapacity": 4_563,
                "CurrentCapacity": 80,
                "MaxCapacity": 100
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 3_506)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 4_436)
        XCTAssertEqual(details.designCapacityMilliampHours, 4_563)
    }

    func testReaderSkipsAbsurdCapacityCandidateAndUsesNextPhysicalValue() {
        let properties: [String: Any] = [
            "AppleRawCurrentCapacity": Int.max,
            "BatteryData": [
                "RemainingCapacity": 3_506,
                "FullChargeCapacity": 4_436,
                "DesignCapacity": 4_563
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 3_506)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 4_436)
        XCTAssertEqual(details.designCapacityMilliampHours, 4_563)
    }

    func testReaderSkipsTransientZeroCurrentCapacityWhenLaterPhysicalValueExists() {
        let properties: [String: Any] = [
            "AppleRawCurrentCapacity": 0,
            "BatteryData": [
                "RemainingCapacity": 3_506,
                "FullChargeCapacity": 4_436,
                "DesignCapacity": 4_563
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 3_506)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 4_436)
        XCTAssertEqual(details.designCapacityMilliampHours, 4_563)
    }

    func testReaderFallsBackToLegacyCurrentCapacityWhenRawCurrentCapacityIsTransientZero() {
        let properties: [String: Any] = [
            "AppleRawCurrentCapacity": 0,
            "CurrentCapacity": 3_506,
            "AppleRawMaxCapacity": 4_436,
            "DesignCapacity": 4_563
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 3_506)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 4_436)
        XCTAssertEqual(details.designCapacityMilliampHours, 4_563)
    }

    func testReaderKeepsZeroCurrentCapacityWhenNoPositivePhysicalValueExists() {
        let properties: [String: Any] = [
            "AppleRawCurrentCapacity": 0,
            "BatteryData": [
                "FullChargeCapacity": 4_436,
                "DesignCapacity": 4_563
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 0)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 4_436)
        XCTAssertEqual(details.designCapacityMilliampHours, 4_563)
    }

    func testReaderDoesNotTreatPercentageShapedLegacyCapacityAsMilliampHoursAfterTransientZero() {
        let properties: [String: Any] = [
            "AppleRawCurrentCapacity": 0,
            "CurrentCapacity": 80,
            "AppleRawMaxCapacity": 4_436,
            "DesignCapacity": 4_563
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 0)
        XCTAssertEqual(details.fullChargeCapacityMilliampHours, 4_436)
        XCTAssertEqual(details.designCapacityMilliampHours, 4_563)
    }

    func testReaderSkipsAbsurdMetricCandidateAndUsesNextValidValue() {
        let properties: [String: Any] = [
            "CycleCount": Int.max,
            "Voltage": Int.max,
            "InstantAmperage": Int.max,
            "AdapterDetails": [
                "Watts": Int.max
            ],
            "LegacyBatteryInfo": [
                "Cycle Count": 120,
                "Voltage": 12_800,
                "Amperage": -1_500
            ],
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 96])
            ])
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.cycleCount, 120)
        XCTAssertEqual(details.voltageMillivolts, 12_800)
        XCTAssertEqual(details.signedCurrentMilliamps, -1_500)
        XCTAssertEqual(details.adapterMaxWatts, 96)
    }

    func testReaderParsesAdapterWattsFromMixedFoundationArray() {
        let properties: [String: Any] = [
            "AppleRawAdapterDetails": NSArray(array: [
                "not a dictionary",
                NSDictionary(dictionary: ["Voltage": 20]),
                NSDictionary(dictionary: ["Watts": 96])
            ])
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 96)
    }

    func testReaderPrefersRawAdapterWattsOverStaleAdapterDetails() {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 100
            ],
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 70])
            ]),
            "PowerTelemetryData": [
                "SystemPowerIn": 82_500,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderDerivesAdapterDetailsWattsWhenReportedWattsAreStaleHigh() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 100,
                "AdapterVoltage": 20_000,
                "Current": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderUsesBestAdapterIndexBeforeStaleRawAdapterEntry() throws {
        let properties: [String: Any] = [
            "BestAdapterIndex": 1,
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 100]),
                NSDictionary(dictionary: ["Watts": 70])
            ]),
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderRejectsCounterBackedSystemPowerInNearStaleAdapterCapability() {
        let properties: [String: Any] = [
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 100])
            ]),
            "PowerTelemetryData": [
                "SystemPowerIn": 99_800,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 100)
        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderRejectsCounterBackedHundredWattEchoSlightlyBelowAdapterCapability() {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 100
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 99_400,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 100)
        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderDerivesRawAdapterWattsBeforeUsingStaleAdapterDetails() {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 100
            ],
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: [
                    "Voltage": 20_000,
                    "Current": 3_500
                ])
            ]),
            "PowerTelemetryData": [
                "SystemPowerIn": 82_500,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderDerivesRawAdapterWattsWhenReportedRawWattsAreStaleHigh() throws {
        let properties: [String: Any] = [
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: [
                    "Watts": 100,
                    "AdapterVoltage": 20_000,
                    "Current": 3_500
                ])
            ]),
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderUsesLowerReportedAdapterPowerWhenRawDetailsAreStaleHigh() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 70
            ],
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 100])
            ]),
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderPrefersDerivedAdapterDetailsOverStaleLowRawAdapterWatts() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 70,
                "AdapterVoltage": 20_000,
                "Current": 3_500
            ],
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 45])
            ]),
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderPrefersNegotiatedAdapterPowerOverStaleHundredWattAdapterDetails() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 100
            ],
            "PowerDistribution": [
                "IPDInputPower": 70_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderDoesNotLetStaleHighNegotiatedPowerOverrideDerivedAdapterDetails() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 70,
                "AdapterVoltage": 20_000,
                "Current": 3_500
            ],
            "PowerDistribution": [
                "IPDInputPower": 100_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 5_000
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderUsesCorroboratedHigherNegotiatedPowerOverStaleLowDerivedAdapterDetails() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 70,
                "AdapterVoltage": 20_000,
                "Current": 3_500
            ],
            "PowerDistribution": [
                "IPDInputPower": 100_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 5_000
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 99_000,
                "SystemPowerInAccumulatorCount": 12_345,
                "SystemVoltageIn": 19_800,
                "SystemCurrentIn": 5_000
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 100)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 99, accuracy: 0.001)
    }

    func testReaderUsesNegotiatedInputPowerWhenVoltageAndCurrentContractAreMissing() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 100
            ],
            "PowerDistribution": [
                "IPDInputPower": 70_000
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderPrefersNegotiatedAdapterPowerOverStaleHundredWattRawAdapterDetails() throws {
        let properties: [String: Any] = [
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 100])
            ]),
            "PowerDistribution": [
                "IPDInputPower": 70_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderPrefersNegotiatedAdapterPowerOverStaleLowAdapterDetails() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 45
            ],
            "PowerDistribution": [
                "IPDInputPower": 70_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderPrefersNegotiatedAdapterPowerOverStaleLowRawAdapterDetails() throws {
        let properties: [String: Any] = [
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 45])
            ]),
            "PowerDistribution": [
                "IPDInputPower": 70_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderPrefersNegotiatedAdapterPowerOverAnyStaleHighRawAdapterDetails() throws {
        let properties: [String: Any] = [
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": 140])
            ]),
            "PowerDistribution": [
                "IPDInputPower": 70_000,
                "IPDInputVoltage": 20_000,
                "IPDInputCurrent": 3_500
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 82_500,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertNil(details.inputPowerWatts)
    }

    func testReaderKeepsReportedAdapterPowerWhenNegotiatedPowerOnlyDiffersByRounding() throws {
        let properties: [String: Any] = [
            "AdapterDetails": [
                "Watts": 70
            ],
            "PowerDistribution": [
                "IPDInputPower": 69_000
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 69_420,
                "SystemPowerInAccumulatorCount": 12_345
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertEqual(try XCTUnwrap(details.inputPowerWatts), 69.42, accuracy: 0.001)
    }

    func testReaderSkipsInvalidAdapterWattsInsideArrayCandidate() {
        let properties: [String: Any] = [
            "AppleRawAdapterDetails": NSArray(array: [
                NSDictionary(dictionary: ["Watts": Int.max]),
                NSDictionary(dictionary: ["Watts": 67])
            ])
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.adapterMaxWatts, 67)
    }

    func testReaderRejectsImpossibleUnsignedMetrics() {
        let properties: [String: Any] = [
            "AppleRawCurrentCapacity": Int.max,
            "AppleRawMaxCapacity": Int.max,
            "DesignCapacity": Int.max,
            "CycleCount": Int.max,
            "Voltage": 250_000,
            "InstantAmperage": Int.max,
            "AdapterDetails": [
                "Watts": Int.max
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertNil(details.currentChargeMilliampHours)
        XCTAssertNil(details.fullChargeCapacityMilliampHours)
        XCTAssertNil(details.designCapacityMilliampHours)
        XCTAssertNil(details.cycleCount)
        XCTAssertNil(details.voltageMillivolts)
        XCTAssertNil(details.signedCurrentMilliamps)
        XCTAssertNil(details.adapterMaxWatts)
    }

    func testReaderSkipsFractionalIntegerCandidates() {
        let properties: [String: Any] = [
            "AppleRawCurrentCapacity": 4_912.9,
            "BatteryData": [
                "RemainingCapacity": 3_506,
                "Voltage": 12_900.5
            ],
            "LegacyBatteryInfo": [
                "Voltage": 12_711
            ]
        ]

        let details = SmartBatteryReader().parse(properties: properties)

        XCTAssertEqual(details.currentChargeMilliampHours, 3_506)
        XCTAssertEqual(details.voltageMillivolts, 12_711)
    }

    func testSignedIntegerNormalizerHandlesUnsignedEncodedNegativeCurrent() {
        XCTAssertEqual(SignedIntegerNormalizer.normalize("18446744073709549095"), -2_521)
        XCTAssertEqual(SignedIntegerNormalizer.normalize(UInt64.max), -1)
    }

    func testSignedIntegerNormalizerRejectsBooleanNSNumberValues() {
        XCTAssertNil(SignedIntegerNormalizer.normalize(NSNumber(value: true)))
        XCTAssertNil(SignedIntegerNormalizer.normalize(NSNumber(value: false)))
    }

    func testSignedIntegerNormalizerRejectsNonFiniteFloatingPointStrings() {
        XCTAssertNil(SignedIntegerNormalizer.normalize("nan"))
        XCTAssertNil(SignedIntegerNormalizer.normalize("inf"))
        XCTAssertNil(SignedIntegerNormalizer.normalize(Double.infinity))
        XCTAssertNil(SignedIntegerNormalizer.normalize(Double.nan))
    }

    func testSignedIntegerNormalizerTrimsAndParsesIntegralFloatingPointStrings() {
        XCTAssertEqual(SignedIntegerNormalizer.normalize(" 42.0 "), 42)
        XCTAssertEqual(SignedIntegerNormalizer.normalize(42.0), 42)
        XCTAssertEqual(SignedIntegerNormalizer.normalize(Float(42.0)), 42)
        XCTAssertEqual(SignedIntegerNormalizer.normalize(NSNumber(value: 42.0)), 42)
    }

    func testSignedIntegerNormalizerRejectsFractionalFloatingPointValues() {
        XCTAssertNil(SignedIntegerNormalizer.normalize(" 42.9 "))
        XCTAssertNil(SignedIntegerNormalizer.normalize(42.9))
        XCTAssertNil(SignedIntegerNormalizer.normalize(Float(42.5)))
        XCTAssertNil(SignedIntegerNormalizer.normalize(NSNumber(value: 42.9)))
    }

    private func packedManufactureDate(year: Int, month: Int, day: Int) -> Int {
        ((year - 1980) << 9) | (month << 5) | day
    }
}
