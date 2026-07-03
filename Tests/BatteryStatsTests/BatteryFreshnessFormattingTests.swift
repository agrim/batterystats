import XCTest
@testable import BatteryStats

final class BatteryFreshnessFormattingTests: XCTestCase {
    func testFreshnessViewDefersPulseUntilRefreshCompletes() throws {
        let source = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatteryFreshnessView.swift")

        XCTAssertTrue(source.contains(".task(id: pulseTrigger)"))
        XCTAssertTrue(source.contains("await runPulse()"))
        XCTAssertTrue(source.contains("@MainActor\n    private func runPulse() async"))
        XCTAssertFalse(source.contains("private func schedulePulse()"))
        XCTAssertFalse(source.contains("private func schedulePulseCancellation()"))
        XCTAssertFalse(source.contains("pulseUpdateTask"))
        XCTAssertFalse(source.contains("pulseTask"))
        XCTAssertTrue(source.contains("await Task.yield()"))
        XCTAssertTrue(source.contains("guard isRefreshing == false,\n              BatteryFreshnessFormatting.hasUsableUpdate"))
        XCTAssertTrue(source.contains("BatteryFreshnessFormatting.hasUsableUpdate(lastUpdated: lastUpdated, now: Date())"))
    }

    func testFreshnessViewRearmsPulseWhenReduceMotionTurnsOff() throws {
        let source = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatteryFreshnessView.swift")

        XCTAssertTrue(source.contains("private struct BatteryFreshnessPulseTrigger: Equatable"))
        XCTAssertTrue(source.contains("reduceMotion: reduceMotion"))
        XCTAssertTrue(source.contains("let reduceMotion: Bool"))
        XCTAssertFalse(source.contains(".onChange(of: reduceMotion)"))
    }

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

    func testSmallFutureClockSkewStillLooksFresh() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let lastUpdated = now.addingTimeInterval(30)

        XCTAssertTrue(BatteryFreshnessFormatting.hasUsableUpdate(lastUpdated: lastUpdated, now: now))
        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(lastUpdated: lastUpdated, now: now, isRefreshing: false),
            "Live - Updated just now"
        )
    }

    func testFutureUpdateBeyondClockSkewDoesNotLookFresh() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let lastUpdated = now.addingTimeInterval(120)

        XCTAssertFalse(BatteryFreshnessFormatting.hasUsableUpdate(lastUpdated: lastUpdated, now: now))
        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(lastUpdated: lastUpdated, now: now, isRefreshing: false),
            "Waiting for battery change"
        )
    }

    func testMinuteUpdateText() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(
                lastUpdated: now.addingTimeInterval(-125),
                now: now,
                isRefreshing: false
            ),
            "Live - Updated 2m ago"
        )
    }

    func testStaleUpdateTextDoesNotClaimToBeLive() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        XCTAssertFalse(BatteryFreshnessFormatting.hasUsableUpdate(
            lastUpdated: now.addingTimeInterval(-(12 * 60)),
            now: now
        ))
        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(
                lastUpdated: now.addingTimeInterval(-(12 * 60)),
                now: now,
                isRefreshing: false
            ),
            "Stale - Updated 12m ago"
        )
        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(
                lastUpdated: now.addingTimeInterval(-(2 * 60 * 60)),
                now: now,
                isRefreshing: false
            ),
            "Stale - Updated 2h ago"
        )
        XCTAssertEqual(
            BatteryFreshnessFormatting.statusText(
                lastUpdated: now.addingTimeInterval(-(3 * 24 * 60 * 60)),
                now: now,
                isRefreshing: false
            ),
            "Stale - Updated 3d ago"
        )
    }

    func testNextStatusChangeDateWakesAtFirstVisibleMinuteBoundary() {
        let lastUpdated = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = lastUpdated.addingTimeInterval(20)

        XCTAssertEqual(
            BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: lastUpdated,
                now: now,
                isRefreshing: false
            ),
            lastUpdated.addingTimeInterval(60)
        )
    }

    func testNextStatusChangeDateWakesAtNextRelativeMinuteBoundary() {
        let lastUpdated = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = lastUpdated.addingTimeInterval(125)

        XCTAssertEqual(
            BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: lastUpdated,
                now: now,
                isRefreshing: false
            ),
            lastUpdated.addingTimeInterval(180)
        )
    }

    func testNextStatusChangeDateWakesAtStaleBoundaryWithoutMinutePolling() {
        let lastUpdated = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = lastUpdated.addingTimeInterval((10 * 60) - 5)

        XCTAssertTrue(BatteryFreshnessFormatting.hasUsableUpdate(lastUpdated: lastUpdated, now: now))
        XCTAssertEqual(
            BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: lastUpdated,
                now: now,
                isRefreshing: false
            ),
            lastUpdated.addingTimeInterval(10 * 60)
        )
    }

    func testNextStatusChangeDateDoesNotMissStaleTransitionAtExactLiveBoundary() {
        let lastUpdated = Date(timeIntervalSinceReferenceDate: 1_000)
        let liveBoundary = lastUpdated.addingTimeInterval(10 * 60)

        XCTAssertTrue(BatteryFreshnessFormatting.hasUsableUpdate(lastUpdated: lastUpdated, now: liveBoundary))
        XCTAssertEqual(
            BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: lastUpdated,
                now: liveBoundary,
                isRefreshing: false
            ),
            liveBoundary.addingTimeInterval(1)
        )
    }

    func testNextStatusChangeDateUsesHourlyBoundariesAfterOneHour() {
        let lastUpdated = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = lastUpdated.addingTimeInterval((2 * 60 * 60) + 120)

        XCTAssertEqual(
            BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: lastUpdated,
                now: now,
                isRefreshing: false
            ),
            lastUpdated.addingTimeInterval(3 * 60 * 60)
        )
    }

    func testNextStatusChangeDateHandlesFutureClockSkewBoundary() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let lastUpdated = now.addingTimeInterval(120)

        XCTAssertEqual(
            BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: lastUpdated,
                now: now,
                isRefreshing: false
            ),
            lastUpdated.addingTimeInterval(-BatterySnapshotFreshnessPolicy.allowableFutureSkew)
        )
    }

    func testNextStatusChangeDateFallsBackToLowFrequencyWhenStatusCannotAge() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertEqual(
            BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: nil,
                now: now,
                isRefreshing: false
            ),
            now.addingTimeInterval(60)
        )
        XCTAssertEqual(
            BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: now,
                now: now,
                isRefreshing: true
            ),
            now.addingTimeInterval(60)
        )
    }

}
