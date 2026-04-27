import XCTest
@testable import BatteryStats

@MainActor
final class BatteryMonitorTests: XCTestCase {
    func testRefreshCoalescesRequestsWhileAReadIsInFlight() async {
        let reader = StubBatteryReader(
            delayNanoseconds: 30_000_000,
            snapshots: [.previewDischarging, .previewCharging]
        )
        let monitor = BatteryMonitor(reader: makeClient(reader))

        monitor.refresh()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        let requestCount = await reader.requestCount
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
    }

    func testRefreshDuringInFlightAddsOnlyOneFollowUpRead() async {
        let reader = StubBatteryReader(
            delayNanoseconds: 30_000_000,
            snapshots: [.previewDischarging, .previewCharging, .previewDischarging]
        )
        let monitor = BatteryMonitor(reader: makeClient(reader))

        monitor.refresh()
        try? await Task.sleep(nanoseconds: 5_000_000)
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        let requestCount = await reader.requestCount
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
    }

    func testStandardRefreshDoesNotRequestDiagnostics() async {
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        let monitor = BatteryMonitor(reader: makeClient(reader))

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard])
    }

    func testRawSnapshotCopyRequestsDiagnosticsOnDemand() async {
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        let monitor = BatteryMonitor(reader: makeClient(reader))

        monitor.copyRawSnapshot()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.diagnostics])
    }

    func testMonitoringDemandCanDisableEnergyChangeProbe() {
        let policy = BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced)

        XCTAssertTrue(policy.usesEnergyChangeProbe(for: BatteryMonitoringDemand(needsEnergyChangeAwareness: true)))
        XCTAssertFalse(policy.usesEnergyChangeProbe(for: BatteryMonitoringDemand(needsEnergyChangeAwareness: false)))
    }

    private func makeClient(_ reader: StubBatteryReader) -> BatteryReadingClient {
        BatteryReadingClient(
            read: { date, options in
                await reader.read(at: date, options: options)
            },
            makeNotificationToken: { _ in
                nil
            }
        )
    }
}

private actor StubBatteryReader {
    private let delayNanoseconds: UInt64
    private var snapshots: [BatterySnapshot]
    private(set) var requests: [BatteryReadOptions] = []

    init(delayNanoseconds: UInt64 = 0, snapshots: [BatterySnapshot]) {
        self.delayNanoseconds = delayNanoseconds
        self.snapshots = snapshots
    }

    var requestCount: Int {
        requests.count
    }

    func read(at date: Date, options: BatteryReadOptions) async -> BatteryReadResult {
        requests.append(options)

        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        let snapshot = snapshots.isEmpty ? BatterySnapshot.previewDischarging : snapshots.removeFirst()
        return BatteryReadResult(
            snapshot: snapshot,
            rawSnapshotText: options.includesDiagnostics ? "raw" : nil,
            parsedSnapshotText: options.includesDiagnostics ? "parsed" : nil
        )
    }
}
