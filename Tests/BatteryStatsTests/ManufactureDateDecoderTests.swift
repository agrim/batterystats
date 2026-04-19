import XCTest
@testable import BatteryStats

final class ManufactureDateDecoderTests: XCTestCase {
    func testDecodeValidPackedManufactureDate() throws {
        let date = try XCTUnwrap(ManufactureDateDecoder.decode(rawValue: 22_316))

        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 12)
    }

    func testInvalidMonthReturnsNil() {
        XCTAssertNil(ManufactureDateDecoder.decode(rawValue: 22_945))
    }
}
