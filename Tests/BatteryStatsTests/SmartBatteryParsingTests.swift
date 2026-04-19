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
        XCTAssertEqual(details.adapterMaxWatts, 70)
        XCTAssertNotNil(details.manufactureDate)
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

    func testSignedIntegerNormalizerHandlesUnsignedEncodedNegativeCurrent() {
        XCTAssertEqual(SignedIntegerNormalizer.normalize("18446744073709549095"), -2_521)
        XCTAssertEqual(SignedIntegerNormalizer.normalize(UInt64.max), -1)
    }
}
