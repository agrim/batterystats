import XCTest
@testable import BatteryStats

final class PowerSourceReaderTests: XCTestCase {
    func testPowerSourceNotificationsUseCommonRunLoopModes() {
        XCTAssertEqual(PowerSourceReader.NotificationToken.runLoopMode, .commonModes)
    }

    func testExternalPowerSourceIsNotReportedAsInternalBattery() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "UPS",
                "Transport Type": "USB",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": true
            ]
        ]))

        XCTAssertFalse(snapshot.isInternalBattery)
        XCTAssertEqual(snapshot.stateOfChargePercent, 80)
    }

    func testInternalBatteryIsPreferredOverOtherPowerSources() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "UPS",
                "Transport Type": "USB",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": true
            ],
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 42,
                "Max Capacity": 100,
                "Is Present": true
            ]
        ]))

        XCTAssertTrue(snapshot.isInternalBattery)
        XCTAssertEqual(snapshot.stateOfChargePercent, 42)
    }

    func testPresentInternalBatteryIsPreferredOverStaleAbsentInternalBattery() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 0,
                "Max Capacity": 100,
                "Is Present": false
            ],
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 74,
                "Max Capacity": 100,
                "Is Present": true
            ]
        ]))

        XCTAssertTrue(snapshot.isInternalBattery)
        XCTAssertTrue(snapshot.isPresent)
        XCTAssertEqual(snapshot.stateOfChargePercent, 74)
    }

    func testPresentPowerSourceIsPreferredOverOnlyStaleAbsentInternalBattery() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 0,
                "Max Capacity": 100,
                "Is Present": false
            ],
            [
                "Type": "UPS",
                "Transport Type": "USB",
                "Current Capacity": 83,
                "Max Capacity": 100,
                "Is Present": true
            ]
        ]))

        XCTAssertFalse(snapshot.isInternalBattery)
        XCTAssertTrue(snapshot.isPresent)
        XCTAssertEqual(snapshot.stateOfChargePercent, 83)
    }

    func testInternalBatteryDetectionToleratesDisplayStyleTypeStrings() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "UPS",
                "Transport Type": "USB",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": true
            ],
            [
                "Type": " internal battery ",
                "Transport Type": "Built In",
                "Current Capacity": 42,
                "Max Capacity": 100,
                "Is Present": true
            ]
        ]))

        XCTAssertTrue(snapshot.isInternalBattery)
        XCTAssertEqual(snapshot.stateOfChargePercent, 42)
    }

    func testInternalBatteryDetectionToleratesSpacedTransportTypeStrings() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "UPS",
                "Transport Type": "USB",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": true
            ],
            [
                "Type": "Battery",
                "Transport Type": " internal ",
                "Current Capacity": 55,
                "Max Capacity": 100,
                "Is Present": true
            ]
        ]))

        XCTAssertTrue(snapshot.isInternalBattery)
        XCTAssertEqual(try XCTUnwrap(snapshot.stateOfChargePercent), 55, accuracy: 0.001)
    }

    func testPublicBatteryPercentRejectsImpossibleCapacityRatios() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 106,
                "Max Capacity": 100,
                "Is Present": true
            ]
        ]))

        XCTAssertNil(snapshot.stateOfChargePercent)
    }

    func testPublicBatteryPercentRejectsAbsurdCapacityValuesBeforeRatioMath() throws {
        let hugeMaximumSnapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 5_000,
                "Max Capacity": Int.max,
                "Is Present": true
            ]
        ]))
        let hugeCurrentSnapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": Int.max,
                "Max Capacity": Int.max,
                "Is Present": true
            ]
        ]))

        XCTAssertNil(hugeMaximumSnapshot.stateOfChargePercent)
        XCTAssertNil(hugeCurrentSnapshot.stateOfChargePercent)
    }

    func testPublicBatteryPercentClampsSmallOverfullCapacityRatio() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 105,
                "Max Capacity": 100,
                "Is Present": true
            ]
        ]))

        XCTAssertEqual(snapshot.stateOfChargePercent, 100)
    }

    func testPublicBatteryTimesKeepPlausibleDurations() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": true,
                "Time to Empty": 245,
                "Time to Full Charge": 70
            ]
        ]))

        XCTAssertEqual(snapshot.systemTimeRemainingMinutes, 245)
        XCTAssertEqual(snapshot.timeToFullMinutes, 70)
    }

    func testPublicBatteryTimesRejectImpossibleDurations() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": true,
                "Time to Empty": -1,
                "Time to Full Charge": Int.max
            ]
        ]))

        XCTAssertNil(snapshot.systemTimeRemainingMinutes)
        XCTAssertNil(snapshot.timeToFullMinutes)
    }

    func testBooleanFlagsAcceptActualCFBooleanValues() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": NSNumber(value: true),
                "Is Charging": NSNumber(value: true),
                "Is Charged": NSNumber(value: false)
            ]
        ]))

        XCTAssertTrue(snapshot.isPresent)
        XCTAssertTrue(snapshot.isCharging)
        XCTAssertFalse(snapshot.isCharged)
    }

    func testBooleanFlagsAcceptNativeSwiftBoolValues() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": true,
                "Is Charging": true,
                "Is Charged": false
            ]
        ]))

        XCTAssertTrue(snapshot.isPresent)
        XCTAssertTrue(snapshot.isCharging)
        XCTAssertFalse(snapshot.isCharged)
        XCTAssertTrue(snapshot.isExternalPowerConnected)
    }

    func testChargingFlagImpliesExternalPowerWhenPowerSourceStateIsMissing() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": NSNumber(value: true),
                "Is Charging": NSNumber(value: true)
            ]
        ]))

        XCTAssertTrue(snapshot.isCharging)
        XCTAssertTrue(snapshot.isExternalPowerConnected)
    }

    func testChargedFlagImpliesExternalPowerWhenPowerSourceStateIsMissing() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 100,
                "Max Capacity": 100,
                "Is Present": NSNumber(value: true),
                "Is Charged": NSNumber(value: true)
            ]
        ]))

        XCTAssertTrue(snapshot.isCharged)
        XCTAssertTrue(snapshot.isExternalPowerConnected)
    }

    func testExplicitBatteryPowerOverridesStaleChargingFlag() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": NSNumber(value: true),
                "Is Charging": NSNumber(value: true),
                "Power Source State": "Battery Power"
            ]
        ]))

        XCTAssertTrue(snapshot.isCharging)
        XCTAssertFalse(snapshot.isExternalPowerConnected)
    }

    func testExplicitBatteryPowerOverridesStaleChargedFlag() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 100,
                "Max Capacity": 100,
                "Is Present": NSNumber(value: true),
                "Is Charged": NSNumber(value: true),
                "Power Source State": " battery power "
            ]
        ]))

        XCTAssertTrue(snapshot.isCharged)
        XCTAssertFalse(snapshot.isExternalPowerConnected)
    }

    func testACPowerSourceStateIsWhitespaceAndCaseInsensitive() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": NSNumber(value: true),
                "Is Charging": NSNumber(value: false),
                "Is Charged": NSNumber(value: false),
                "Power Source State": " ac power "
            ]
        ]))

        XCTAssertFalse(snapshot.isCharging)
        XCTAssertFalse(snapshot.isCharged)
        XCTAssertTrue(snapshot.isExternalPowerConnected)
    }

    func testBooleanFlagsAcceptPlainNumericZeroOneValues() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": NSNumber(value: 0),
                "Is Charging": NSNumber(value: 1),
                "Is Charged": NSNumber(value: 1)
            ]
        ]))

        XCTAssertFalse(snapshot.isPresent)
        XCTAssertTrue(snapshot.isCharging)
        XCTAssertTrue(snapshot.isCharged)
        XCTAssertTrue(snapshot.isExternalPowerConnected)
    }

    func testBooleanFlagsRejectNonBooleanNumericNSNumberValues() throws {
        let snapshot = try XCTUnwrap(PowerSourceReader.snapshot(from: [
            [
                "Type": "InternalBattery",
                "Transport Type": "Internal",
                "Current Capacity": 80,
                "Max Capacity": 100,
                "Is Present": NSNumber(value: 2),
                "Is Charging": NSNumber(value: -1),
                "Is Charged": NSNumber(value: 0.5)
            ]
        ]))

        XCTAssertTrue(snapshot.isPresent)
        XCTAssertFalse(snapshot.isCharging)
        XCTAssertFalse(snapshot.isCharged)
        XCTAssertFalse(snapshot.isExternalPowerConnected)
    }
}
