import XCTest
@testable import BatteryStats

final class FormatterTests: XCTestCase {
    func testFormatsMilliampHours() {
        XCTAssertEqual(BatteryFormatting.milliampHours(5_338), "5,338 mAh")
    }

    func testFormatsPercentWithOneDecimal() {
        XCTAssertEqual(BatteryFormatting.percent(81.38, decimals: 1), "81.4%")
    }

    func testFormatsFahrenheitTemperature() {
        XCTAssertEqual(BatteryFormatting.temperature(34.2, unitPreference: .fahrenheit), "93.6 °F")
    }

    func testFormatsAge() {
        let formattedAge = BatteryFormatting.age(DateComponents(year: 2, month: 3))

        XCTAssertTrue(formattedAge.contains("2"))
        XCTAssertTrue(formattedAge.contains("3"))
    }
}
