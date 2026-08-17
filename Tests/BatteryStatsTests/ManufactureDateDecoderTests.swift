import XCTest
@testable import BatteryStats

final class ManufactureDateDecoderTests: XCTestCase {
    func testDecodeValidPackedManufactureDate() throws {
        let date = try XCTUnwrap(ManufactureDateDecoder.decode(rawValue: 22_316))

        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 12)
    }

    func testDecodeUsesStableUTCCalendarByDefault() throws {
        let januaryFirst2023 = (43 << 9) | (1 << 5) | 1
        let date = try XCTUnwrap(ManufactureDateDecoder.decode(rawValue: januaryFirst2023))
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    func testInvalidMonthReturnsNil() {
        XCTAssertNil(ManufactureDateDecoder.decode(rawValue: 22_945))
    }

    func testInvalidDayForDecodedMonthReturnsNil() {
        let aprilThirtyFirst = (43 << 9) | (4 << 5) | 31

        XCTAssertNil(ManufactureDateDecoder.decode(rawValue: aprilThirtyFirst))
    }

    func testRejectsValuesOutsidePackedDateRangeBeforeMasking() {
        let validDate = 22_316

        XCTAssertNotNil(ManufactureDateDecoder.decode(rawValue: validDate))
        XCTAssertNil(ManufactureDateDecoder.decode(rawValue: -65_503))
        XCTAssertNil(ManufactureDateDecoder.decode(rawValue: validDate + 65_536))
        XCTAssertNil(ManufactureDateDecoder.decode(rawValue: Int.max))
    }

    func testRejectsPreMacBookEraPackedDates() {
        let decemberThirtyFirst2005 = (25 << 9) | (12 << 5) | 31
        let januaryFirst2006 = (26 << 9) | (1 << 5) | 1

        XCTAssertNil(ManufactureDateDecoder.decode(rawValue: decemberThirtyFirst2005))
        XCTAssertNotNil(ManufactureDateDecoder.decode(rawValue: januaryFirst2006))
    }

    func testRejectsFuturePackedDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let latestDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)))
        let januaryFirst2027 = (47 << 9) | (1 << 5) | 1

        XCTAssertNil(ManufactureDateDecoder.decode(rawValue: januaryFirst2027, calendar: calendar, latestDate: latestDate))
    }

}
