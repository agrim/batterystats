import XCTest
@testable import BatteryStats

final class BatteryFreshnessFormattingTests: XCTestCase {
    func testRefreshingTextTakesPriority() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(lastUpdated: now, now: now, isRefreshing: true),
            "Refreshing..."
        )
    }

    func testWaitingTextWhenNoUpdateHasPublished() {
        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(lastUpdated: nil, now: Date(), isRefreshing: false),
            "Waiting for battery change"
        )
    }

    func testRecentUpdateText() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let lastUpdated = now.addingTimeInterval(-20)

        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(lastUpdated: lastUpdated, now: now, isRefreshing: false),
            "Live - Updated just now"
        )
    }

    func testMinuteHourAndDayUpdateText() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(
                lastUpdated: now.addingTimeInterval(-125),
                now: now,
                isRefreshing: false
            ),
            "Live - Updated 2m ago"
        )
        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(
                lastUpdated: now.addingTimeInterval(-(2 * 60 * 60)),
                now: now,
                isRefreshing: false
            ),
            "Live - Updated 2h ago"
        )
        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(
                lastUpdated: now.addingTimeInterval(-(3 * 24 * 60 * 60)),
                now: now,
                isRefreshing: false
            ),
            "Live - Updated 3d ago"
        )
    }
}
