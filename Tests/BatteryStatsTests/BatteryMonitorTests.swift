import XCTest
@testable import BatteryStats

@MainActor
final class BatteryMonitorTests: XCTestCase {
    func testMonitoringTimersUseCommonRunLoopMode() {
        XCTAssertEqual(BatteryMonitor.timerRunLoopMode, .common)
    }

    func testRefreshCoalescesRequestsWhileAReadIsInFlight() async {
        let reader = StubBatteryReader(
            delayNanoseconds: 30_000_000,
            snapshots: [.previewDischarging, .previewCharging]
        )
        let monitor = makeMonitor(reader)

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
        let monitor = makeMonitor(reader)

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
        let monitor = makeMonitor(reader)

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard])
    }

    func testRefreshDoesNotRestoreRateBasedTimeForIdlePowerStates() async {
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .connectedNotCharging,
            isCharging: false,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 39,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )
        let reader = StubBatteryReader(snapshots: [snapshot])
        let monitor = makeMonitor(reader)

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(monitor.snapshot?.powerState, .connectedNotCharging)
        XCTAssertNil(monitor.snapshot?.rateBasedTimeRemainingMinutes)
        XCTAssertNil(monitor.snapshot?.displayedTimeMinutes)
    }

    func testRefreshRestoresRateBasedTimeForConnectedDischarging() async {
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .connectedDischarging,
            isCharging: false,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 39,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )
        let reader = StubBatteryReader(snapshots: [snapshot])
        let monitor = makeMonitor(reader)

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(monitor.snapshot?.powerState, .connectedDischarging)
        XCTAssertEqual(monitor.snapshot?.rateBasedTimeRemainingMinutes, 150)
        XCTAssertEqual(monitor.snapshot?.displayedTimeMinutes, 150)
    }

    func testStartIsIdempotent() async {
        let reader = StubBatteryReader(
            delayNanoseconds: 30_000_000,
            snapshots: [.previewDischarging, .previewCharging]
        )
        let monitor = makeMonitor(reader)

        monitor.start()
        monitor.start()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard])
    }

    func testVisibleSurfaceRefreshDoesNotStartInactiveMonitor() async {
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        let monitor = makeMonitor(reader)

        monitor.refreshForVisibleSurface()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [])
        XCTAssertNil(monitor.snapshot)
    }

    func testVisibleSurfaceRefreshUpdatesAlreadyStartedMonitor() async {
        let reader = StubBatteryReader(
            snapshots: [.previewDischarging, .previewCharging]
        )
        let monitor = makeMonitor(reader)

        monitor.start()
        await monitor.waitForIdleForTesting()

        monitor.refreshForVisibleSurface()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
    }

    func testVisibleSurfaceRefreshQueuesFollowUpWhileReadIsPending() async {
        let reader = StubBatteryReader(
            delayNanoseconds: 30_000_000,
            snapshots: [.previewDischarging, .previewCharging]
        )
        let monitor = makeMonitor(reader)

        monitor.start()
        monitor.refreshForVisibleSurface()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
    }

    func testStopCancelsInFlightRefreshWithoutPublishingSnapshot() async {
        let reader = StubBatteryReader(
            delayNanoseconds: 30_000_000,
            snapshots: [.previewDischarging]
        )
        let monitor = makeMonitor(reader)

        monitor.refresh()
        try? await Task.sleep(nanoseconds: 5_000_000)
        monitor.stop()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard])
        XCTAssertNil(monitor.snapshot)
        XCTAssertEqual(monitor.availabilityState, .loading)
        XCTAssertFalse(monitor.isRefreshing)
    }

    func testPowerSourceNotificationAfterStopDoesNotStartRefresh() async {
        let reader = StubBatteryReader(
            snapshots: [.previewDischarging, .previewCharging]
        )
        var notificationHandler: (@Sendable () -> Void)?
        let monitor = BatteryMonitor(
            reader: BatteryReadingClient(
                read: { date, options in
                    await reader.read(at: date, options: options)
                },
                makeNotificationToken: { handler in
                    notificationHandler = handler
                    return nil
                }
            ),
            widgetTimelineReloader: {}
        )

        monitor.start()
        await monitor.waitForIdleForTesting()
        monitor.stop()
        notificationHandler?()
        await Task.yield()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)
    }

    func testRestartDuringInFlightRefreshStartsFreshRead() async {
        let reader = StubBatteryReader(
            delayNanoseconds: 30_000_000,
            snapshots: [.previewDischarging, .previewCharging]
        )
        let monitor = makeMonitor(reader)

        monitor.start()
        try? await Task.sleep(nanoseconds: 5_000_000)
        monitor.stop()
        monitor.start()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
        XCTAssertFalse(monitor.isRefreshing)
    }

    func testRawSnapshotCopyRequestsDiagnosticsOnDemand() async {
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        let monitor = makeMonitor(reader)

        monitor.copyRawSnapshot()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.diagnostics])
    }

    func testRawSnapshotCopyPublishesDiagnosticsSnapshot() async {
        let reader = ControlledDiagnosticsReader()
        var copiedStrings: [String] = []
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let diagnosticsDate = Date(timeIntervalSince1970: 2_000)
        var readDates = [refreshDate, diagnosticsDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60,
            now: { readDates.removeFirst() }
        )

        monitor.refresh()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(
            at: 1,
            snapshot: .previewCharging,
            rawSnapshotText: "charging raw"
        )
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(copiedStrings, ["charging raw"])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
        XCTAssertEqual(monitor.snapshot?.timestamp, diagnosticsDate)
        XCTAssertEqual(reader.requestDates, [refreshDate, diagnosticsDate])
        XCTAssertEqual(reloadCount, 2)

        monitor.copyParsedSnapshot()

        XCTAssertTrue(copiedStrings.last?.contains("Power state: Charging") == true)
    }

    func testOlderRefreshCompletionDoesNotOverwriteNewerDiagnosticsSnapshot() async {
        let reader = ControlledDiagnosticsReader()
        var copiedStrings: [String] = []
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60
        )

        monitor.refresh()
        await reader.waitForRequestCount(1)
        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(2)

        reader.resumeRequest(
            at: 1,
            snapshot: .previewCharging,
            rawSnapshotText: "newer raw"
        )
        try? await Task.sleep(nanoseconds: 5_000_000)

        XCTAssertEqual(monitor.snapshot?.powerState, .charging)

        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reader.requests, [.standard, .diagnostics])
        XCTAssertEqual(copiedStrings, ["newer raw"])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
        XCTAssertEqual(reloadCount, 1)
    }

    func testRawSnapshotCopyTracksLatestDiagnosticsInFlightState() async {
        let reader = ControlledDiagnosticsReader()
        var copiedStrings: [String] = []
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {}
        )

        XCTAssertFalse(monitor.isCopyingRawSnapshot)

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(1)

        XCTAssertTrue(monitor.isCopyingRawSnapshot)

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 0, rawSnapshotText: "first")
        await Task.yield()

        XCTAssertTrue(monitor.isCopyingRawSnapshot)
        XCTAssertTrue(copiedStrings.isEmpty)

        reader.resumeRequest(at: 1, rawSnapshotText: "second")
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(monitor.isCopyingRawSnapshot)
        XCTAssertEqual(copiedStrings, ["second"])
    }

    func testRawSnapshotCopyRefreshesParsedFallbackFromDiagnostics() async {
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        var copiedStrings: [String] = []
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {}
        )

        monitor.copyRawSnapshot()
        await monitor.waitForIdleForTesting()
        XCTAssertEqual(copiedStrings, ["raw"])

        monitor.copyParsedSnapshot()

        XCTAssertEqual(copiedStrings.first, "raw")
        XCTAssertTrue(copiedStrings.last?.contains("Power state: On Battery") == true)
    }

    func testRawSnapshotCopyDoesNotPasteStaleRawTextWhenUnsupported() async {
        let reader = ControlledDiagnosticsReader()
        var copiedStrings: [String] = []
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {}
        )

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(
            at: 0,
            snapshot: .previewDischarging,
            rawSnapshotText: "old raw",
            parsedSnapshotText: "old parsed"
        )
        await monitor.waitForIdleForTesting()

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: nil)
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(copiedStrings, [
            "old raw",
            "No supported internal battery is currently available."
        ])
    }

    func testRawSnapshotCopyUnsupportedDiagnosticsDoesNotClearPublishedSnapshot() async throws {
        let reader = ControlledDiagnosticsReader()
        let store = try makeWidgetSnapshotStore()
        var copiedStrings: [String] = []
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let diagnosticsDate = Date(timeIntervalSince1970: 1_060)
        var readDates = [refreshDate, diagnosticsDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetSnapshotStore: store,
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60,
            now: { readDates.removeFirst() }
        )

        monitor.refresh()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        let storedSnapshot = try XCTUnwrap(store.snapshot(now: refreshDate.addingTimeInterval(30), maximumAge: 60))
        XCTAssertEqual(storedSnapshot.powerState, .onBattery)

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: nil)
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(copiedStrings, ["No supported internal battery is currently available."])
        XCTAssertEqual(monitor.availabilityState, .available)
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)
        XCTAssertEqual(monitor.snapshot?.timestamp, refreshDate)
        XCTAssertEqual(reloadCount, 1)

        let retainedSnapshot = try XCTUnwrap(store.snapshot(now: refreshDate.addingTimeInterval(30), maximumAge: 60))
        XCTAssertEqual(retainedSnapshot.powerState, .onBattery)

        monitor.copyParsedSnapshot()
        XCTAssertTrue(copiedStrings.last?.contains("Power state: On Battery") == true)
    }

    func testRawSnapshotCopyDoesNotPasteStaleRawTextWhenRawDiagnosticsAreUnavailable() async {
        let reader = ControlledDiagnosticsReader()
        var copiedStrings: [String] = []
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {}
        )

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(
            at: 0,
            snapshot: .previewDischarging,
            rawSnapshotText: "old raw",
            parsedSnapshotText: "old parsed"
        )
        await monitor.waitForIdleForTesting()

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(
            at: 1,
            snapshot: .previewCharging,
            rawSnapshotText: nil,
            parsedSnapshotText: "new parsed"
        )
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(copiedStrings, [
            "old raw",
            "Raw battery diagnostics are unavailable for the latest snapshot."
        ])

        monitor.copyParsedSnapshot()
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
        XCTAssertTrue(copiedStrings.last?.contains("Power state: Charging") == true)
    }

    func testUnsupportedRefreshClearsParsedCopyFallback() async {
        let reader = ControlledDiagnosticsReader()
        var copiedStrings: [String] = []
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {}
        )

        monitor.refresh()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        monitor.copyParsedSnapshot()

        monitor.refresh()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: nil)
        await monitor.waitForIdleForTesting()

        monitor.copyParsedSnapshot()

        XCTAssertTrue(copiedStrings.first?.contains("State of charge") == true)
        XCTAssertEqual(copiedStrings.last, "Unsupported")
    }

    func testParsedSnapshotCopyIsDisabledUntilAReadableStatePublishes() async {
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        var copiedStrings: [String] = []
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {}
        )

        XCTAssertFalse(monitor.canCopyParsedSnapshot)
        monitor.copyParsedSnapshot()
        XCTAssertTrue(copiedStrings.isEmpty)

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertTrue(monitor.canCopyParsedSnapshot)
        monitor.copyParsedSnapshot()
        XCTAssertEqual(copiedStrings.count, 1)
        XCTAssertTrue(copiedStrings.first?.contains("State of charge") == true)
    }

    func testUnsupportedRefreshStillAllowsParsedUnsupportedCopy() async {
        let reader = ControlledDiagnosticsReader()
        var copiedStrings: [String] = []
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {}
        )

        monitor.refresh()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: nil)
        await monitor.waitForIdleForTesting()

        XCTAssertTrue(monitor.canCopyParsedSnapshot)
        monitor.copyParsedSnapshot()
        XCTAssertEqual(copiedStrings, ["Unsupported"])
    }

    func testRawSnapshotCopyIgnoresStaleDiagnosticsTasks() async {
        let reader = ControlledDiagnosticsReader()
        var copiedStrings: [String] = []
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            pasteboardCopy: { copiedStrings.append($0) },
            widgetTimelineReloader: {}
        )

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(1)
        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(2)

        reader.resumeRequest(at: 0, rawSnapshotText: "first")
        await Task.yield()

        monitor.copyRawSnapshot()
        await reader.waitForRequestCount(3)

        reader.resumeRequest(at: 2, rawSnapshotText: "third")
        await monitor.waitForIdleForTesting()
        reader.resumeRequest(at: 1, rawSnapshotText: "second")
        await Task.yield()

        XCTAssertEqual(copiedStrings, ["third"])
    }

    func testMonitoringDemandCanDisableEnergyChangeProbe() {
        let policy = BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced)

        XCTAssertTrue(policy.usesEnergyChangeProbe(for: BatteryMonitoringDemand(needsEnergyChangeAwareness: true)))
        XCTAssertFalse(policy.usesEnergyChangeProbe(for: BatteryMonitoringDemand(needsEnergyChangeAwareness: false)))
    }

    func testDefaultMonitoringDemandKeepsEnergyProbeOffForBareMonitor() async {
        let reader = ControlledDiagnosticsReader()
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {}
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await Task.yield()

        XCTAssertEqual(reader.requests, [.standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)
    }

    func testEnergyProbeDoesNotRunWhenBatteryIsUnsupported() async {
        let reader = ControlledDiagnosticsReader()
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {}
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: nil)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await Task.yield()

        XCTAssertEqual(reader.requests, [.standard])
        XCTAssertEqual(monitor.availabilityState, .unsupported)
    }

    func testEnergyProbeMissingSnapshotClearsCurrentBatteryState() async throws {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let store = try makeWidgetSnapshotStore()
        let publicationDate = Date(timeIntervalSince1970: 1_000)
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetSnapshotStore: store,
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { publicationDate }
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: nil)
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.availabilityState, .unsupported)
        XCTAssertNil(monitor.snapshot)
        XCTAssertNil(store.snapshot(now: publicationDate.addingTimeInterval(30), maximumAge: 60))
        XCTAssertEqual(reloadCount, 2)
    }

    func testDisablingEnergyProbeIgnoresInFlightProbeResult() async {
        let reader = ControlledDiagnosticsReader()
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {}
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        monitor.updateMonitoringDemand(BatteryMonitoringDemand(needsEnergyChangeAwareness: false))
        reader.resumeRequest(at: 1, snapshot: .previewCharging)
        await Task.yield()

        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)
    }

    func testVisibleSurfaceDemandKeepsEnergyProbeActiveWhenBackgroundDemandIsDisabled() async {
        let reader = ControlledDiagnosticsReader()
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {}
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        monitor.updateMonitoringDemand(BatteryMonitoringDemand(needsEnergyChangeAwareness: false))
        monitor.beginVisibleSurfaceMonitoring()
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: .previewCharging)
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
    }

    func testEndingLastVisibleSurfaceDisablesEnergyProbeWhenBackgroundDemandIsDisabled() async {
        let reader = ControlledDiagnosticsReader()
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {}
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        monitor.updateMonitoringDemand(BatteryMonitoringDemand(needsEnergyChangeAwareness: false))
        monitor.beginVisibleSurfaceMonitoring()
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        monitor.endVisibleSurfaceMonitoring()
        monitor.probeEnergyUseForTesting()
        await Task.yield()

        XCTAssertEqual(reader.requests, [.standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)
    }

    func testStopClearsVisibleSurfaceDemandBeforeRestart() async {
        let reader = StubBatteryReader(snapshots: [
            .previewDischarging,
            .previewDischarging,
            .previewCharging
        ])
        let monitor = makeMonitor(reader)

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        monitor.updateMonitoringDemand(BatteryMonitoringDemand(needsEnergyChangeAwareness: false))
        monitor.beginVisibleSurfaceMonitoring()
        monitor.start()
        await monitor.waitForIdleForTesting()

        monitor.stop()
        monitor.start()
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await monitor.waitForIdleForTesting()

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)
    }

    func testLightningRefreshOverridesTimerUntilDisabled() async {
        let reader = StubBatteryReader(snapshots: [
            .previewDischarging,
            .previewCharging
        ])
        let monitor = makeMonitor(reader)
        let policy = BatteryRefreshPolicy(cadence: .fiveMinutes, energyChangeSensitivity: .balanced)

        monitor.updateRefreshPolicy(policy)
        monitor.start()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(monitor.currentRefreshIntervalForTesting(), 300)

        monitor.setLightningRefreshActive(true)
        XCTAssertEqual(monitor.currentRefreshIntervalForTesting(), policy.lightningRefreshInterval)

        monitor.setLightningRefreshActive(false)
        await monitor.waitForIdleForTesting()
        XCTAssertEqual(monitor.currentRefreshIntervalForTesting(), 300)

        let requests = await reader.requests
        XCTAssertEqual(requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
    }

    func testStopClearsLightningRefreshBeforeRestart() async {
        let reader = StubBatteryReader(snapshots: [
            .previewDischarging,
            .previewDischarging
        ])
        let monitor = makeMonitor(reader)
        let policy = BatteryRefreshPolicy(cadence: .fiveMinutes, energyChangeSensitivity: .balanced)

        monitor.updateRefreshPolicy(policy)
        monitor.start()
        await monitor.waitForIdleForTesting()

        monitor.setLightningRefreshActive(true)
        XCTAssertEqual(monitor.currentRefreshIntervalForTesting(), policy.lightningRefreshInterval)

        monitor.stop()
        monitor.start()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(monitor.currentRefreshIntervalForTesting(), 300)

        let requestCount = await reader.requestCount
        XCTAssertGreaterThanOrEqual(requestCount, 2)
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)
    }

    func testLightningRefreshLoopsUntilDisabled() async {
        let reader = StubBatteryReader(snapshots: [
            .previewDischarging,
            .previewCharging,
            .previewCharging,
            .previewCharging
        ])
        let monitor = makeMonitor(reader)

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .fiveMinutes, energyChangeSensitivity: .balanced))
        monitor.start()
        await monitor.waitForIdleForTesting()

        monitor.setLightningRefreshActive(true)
        try? await Task.sleep(for: .milliseconds(550))
        monitor.setLightningRefreshActive(false)
        await monitor.waitForIdleForTesting()

        let requestCount = await reader.requestCount
        XCTAssertGreaterThanOrEqual(requestCount, 3)
    }

    func testReenabledEnergyProbeStartsWithFreshEnergyBaseline() async {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_030)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let snapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: snapshot)
        await monitor.waitForIdleForTesting()

        monitor.updateMonitoringDemand(BatteryMonitoringDemand(needsEnergyChangeAwareness: false))
        monitor.updateMonitoringDemand(BatteryMonitoringDemand(needsEnergyChangeAwareness: true))
        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: snapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 2)
    }

    func testEnergyProbePublishesWhenHighTemperatureAlertStateChangesWithoutEnergyChange() async {
        let reader = ControlledDiagnosticsReader()
        let deliverer = MonitorFakeBatteryAlertNotificationDeliverer()
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            alertCoordinator: coordinator,
            widgetTimelineReloader: {}
        )
        let policy = BatteryAlertPolicy(isHighTemperatureAlertEnabled: true)

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        monitor.updateAlerts(policy)
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: makeTemperatureSnapshot(celsius: 39, powerWatts: 14.4))
        await monitor.waitForIdleForTesting()

        XCTAssertTrue(deliverer.notifications.isEmpty)

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: makeTemperatureSnapshot(celsius: 42, powerWatts: 14.4))
        await monitor.waitForIdleForTesting()
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.temperatureCelsius, 42)
        XCTAssertEqual(deliverer.notifications.map(\.identifier), ["BatteryStats.HighTemperature"])
    }

    func testEnergyProbePublishesVisiblePowerStateChangeWithoutEnergyChange() async {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 2_000)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let discharging = makeEnergyProbeSnapshot(
            powerState: .onBattery,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )
        let charging = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: discharging)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: charging)
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
        XCTAssertEqual(monitor.snapshot?.statusDisplayTitle, "Charging")
        XCTAssertEqual(monitor.snapshot?.activePowerWatts, 14.4)
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reader.requestDates, [refreshDate, probeDate])
        XCTAssertEqual(reloadCount, 2)
    }

    func testEnergyProbePublishesVisiblePowerValueChangeBelowEnergyThreshold() async {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.8
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.8, thresholdPercent: 35))
        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.activePowerWatts, 14.8)
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 2)
    }

    func testEnergyProbePublishesFreshnessWhenUpdateMinuteChangesWithoutValueChange() async throws {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_061)
        var readDates = [refreshDate, probeDate]
        let widgetStore = try makeWidgetSnapshotStore()
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetSnapshotStore: widgetStore,
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60,
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .onBattery,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .onBattery,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        let loadedSnapshot = try XCTUnwrap(widgetStore.snapshot(now: probeDate, maximumAge: 60))
        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(monitor.lastUpdated, probeDate)
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(loadedSnapshot.timestamp, probeDate)
        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(reloadCount, 2)
    }

    func testEnergyProbePublishesChargingInputPowerTitleChangeWhenWattsAreStable() async throws {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            inputPowerWatts: 14.4
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(firstSnapshot.activePowerWatts, secondSnapshot.activePowerWatts)
        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.inputPowerWatts, 14.4)
        XCTAssertEqual(BatterySummaryDetailFormatting.powerTitle(for: try XCTUnwrap(monitor.snapshot)), "Input Power")
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 2)
    }

    func testEnergyProbePublishesConnectedDischargingInputPowerTitleChangeWhenWattsAreStable() async throws {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .connectedDischarging,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .connectedDischarging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            inputPowerWatts: 14.4
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(firstSnapshot.activePowerWatts, secondSnapshot.activePowerWatts)
        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.inputPowerWatts, 14.4)
        XCTAssertEqual(BatterySummaryDetailFormatting.powerTitle(for: try XCTUnwrap(monitor.snapshot)), "Input Power")
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 2)
    }

    func testEnergyProbePublishesVisibleTimeRemainingChangeWithoutEnergyChange() async {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            timeToFullMinutes: 82
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            timeToFullMinutes: 125
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.displayedTimeMinutes, 125)
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.displayValue(
                snapshot: monitor.snapshot,
                displayMode: .iconAndTimeRemaining,
                temperatureUnitPreference: .celsius
            ),
            "2h"
        )
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 2)
    }

    func testEnergyProbePublishesVisibleCurrentChangeWithoutWattChange() async throws {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 0.04,
            currentMilliamps: 1_200
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 0.04,
            currentMilliamps: 1_350
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 1.2, current: 1.35, thresholdPercent: 35))
        XCTAssertNil(monitor.snapshot?.activePowerWatts)
        XCTAssertEqual(monitor.snapshot?.activeCurrentMilliamps, 1_350)
        XCTAssertEqual(
            BatterySummaryDetailFormatting.timeSummary(for: try XCTUnwrap(monitor.snapshot)),
            "1h 22m / 1,350 mA"
        )
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 1)
    }

    func testEnergyProbeSkipsInvisibleChargingCurrentChangeWhenPowerIsStable() async throws {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            currentMilliamps: 1_200
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            currentMilliamps: 1_350
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(monitor.snapshot?.activePowerWatts, 14.4)
        XCTAssertEqual(monitor.snapshot?.activeCurrentMilliamps, 1_200)
        XCTAssertEqual(
            BatterySummaryDetailFormatting.timeSummary(for: try XCTUnwrap(monitor.snapshot)),
            "1h 22m / 14.4 W"
        )
        XCTAssertEqual(monitor.snapshot?.timestamp, refreshDate)
        XCTAssertEqual(reloadCount, 1)
    }

    func testEnergyProbePublishesVisibleDetailRowsWithoutEnergyChange() async {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            voltageMillivolts: 12_000,
            temperatureCelsius: 32.0,
            cycleCount: 120,
            currentChargeMilliampHours: 3_050,
            currentChargeWattHours: 39.6
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            voltageMillivolts: 12_180,
            temperatureCelsius: 33.2,
            cycleCount: 121,
            currentChargeMilliampHours: 3_075,
            currentChargeWattHours: 39.9
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(monitor.snapshot?.temperatureCelsius, 33.2)
        XCTAssertEqual(monitor.snapshot?.voltageMillivolts, 12_180)
        XCTAssertEqual(monitor.snapshot?.cycleCount, 121)
        XCTAssertEqual(monitor.snapshot?.currentChargeMilliampHours, 3_075)
        XCTAssertEqual(monitor.snapshot?.currentChargeWattHours, 39.9)
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 1)
    }

    func testEnergyProbePublishesVisibleChargeTintChangeInsideRoundedPercentBucket() async {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .onBattery,
            stateOfChargePercent: 40.4,
            powerWatts: 14.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .onBattery,
            stateOfChargePercent: 39.6,
            powerWatts: 14.4
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(
            BatteryFormatting.percent(firstSnapshot.presentationStateOfChargePercent, decimals: 0),
            BatteryFormatting.percent(secondSnapshot.presentationStateOfChargePercent, decimals: 0)
        )
        XCTAssertEqual(firstSnapshot.batterySymbolName, secondSnapshot.batterySymbolName)
        XCTAssertNotEqual(
            BatteryPresentationStyle.chargeTintStyle(for: firstSnapshot),
            BatteryPresentationStyle.chargeTintStyle(for: secondSnapshot)
        )
        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.presentationStateOfChargePercent, 39.6)
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 2)
    }

    func testEnergyProbePublishesVisibleHealthTintChangeInsideRoundedPercentBucket() async {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let refreshDate = Date(timeIntervalSince1970: 1_000)
        let probeDate = Date(timeIntervalSince1970: 1_015)
        var readDates = [refreshDate, probeDate]
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            now: { readDates.removeFirst() }
        )
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            healthPercent: 90.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            healthPercent: 89.6
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: firstSnapshot)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: secondSnapshot)
        await monitor.waitForIdleForTesting()

        XCTAssertFalse(BatteryRefreshPolicy.isSignificantEnergyChange(previous: 14.4, current: 14.4, thresholdPercent: 35))
        XCTAssertEqual(
            BatteryFormatting.percent(firstSnapshot.presentationHealthPercent, decimals: 0),
            BatteryFormatting.percent(secondSnapshot.presentationHealthPercent, decimals: 0)
        )
        XCTAssertNotEqual(
            BatteryPresentationStyle.healthTintStyle(for: firstSnapshot),
            BatteryPresentationStyle.healthTintStyle(for: secondSnapshot)
        )
        XCTAssertEqual(reader.requests, [.standard, .standard])
        XCTAssertEqual(monitor.snapshot?.presentationHealthPercent, 89.6)
        XCTAssertEqual(monitor.snapshot?.timestamp, probeDate)
        XCTAssertEqual(reloadCount, 2)
    }

    func testRefreshCancelsInFlightEnergyProbeResult() async {
        let reader = ControlledDiagnosticsReader()
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            }
        )

        monitor.updateRefreshPolicy(BatteryRefreshPolicy(cadence: .dynamic, energyChangeSensitivity: .balanced))
        enableEnergyProbeDemand(on: monitor)
        monitor.start()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: .previewDischarging)
        await monitor.waitForIdleForTesting()

        monitor.probeEnergyUseForTesting()
        await reader.waitForRequestCount(2)
        monitor.refresh()
        await reader.waitForRequestCount(3)
        reader.resumeRequest(at: 2, snapshot: .previewCharging)
        await monitor.waitForIdleForTesting()

        reader.resumeRequest(at: 1, snapshot: makeLowBatterySnapshot(timestamp: Date(timeIntervalSince1970: 1_060)))
        await Task.yield()

        XCTAssertEqual(reader.requests, [.standard, .standard, .standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .charging)
        XCTAssertEqual(monitor.snapshot?.stateOfChargePercent, BatterySnapshot.previewCharging.stateOfChargePercent)
        XCTAssertEqual(reloadCount, 2)
    }

    func testRefreshRequestsWidgetTimelineReloadWhenSnapshotPublishes() async {
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            }
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reloadCount, 1)
    }

    func testEnablingHistoryRecordsCurrentSnapshotImmediately() async throws {
        let historyStore = try makeHistoryStore()
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {}
        )

        monitor.updateHistory(store: historyStore, policy: .disabled)
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertTrue(historyStore.entries.isEmpty)

        monitor.updateHistory(
            store: historyStore,
            policy: BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false)
        )

        XCTAssertEqual(historyStore.entries.count, 1)
        XCTAssertEqual(historyStore.entries.first?.timestamp, monitor.snapshot?.timestamp)
        XCTAssertEqual(historyStore.entries.first?.stateOfChargePercent, monitor.snapshot?.stateOfChargePercent)
    }

    func testRuntimeConfigurationObserverAppliesPreferenceChangesWithoutViewOnChange() async throws {
        let preferences = try makePreferencesStore()
        let historyStore = try makeHistoryStore()
        let reader = StubBatteryReader(snapshots: [.previewDischarging])
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {}
        )
        let observer = BatteryMonitorConfigurationObserver(
            monitor: monitor,
            preferences: preferences,
            historyStore: historyStore
        )

        observer.start()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertTrue(historyStore.entries.isEmpty)

        preferences.isHistoryEnabled = true

        for _ in 0..<10 {
            if historyStore.entries.count == 1 {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(historyStore.entries.count, 1)
        XCTAssertEqual(historyStore.entries.first?.timestamp, monitor.snapshot?.timestamp)
        XCTAssertEqual(historyStore.entries.first?.stateOfChargePercent, monitor.snapshot?.stateOfChargePercent)
        withExtendedLifetime(observer) {}
    }

    func testRuntimeConfigurationObserverAppliesPreferenceChangesWithoutForcingSensorRead() async throws {
        let preferences = try makePreferencesStore()
        let historyStore = try makeHistoryStore()
        let reader = StubBatteryReader(snapshots: [.previewDischarging, .previewCharging])
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {}
        )
        let observer = BatteryMonitorConfigurationObserver(
            monitor: monitor,
            preferences: preferences,
            historyStore: historyStore
        )

        observer.start()
        monitor.start()
        await monitor.waitForIdleForTesting()

        let initialRequests = await reader.requests
        XCTAssertEqual(initialRequests, [.standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)

        preferences.refreshCadencePreference = .fiveMinutes

        for _ in 0..<5 {
            await Task.yield()
        }
        await monitor.waitForIdleForTesting()

        let updatedRequests = await reader.requests
        XCTAssertEqual(updatedRequests, [.standard])
        XCTAssertEqual(monitor.snapshot?.powerState, .onBattery)
        withExtendedLifetime(observer) {}
    }

    func testRefreshSkipsDuplicateWidgetTimelineReloadInsideThrottleWindow() async {
        let reader = StubBatteryReader(snapshots: [.previewDischarging, .previewDischarging])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reloadCount, 1)
    }

    func testWidgetTimelineReloadsWhenPublicationTimestampLeavesThrottleWindow() async {
        var publicationDates = [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 1_061)
        ]
        let reader = StubBatteryReader(snapshots: [
            makeLowBatterySnapshot(timestamp: Date(timeIntervalSince1970: 900)),
            makeLowBatterySnapshot(timestamp: Date(timeIntervalSince1970: 900))
        ])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60,
            now: { publicationDates.removeFirst() }
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reloadCount, 2)
    }

    func testWidgetTimelineReloadsWhenPublicationClockMovesBackwardInsideSameMinute() async {
        var publicationDates = [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 990)
        ]
        let reader = StubBatteryReader(snapshots: [
            makeLowBatterySnapshot(timestamp: Date(timeIntervalSince1970: 900)),
            makeLowBatterySnapshot(timestamp: Date(timeIntervalSince1970: 900))
        ])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60,
            now: { publicationDates.removeFirst() }
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reloadCount, 2)
        XCTAssertEqual(monitor.snapshot?.timestamp, Date(timeIntervalSince1970: 990))
    }

    func testWidgetTimelineReloadsWhenLowPowerStatusTitleChangesInsideThrottleWindow() async {
        let reader = StubBatteryReader(snapshots: [
            makeWidgetReloadSnapshot(stateOfChargePercent: 20.4),
            makeWidgetReloadSnapshot(stateOfChargePercent: 20.0)
        ])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reloadCount, 2)
        XCTAssertEqual(monitor.snapshot?.statusDisplayTitle, "On Battery Low Power")
    }

    func testWidgetTimelineReloadsWhenChargeTintChangesInsideRoundedPercentBucket() async {
        let firstSnapshot = makeWidgetReloadSnapshot(stateOfChargePercent: 40.4)
        let secondSnapshot = makeWidgetReloadSnapshot(stateOfChargePercent: 39.6)
        let reader = StubBatteryReader(snapshots: [firstSnapshot, secondSnapshot])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(
            BatteryFormatting.percent(firstSnapshot.presentationStateOfChargePercent, decimals: 0),
            BatteryFormatting.percent(secondSnapshot.presentationStateOfChargePercent, decimals: 0)
        )
        XCTAssertEqual(firstSnapshot.batterySymbolName, secondSnapshot.batterySymbolName)
        XCTAssertNotEqual(
            BatteryPresentationStyle.chargeTintStyle(for: firstSnapshot),
            BatteryPresentationStyle.chargeTintStyle(for: secondSnapshot)
        )
        XCTAssertEqual(reloadCount, 2)
    }

    func testWidgetTimelineReloadsWhenChargingInputPowerTitleChangesInsideThrottleWindow() async {
        var publicationDates = [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 1_015)
        ]
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            inputPowerWatts: 14.4
        )
        let reader = StubBatteryReader(snapshots: [firstSnapshot, secondSnapshot])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60,
            now: { publicationDates.removeFirst() }
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(firstSnapshot.activePowerWatts, secondSnapshot.activePowerWatts)
        XCTAssertEqual(monitor.snapshot?.inputPowerWatts, 14.4)
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: monitor.snapshot), "Input Power")
        XCTAssertEqual(reloadCount, 2)
    }

    func testWidgetTimelineDoesNotReloadForInputPowerAboveAdapterCapabilityInsideThrottleWindow() async {
        var publicationDates = [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 1_015)
        ]
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 25.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .charging,
            stateOfChargePercent: 61,
            powerWatts: 25.4,
            inputPowerWatts: 100
        )
        let reader = StubBatteryReader(snapshots: [firstSnapshot, secondSnapshot])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60,
            now: { publicationDates.removeFirst() }
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(secondSnapshot.activePowerWatts, 25.4)
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: secondSnapshot), "Charge Rate")
        XCTAssertEqual(reloadCount, 1)
    }

    func testWidgetTimelineReloadsWhenConnectedInputPowerTitleChangesInsideThrottleWindow() async {
        var publicationDates = [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 1_015)
        ]
        let firstSnapshot = makeEnergyProbeSnapshot(
            powerState: .connectedNotCharging,
            stateOfChargePercent: 61,
            powerWatts: 14.4
        )
        let secondSnapshot = makeEnergyProbeSnapshot(
            powerState: .connectedNotCharging,
            stateOfChargePercent: 61,
            powerWatts: 14.4,
            inputPowerWatts: 14.4
        )
        let reader = StubBatteryReader(snapshots: [firstSnapshot, secondSnapshot])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60,
            now: { publicationDates.removeFirst() }
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertNil(firstSnapshot.activePowerWatts)
        XCTAssertEqual(secondSnapshot.activePowerWatts, 14.4)
        XCTAssertEqual(monitor.snapshot?.inputPowerWatts, 14.4)
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: monitor.snapshot), "Input Power")
        XCTAssertEqual(reloadCount, 2)
    }

    func testWidgetTimelineReloadsWhenHealthTintChangesInsideRoundedPercentBucket() async {
        let firstSnapshot = makeWidgetReloadSnapshot(stateOfChargePercent: 55, healthPercent: 90.4)
        let secondSnapshot = makeWidgetReloadSnapshot(stateOfChargePercent: 55, healthPercent: 89.6)
        let reader = StubBatteryReader(snapshots: [firstSnapshot, secondSnapshot])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(
            BatteryFormatting.percent(firstSnapshot.presentationHealthPercent, decimals: 0),
            BatteryFormatting.percent(secondSnapshot.presentationHealthPercent, decimals: 0)
        )
        XCTAssertNotEqual(
            BatteryPresentationStyle.healthTintStyle(for: firstSnapshot),
            BatteryPresentationStyle.healthTintStyle(for: secondSnapshot)
        )
        XCTAssertEqual(reloadCount, 2)
    }

    func testWidgetTimelineReloadsWhenMediumBatteryIconChangesInsideRoundedPercentBucket() async {
        let firstSnapshot = makeEnergyProbeSnapshot(powerState: .onBattery, stateOfChargePercent: 0.4, powerWatts: 14.4)
        let secondSnapshot = makeEnergyProbeSnapshot(powerState: .onBattery, stateOfChargePercent: 0, powerWatts: 14.4)
        let reader = StubBatteryReader(snapshots: [firstSnapshot, secondSnapshot])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            },
            widgetTimelineReloadMinimumInterval: 60
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()
        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(
            BatteryFormatting.percent(firstSnapshot.presentationStateOfChargePercent, decimals: 0),
            BatteryFormatting.percent(secondSnapshot.presentationStateOfChargePercent, decimals: 0)
        )
        XCTAssertNotEqual(
            BatteryPresentationStyle.statusDescriptor(for: firstSnapshot).symbolName,
            BatteryPresentationStyle.statusDescriptor(for: secondSnapshot).symbolName
        )
        XCTAssertNotEqual(firstSnapshot.batterySymbolName, secondSnapshot.batterySymbolName)
        XCTAssertEqual(reloadCount, 2)
    }

    func testWidgetTimelineReloadHandlesNonFiniteSnapshotValues() async {
        let reader = StubBatteryReader(snapshots: [makeNonFiniteSnapshot()])
        var reloadCount = 0
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetTimelineReloader: {
                reloadCount += 1
            }
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(reloadCount, 1)
        XCTAssertNotNil(monitor.snapshot)
    }

    func testWidgetSnapshotStoreRoundTripsRecentSnapshot() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = makeLowBatterySnapshot()

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, snapshot.powerState)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, snapshot.stateOfChargePercent)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.healthPercent), 83.33, accuracy: 0.01)
        XCTAssertEqual(loadedSnapshot.currentChargeMilliampHours, snapshot.currentChargeMilliampHours)
    }

    func testWidgetSnapshotStoreFreshnessMissDoesNotDeleteRetainedSnapshot() throws {
        let store = try makeWidgetSnapshotStore()
        let defaults = try XCTUnwrap(store.defaults)
        let snapshot = makeLowBatterySnapshot()
        let now = Date(timeIntervalSince1970: 1_500)

        store.save(snapshot)

        XCTAssertNil(store.snapshot(now: now, maximumAge: 60))
        XCTAssertNotNil(defaults.data(forKey: "latestBatteryWidgetSnapshot"))

        let retainedSnapshot = try XCTUnwrap(store.snapshot(now: now))
        XCTAssertEqual(retainedSnapshot.timestamp, snapshot.timestamp)
    }

    func testWidgetSnapshotStoreKeepsStaleSnapshotWithinDefaultRetentionWindow() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = makeLowBatterySnapshot()
        let now = snapshot.timestamp.addingTimeInterval(12 * 60)

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: now))
        XCTAssertEqual(loadedSnapshot.timestamp, snapshot.timestamp)
        XCTAssertEqual(
            BatteryWidgetUpdateFormatting.statusText(updatedAt: loadedSnapshot.timestamp, now: now),
            "Stale 12m ago"
        )
    }

    func testWidgetSnapshotStoreDropsSnapshotBeyondDefaultRetentionWindow() throws {
        let store = try makeWidgetSnapshotStore()
        let defaults = try XCTUnwrap(store.defaults)
        let snapshot = makeLowBatterySnapshot()
        let now = snapshot.timestamp.addingTimeInterval(BatteryWidgetSnapshotStore.defaultRetentionAge + 1)

        store.save(snapshot)

        XCTAssertNil(store.snapshot(now: now))
        XCTAssertNil(defaults.data(forKey: "latestBatteryWidgetSnapshot"))
    }

    func testWidgetSnapshotStoreClampsSmallFutureTimestampOnRead() throws {
        let store = try makeWidgetSnapshotStore()
        let now = Date(timeIntervalSince1970: 1_030)
        let snapshot = makeLowBatterySnapshot(timestamp: now.addingTimeInterval(20))

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: now, maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.timestamp, now)

        let defaults = try XCTUnwrap(store.defaults)
        let rewrittenData = try XCTUnwrap(defaults.data(forKey: "latestBatteryWidgetSnapshot"))
        let rewrittenSnapshot = try JSONDecoder().decode(BatterySnapshot.self, from: rewrittenData)
        XCTAssertEqual(rewrittenSnapshot.timestamp, now)
    }

    func testWidgetSnapshotStoreNormalizesContradictoryPersistedPowerState() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 39,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .connectedDischarging)
        XCTAssertFalse(loadedSnapshot.isCharging)
        XCTAssertTrue(loadedSnapshot.isExternalPowerConnected)
        XCTAssertEqual(loadedSnapshot.dischargeRateMilliamps, 1_200)
        XCTAssertEqual(loadedSnapshot.displayedTimeMinutes, 150)
    }

    func testWidgetSnapshotStorePreservesStoredFullACStateWhenExternalFlagIsStale() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .fullOnAC,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 5_000,
            currentChargeWattHours: 65,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 100,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .fullOnAC)
        XCTAssertFalse(loadedSnapshot.isCharging)
        XCTAssertTrue(loadedSnapshot.isExternalPowerConnected)
    }

    func testWidgetSnapshotStoreShowsFullChargeWhenStoredFullACCurrentIsTransientlyEmpty() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .fullOnAC,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 0,
            currentChargeWattHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: nil,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .fullOnAC)
        XCTAssertEqual(loadedSnapshot.currentChargeMilliampHours, 5_000)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, 100)
        XCTAssertEqual(loadedSnapshot.batterySymbolName, "battery.100")
    }

    func testWidgetSnapshotStoreDoesNotForceFullACWhenStoredPercentContradictsChargedState() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .fullOnAC,
            isCharging: false,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 1_000,
            currentChargeWattHours: 12,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 20,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .connectedNotCharging)
        XCTAssertEqual(loadedSnapshot.currentChargeMilliampHours, 1_000)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, 20)
        XCTAssertEqual(loadedSnapshot.batterySymbolName, "battery.25")
    }

    func testWidgetSnapshotStorePreservesStoredConnectedStateWhenExternalFlagIsStale() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .connectedNotCharging,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 4_000,
            currentChargeWattHours: 52,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 80,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .connectedNotCharging)
        XCTAssertFalse(loadedSnapshot.isCharging)
        XCTAssertTrue(loadedSnapshot.isExternalPowerConnected)
    }

    func testWidgetSnapshotStorePreservesConnectedDischargingRatesAndTime() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .connectedDischarging,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .connectedDischarging)
        XCTAssertFalse(loadedSnapshot.isCharging)
        XCTAssertTrue(loadedSnapshot.isExternalPowerConnected)
        XCTAssertEqual(loadedSnapshot.dischargeRateMilliamps, 1_200)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.dischargeRateWatts), 14.4, accuracy: 0.001)
        XCTAssertEqual(loadedSnapshot.rateBasedTimeRemainingMinutes, 150)
        XCTAssertEqual(loadedSnapshot.systemTimeRemainingMinutes, 145)
        XCTAssertEqual(loadedSnapshot.displayedTimeMinutes, 150)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 14.4, accuracy: 0.001)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 70)
    }

    func testWidgetSnapshotStorePreservesStoredConnectedStateWhenSignedCurrentIsStale() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .connectedNotCharging,
            isCharging: false,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 4_000,
            currentChargeWattHours: 52,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 80,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .connectedNotCharging)
        XCTAssertFalse(loadedSnapshot.isCharging)
        XCTAssertTrue(loadedSnapshot.isExternalPowerConnected)
        XCTAssertNil(loadedSnapshot.currentMilliampsSigned)
        XCTAssertNil(loadedSnapshot.dischargeRateMilliamps)
        XCTAssertNil(loadedSnapshot.dischargeRateWatts)
        XCTAssertNil(loadedSnapshot.rateBasedTimeRemainingMinutes)
        XCTAssertNil(loadedSnapshot.systemTimeRemainingMinutes)
        XCTAssertNil(loadedSnapshot.activeCurrentMilliamps)
        XCTAssertNil(loadedSnapshot.activePowerWatts)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 70)
    }

    func testWidgetSnapshotStorePreservesStoredOnBatteryStateWhenExternalFlagIsStale() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 4_000,
            currentChargeWattHours: 52,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 80,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .onBattery)
        XCTAssertFalse(loadedSnapshot.isCharging)
        XCTAssertFalse(loadedSnapshot.isExternalPowerConnected)
        XCTAssertNil(loadedSnapshot.adapterMaxWatts)
    }

    func testWidgetSnapshotStorePreservesUnknownStateWithoutPowerEvidence() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .unknown,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 4_000,
            currentChargeWattHours: 52,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 80,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: 20,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .unknown)
        XCTAssertFalse(loadedSnapshot.isCharging)
        XCTAssertFalse(loadedSnapshot.isExternalPowerConnected)
        XCTAssertNil(loadedSnapshot.displayedTimeMinutes)
        XCTAssertNil(loadedSnapshot.activePowerWatts)
        XCTAssertNil(loadedSnapshot.adapterMaxWatts)
    }

    func testWidgetSnapshotStoreResolvesUnknownStateWhenExternalPowerIsKnown() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .unknown,
            isCharging: false,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 4_000,
            currentChargeWattHours: 52,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 80,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .connectedNotCharging)
        XCTAssertFalse(loadedSnapshot.isCharging)
        XCTAssertTrue(loadedSnapshot.isExternalPowerConnected)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 70)
    }

    func testWidgetSnapshotStoreSanitizesNonFiniteValues() throws {
        let store = try makeWidgetSnapshotStore()

        store.save(makeNonFiniteSnapshot())

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.healthPercent), 83.33, accuracy: 0.01)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, 60)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.dischargeRateWatts), 14.4, accuracy: 0.001)
    }

    func testWidgetSnapshotStoreDerivesMissingHealthFromValidCapacity() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: nil,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.healthPercent), 83.33, accuracy: 0.01)
        XCTAssertEqual(loadedSnapshot.presentationHealthPercent, loadedSnapshot.healthPercent)
    }

    func testWidgetSnapshotStorePrefersCapacityDerivedHealthOverStaleStoredHealth() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 4_000,
            fullChargeCapacityWattHours: 52,
            designCapacityMilliampHours: 5_000,
            designCapacityWattHours: 65,
            healthPercent: 100,
            stateOfChargePercent: 75,
            voltageMillivolts: 13_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 15.6,
            rateBasedTimeRemainingMinutes: 200,
            systemTimeRemainingMinutes: 195,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: nil,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.healthPercent, 80)
        XCTAssertEqual(loadedSnapshot.presentationHealthPercent, 80)
    }

    func testWidgetSnapshotStoreDerivesMissingStateOfChargeFromValidCapacity() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: nil,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, 60)
        XCTAssertEqual(loadedSnapshot.presentationStateOfChargePercent, 60)
    }

    func testWidgetSnapshotStoreReconcilesCurrentChargeWithTrustedPercent() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 0,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 92,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.currentChargeMilliampHours, 4_600)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.currentChargeWattHours), 55.2, accuracy: 0.001)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, 92)
    }

    func testWidgetSnapshotStoreDropsCurrentEnergyWhenCurrentChargeIsRejected() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 6_000,
            currentChargeWattHours: 72,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: nil,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.currentChargeMilliampHours)
        XCTAssertNil(loadedSnapshot.currentChargeWattHours)
        XCTAssertEqual(loadedSnapshot.fullChargeCapacityWattHours, 60)
    }

    func testWidgetSnapshotStoreSanitizesOutOfRangeValues() throws {
        let store = try makeWidgetSnapshotStore()

        store.save(makeOutOfRangeSnapshot())

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.currentChargeMilliampHours)
        XCTAssertNil(loadedSnapshot.currentChargeWattHours)
        XCTAssertNil(loadedSnapshot.fullChargeCapacityMilliampHours)
        XCTAssertNil(loadedSnapshot.designCapacityMilliampHours)
        XCTAssertNil(loadedSnapshot.healthPercent)
        XCTAssertNil(loadedSnapshot.stateOfChargePercent)
        XCTAssertNil(loadedSnapshot.voltageMillivolts)
        XCTAssertNil(loadedSnapshot.currentMilliampsSigned)
        XCTAssertNil(loadedSnapshot.dischargeRateMilliamps)
        XCTAssertNil(loadedSnapshot.chargeRateWatts)
        XCTAssertNil(loadedSnapshot.rateBasedTimeRemainingMinutes)
        XCTAssertNil(loadedSnapshot.systemTimeRemainingMinutes)
        XCTAssertNil(loadedSnapshot.timeToFullMinutes)
        XCTAssertNil(loadedSnapshot.cycleCount)
        XCTAssertNil(loadedSnapshot.temperatureCelsius)
        XCTAssertNil(loadedSnapshot.adapterMaxWatts)
    }

    func testWidgetSnapshotStoreRejectsAbsurdDurationValues() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 39.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: Int.max,
            systemTimeRemainingMinutes: 1_441,
            timeToFullMinutes: Int.max,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.rateBasedTimeRemainingMinutes)
        XCTAssertNil(loadedSnapshot.systemTimeRemainingMinutes)
        XCTAssertNil(loadedSnapshot.timeToFullMinutes)
        XCTAssertNil(loadedSnapshot.displayedTimeMinutes)
    }

    func testWidgetSnapshotStoreRecomputesFalseZeroTimeToEmptyWhenBatteryHasCharge() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 0,
            systemTimeRemainingMinutes: 0,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.rateBasedTimeRemainingMinutes, 150)
        XCTAssertNil(loadedSnapshot.systemTimeRemainingMinutes)
        XCTAssertEqual(loadedSnapshot.displayedTimeMinutes, 150)
    }

    func testWidgetSnapshotStoreKeepsZeroTimeToEmptyWhenBatteryIsEmpty() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 0,
            currentChargeWattHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72,
            healthPercent: 83,
            stateOfChargePercent: 0,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 0,
            systemTimeRemainingMinutes: 0,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.rateBasedTimeRemainingMinutes, 0)
        XCTAssertEqual(loadedSnapshot.systemTimeRemainingMinutes, 0)
        XCTAssertEqual(loadedSnapshot.displayedTimeMinutes, 0)
    }

    func testWidgetSnapshotStoreRecomputesFalseZeroTimeToFullWhenChargingBelowFull() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 725,
            currentChargeWattHours: 8.7,
            fullChargeCapacityMilliampHours: 4_525,
            fullChargeCapacityWattHours: 54.3,
            designCapacityMilliampHours: 5_000,
            designCapacityWattHours: 60,
            healthPercent: 90.5,
            stateOfChargePercent: 16,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 4_387,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 52.6,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 0,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        let timeToFullMinutes = try XCTUnwrap(loadedSnapshot.timeToFullMinutes)
        XCTAssertGreaterThan(timeToFullMinutes, 0)
        XCTAssertEqual(loadedSnapshot.displayedTimeMinutes, timeToFullMinutes)
    }

    func testWidgetSnapshotStorePreservesValidStoredTimeToFullValue() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 2_000,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 24,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 240,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )
        let expectedMinutes = try XCTUnwrap(BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            chargeCurrentMilliamps: 2_000,
            reportedTimeToFullMinutes: nil
        ))
        XCTAssertNotEqual(expectedMinutes, 240)

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.timeToFullMinutes, 240)
        XCTAssertEqual(loadedSnapshot.displayedTimeMinutes, 240)
    }

    func testWidgetSnapshotStoreDerivesMissingTimeToFullFromChargeCurrent() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 2_000,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 24,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )
        let expectedMinutes = try XCTUnwrap(BatteryCalculations.estimatedTimeToFullMinutes(
            currentChargeMilliampHours: 3_000,
            fullChargeCapacityMilliampHours: 5_000,
            chargeCurrentMilliamps: 2_000,
            reportedTimeToFullMinutes: nil
        ))

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.timeToFullMinutes, expectedMinutes)
        XCTAssertEqual(loadedSnapshot.displayedTimeMinutes, expectedMinutes)
    }

    func testWidgetSnapshotStoreKeepsZeroTimeToFullWhenBatteryIsFull() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 5_000,
            currentChargeWattHours: 60,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72,
            healthPercent: 83,
            stateOfChargePercent: 100,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 0,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertEqual(loadedSnapshot.timeToFullMinutes, 0)
        XCTAssertEqual(loadedSnapshot.displayedTimeMinutes, 0)
    }

    func testWidgetSnapshotStoreRejectsAbsurdPhysicalValues() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: Int.max,
            currentChargeWattHours: .greatestFiniteMagnitude,
            fullChargeCapacityMilliampHours: Int.max,
            fullChargeCapacityWattHours: .greatestFiniteMagnitude,
            designCapacityMilliampHours: Int.max,
            designCapacityWattHours: .greatestFiniteMagnitude,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: Int.max,
            currentMilliampsSigned: Int.max,
            dischargeRateMilliamps: Int.max,
            chargeRateWatts: .greatestFiniteMagnitude,
            dischargeRateWatts: .greatestFiniteMagnitude,
            rateBasedTimeRemainingMinutes: 120,
            systemTimeRemainingMinutes: 120,
            timeToFullMinutes: nil,
            cycleCount: Int.max,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: Int.max,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.currentChargeMilliampHours)
        XCTAssertNil(loadedSnapshot.currentChargeWattHours)
        XCTAssertNil(loadedSnapshot.fullChargeCapacityMilliampHours)
        XCTAssertNil(loadedSnapshot.fullChargeCapacityWattHours)
        XCTAssertNil(loadedSnapshot.designCapacityMilliampHours)
        XCTAssertNil(loadedSnapshot.designCapacityWattHours)
        XCTAssertNil(loadedSnapshot.voltageMillivolts)
        XCTAssertNil(loadedSnapshot.currentMilliampsSigned)
        XCTAssertNil(loadedSnapshot.dischargeRateMilliamps)
        XCTAssertNil(loadedSnapshot.chargeRateWatts)
        XCTAssertNil(loadedSnapshot.dischargeRateWatts)
        XCTAssertNil(loadedSnapshot.cycleCount)
        XCTAssertNil(loadedSnapshot.adapterMaxWatts)
    }

    func testWidgetSnapshotStoreRecomputesStaleZeroMaximumEnergyValues() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 0,
            currentChargeWattHours: 0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 0,
            healthPercent: 83,
            stateOfChargePercent: 0,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.currentChargeWattHours, 0)
        XCTAssertEqual(loadedSnapshot.fullChargeCapacityWattHours, 60)
        XCTAssertEqual(loadedSnapshot.designCapacityWattHours, 72)
    }

    func testWidgetSnapshotStoreClampsSmallCurrentChargeOverage() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 5_050,
            currentChargeWattHours: 60.6,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72,
            healthPercent: 83,
            stateOfChargePercent: nil,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.currentChargeMilliampHours, 5_000)
        XCTAssertEqual(loadedSnapshot.fullChargeCapacityMilliampHours, 5_000)
        XCTAssertEqual(loadedSnapshot.currentChargeWattHours, 60)
        XCTAssertEqual(loadedSnapshot.fullChargeCapacityWattHours, 60)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, 100)
    }

    func testWidgetSnapshotStoreDropsStaleAdapterWattageWhenOnBattery() throws {
        let store = try makeWidgetSnapshotStore()

        store.save(makeLowBatterySnapshot())

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .onBattery)
        XCTAssertNil(loadedSnapshot.adapterMaxWatts)
    }

    func testWidgetSnapshotStorePreservesAdapterWattageWhenPluggedIn() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .connectedNotCharging,
            isCharging: false,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 39.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .connectedNotCharging)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 70)
    }

    func testWidgetSnapshotStoreRecomputesStaleStoredChargeRateFromCurrentAndVoltage() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 5_500,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 100,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 100,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 100)
        XCTAssertEqual(loadedSnapshot.chargeRateWatts, 66)
        XCTAssertEqual(loadedSnapshot.activePowerWatts, 66)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "66.0 W")
    }

    func testWidgetSnapshotStoreRejectsChargeRateAboveAdapterContract() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 8_333,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 100,
            inputPowerWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 70)
        XCTAssertNil(loadedSnapshot.chargeRateWatts)
        XCTAssertNil(loadedSnapshot.activePowerWatts)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "—")
    }

    func testWidgetSnapshotStoreRejectsStoredChargeRateThatMirrorsAdapterCapability() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 8_333,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 100,
            inputPowerWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 100,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 100)
        XCTAssertNil(loadedSnapshot.chargeRateWatts)
        XCTAssertNil(loadedSnapshot.activePowerWatts)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "—")
    }

    func testWidgetSnapshotStoreRejectsUnverifiedHighStoredChargeRateWithoutAdapterCapability() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 8_333,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 100,
            inputPowerWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: nil,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.adapterMaxWatts)
        XCTAssertNil(loadedSnapshot.chargeRateWatts)
        XCTAssertNil(loadedSnapshot.activePowerWatts)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "—")
    }

    func testWidgetSnapshotStoreDropsLegacyChargeRateWithoutCurrentEvidence() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 100,
            inputPowerWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 70)
        XCTAssertNil(loadedSnapshot.chargeRateWatts)
        XCTAssertNil(loadedSnapshot.activePowerWatts)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "—")
    }

    func testWidgetSnapshotStorePreservesInputPowerButDisplaysChargeRateWhileCharging() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_044,
            currentMilliampsSigned: 2_111,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 25.424884,
            inputPowerWatts: 39.8,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.chargeRateWatts), 25.424884, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.inputPowerWatts), 39.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 39.8, accuracy: 0.001)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "39.8 W")
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: loadedSnapshot), "Input Power")
    }

    func testWidgetSnapshotStoreRejectsInputPowerAboveAdapterCapability() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_044,
            currentMilliampsSigned: 2_111,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 25.424884,
            inputPowerWatts: 100,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertNil(loadedSnapshot.inputPowerWatts)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 25.424884, accuracy: 0.001)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "25.4 W")
    }

    func testWidgetSnapshotStoreDerivesMissingStoredChargeRateFromCurrentAndVoltage() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 5_500,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertEqual(loadedSnapshot.chargeRateWatts, 66)
        XCTAssertEqual(loadedSnapshot.activePowerWatts, 66)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "66.0 W")
    }

    func testWidgetSnapshotStoreDerivesMissingStoredDischargeRateFromCurrentAndVoltage() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: nil,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .onBattery)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.dischargeRateWatts), 14.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 14.4, accuracy: 0.001)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "14.4 W")
    }

    func testWidgetSnapshotStoreDropsStaleTimingAndPowerForIdleStates() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .connectedNotCharging,
            isCharging: false,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 39.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: nil,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 18,
            dischargeRateWatts: 14,
            rateBasedTimeRemainingMinutes: 25,
            systemTimeRemainingMinutes: 24,
            timeToFullMinutes: 20,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.powerState, .connectedNotCharging)
        XCTAssertNil(loadedSnapshot.chargeRateWatts)
        XCTAssertNil(loadedSnapshot.dischargeRateWatts)
        XCTAssertNil(loadedSnapshot.rateBasedTimeRemainingMinutes)
        XCTAssertNil(loadedSnapshot.systemTimeRemainingMinutes)
        XCTAssertNil(loadedSnapshot.timeToFullMinutes)
        XCTAssertNil(loadedSnapshot.displayedTimeMinutes)
        XCTAssertNil(loadedSnapshot.activePowerWatts)
        XCTAssertEqual(loadedSnapshot.adapterMaxWatts, 70)
    }

    func testWidgetSnapshotStoreSanitizesOlderPersistedSnapshotOnRead() throws {
        let store = try makeWidgetSnapshotStore()
        let defaults = try XCTUnwrap(store.defaults)
        let rawSnapshot = makeOutOfRangeSnapshot()
        let rawData = try JSONEncoder().encode(rawSnapshot)
        defaults.set(rawData, forKey: "latestBatteryWidgetSnapshot")

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))

        XCTAssertNil(loadedSnapshot.currentChargeMilliampHours)
        XCTAssertNil(loadedSnapshot.healthPercent)
        XCTAssertNil(loadedSnapshot.stateOfChargePercent)
        XCTAssertNil(loadedSnapshot.temperatureCelsius)
        let rewrittenData = try XCTUnwrap(defaults.data(forKey: "latestBatteryWidgetSnapshot"))
        XCTAssertNotEqual(rewrittenData, rawData)
    }

    func testWidgetSnapshotStoreReadsLegacySnapshotWithoutInputPowerField() throws {
        let store = try makeWidgetSnapshotStore()
        let defaults = try XCTUnwrap(store.defaults)
        let rawSnapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 1_500,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 18,
            inputPowerWatts: 39.8,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )
        let encodedData = try JSONEncoder().encode(rawSnapshot)
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        dictionary.removeValue(forKey: "inputPowerWatts")
        let legacyData = try JSONSerialization.data(withJSONObject: dictionary)
        defaults.set(legacyData, forKey: "latestBatteryWidgetSnapshot")

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))

        XCTAssertEqual(loadedSnapshot.powerState, .charging)
        XCTAssertNil(loadedSnapshot.inputPowerWatts)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 18, accuracy: 0.001)
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: loadedSnapshot), "Charge Rate")
    }

    func testWidgetSnapshotStoreTreatsLegacyInputPowerWithoutEvidenceAsUntrusted() throws {
        let store = try makeWidgetSnapshotStore()
        let defaults = try XCTUnwrap(store.defaults)
        let rawSnapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 2_111,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 25.424884,
            inputPowerWatts: 100,
            inputPowerEvidence: .counterBacked,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 100,
            notes: []
        )
        let encodedData = try JSONEncoder().encode(rawSnapshot)
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        dictionary.removeValue(forKey: "inputPowerEvidence")
        let legacyData = try JSONSerialization.data(withJSONObject: dictionary)
        defaults.set(legacyData, forKey: "latestBatteryWidgetSnapshot")

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))

        XCTAssertNil(loadedSnapshot.inputPowerEvidence)
        XCTAssertNil(loadedSnapshot.inputPowerWatts)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 25.332, accuracy: 0.001)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "25.3 W")
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: loadedSnapshot), "Charge Rate")
    }

    func testWidgetSnapshotStorePreservesCurrentDerivedChargeRateNearAdapterCapability() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 5_785,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 69.42,
            inputPowerWatts: nil,
            inputPowerEvidence: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 18,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.inputPowerWatts)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.chargeRateWatts), 69.42, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 69.42, accuracy: 0.001)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "69.4 W")
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: loadedSnapshot), "Charge Rate")
    }

    func testWidgetSnapshotStorePreservesCounterBackedInputPowerNearAdapterCapability() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 2_111,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 25.424884,
            inputPowerWatts: 69.42,
            inputPowerEvidence: .counterBacked,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.inputPowerEvidence, .counterBacked)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.inputPowerWatts), 69.42, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 69.42, accuracy: 0.001)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "69.4 W")
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: loadedSnapshot), "Input Power")
    }

    func testWidgetSnapshotStoreRejectsCounterBackedInputPowerThatExactlyMirrorsAdapterCapability() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 2_111,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 25.332,
            inputPowerWatts: 100,
            inputPowerEvidence: .counterBacked,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 100,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.inputPowerEvidence)
        XCTAssertNil(loadedSnapshot.inputPowerWatts)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 25.332, accuracy: 0.001)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "25.3 W")
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: loadedSnapshot), "Charge Rate")
    }

    func testWidgetSnapshotStoreRejectsCounterBackedInputPowerThatNearlyMirrorsAdapterCapability() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 2_111,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 25.332,
            inputPowerWatts: 99.8,
            inputPowerEvidence: .counterBacked,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 100,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.inputPowerEvidence)
        XCTAssertNil(loadedSnapshot.inputPowerWatts)
        XCTAssertEqual(try XCTUnwrap(loadedSnapshot.activePowerWatts), 25.332, accuracy: 0.001)
        XCTAssertEqual(BatteryWidgetMetricFormatting.powerText(for: loadedSnapshot), "25.3 W")
        XCTAssertEqual(BatteryMediumWidgetFormatting.powerTitle(for: loadedSnapshot), "Charge Rate")
    }

    func testWidgetSnapshotStorePreservesExplicitMissingChargeRateMarkerWhenSanitizing() throws {
        let store = try makeWidgetSnapshotStore()
        let defaults = try XCTUnwrap(store.defaults)
        let rawSnapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 150,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: 5_500,
            dischargeRateMilliamps: nil,
            chargeRateWatts: nil,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 60,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )
        let encodedData = try JSONEncoder().encode(rawSnapshot)
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        dictionary["chargeRateWatts"] = NSNull()
        let legacyData = try JSONSerialization.data(withJSONObject: dictionary)
        defaults.set(legacyData, forKey: "latestBatteryWidgetSnapshot")

        let firstRead = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(firstRead.chargeRateWatts)
        XCTAssertNil(firstRead.activePowerWatts)
        XCTAssertEqual(try XCTUnwrap(firstRead.healthPercent), 83.33333333333334, accuracy: 0.001)

        let rewrittenData = try XCTUnwrap(defaults.data(forKey: "latestBatteryWidgetSnapshot"))
        let rewrittenDictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: rewrittenData) as? [String: Any])
        XCTAssertTrue(rewrittenDictionary["chargeRateWatts"] is NSNull)

        let secondRead = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_031), maximumAge: 60))
        XCTAssertNil(secondRead.chargeRateWatts)
        XCTAssertNil(secondRead.activePowerWatts)
    }

    func testWidgetSnapshotStoreClampsSmallPercentOverages() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 5_000,
            currentChargeWattHours: 65.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 4_900,
            designCapacityWattHours: 63.7,
            healthPercent: 100.2,
            stateOfChargePercent: 105,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 25,
            systemTimeRemainingMinutes: 24,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.healthPercent, 100)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, 100)
    }

    func testWidgetSnapshotStoreDerivesImpossibleChargeOverageFromValidCapacity() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 5_000,
            currentChargeWattHours: 65.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 4_900,
            designCapacityWattHours: 63.7,
            healthPercent: 119,
            stateOfChargePercent: 119,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 25,
            systemTimeRemainingMinutes: 24,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.healthPercent, 100)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, 100)
    }

    func testWidgetSnapshotStoreRoundTripsSnapshotWithDateComponents() throws {
        let store = try makeWidgetSnapshotStore()
        let manufactureDate = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2023, month: 9, day: 12)))
        let snapshotDate = Date(timeIntervalSince1970: 1_735_689_600)
        let snapshot = BatterySnapshot(
            timestamp: snapshotDate,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: manufactureDate,
            batteryAgeComponents: DateComponents(year: 99, month: 99),
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: snapshot.timestamp.addingTimeInterval(30), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.manufactureDate, snapshot.manufactureDate)
        XCTAssertEqual(loadedSnapshot.batteryAgeComponents?.year, 1)
        XCTAssertEqual(loadedSnapshot.batteryAgeComponents?.month, 3)
    }

    func testWidgetSnapshotStoreRefreshesStoredBatteryAgeAgainstReadDate() throws {
        let store = try makeWidgetSnapshotStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let manufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let snapshotDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2024,
            month: 1,
            day: 31,
            hour: 23,
            minute: 30
        )))
        let readDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2024,
            month: 2,
            day: 1,
            hour: 0,
            minute: 30
        )))
        let snapshot = BatterySnapshot(
            timestamp: snapshotDate,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: manufactureDate,
            batteryAgeComponents: DateComponents(year: 99, month: 99),
            temperatureCelsius: 32,
            adapterMaxWatts: nil,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: readDate, maximumAge: 2 * 60 * 60))
        XCTAssertEqual(loadedSnapshot.timestamp, snapshotDate)
        XCTAssertEqual(loadedSnapshot.manufactureDate, manufactureDate)
        XCTAssertEqual(loadedSnapshot.batteryAgeComponents?.year, 0)
        XCTAssertEqual(loadedSnapshot.batteryAgeComponents?.month, 1)

        let storedData = try XCTUnwrap(store.defaults?.data(forKey: "latestBatteryWidgetSnapshot"))
        let storedSnapshot = try JSONDecoder().decode(BatterySnapshot.self, from: storedData)
        XCTAssertEqual(storedSnapshot.batteryAgeComponents?.year, 0)
        XCTAssertEqual(storedSnapshot.batteryAgeComponents?.month, 1)
    }

    func testWidgetSnapshotStoreRejectsFutureManufactureDateAndOrphanAge() throws {
        let store = try makeWidgetSnapshotStore()
        let snapshot = BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: Date(timeIntervalSince1970: 2_000),
            batteryAgeComponents: DateComponents(year: 2, month: 3),
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.manufactureDate)
        XCTAssertNil(loadedSnapshot.batteryAgeComponents)
    }

    func testWidgetSnapshotStoreRejectsImplausiblyOldManufactureDateAndOrphanAge() throws {
        let store = try makeWidgetSnapshotStore()
        let calendar = Calendar(identifier: .gregorian)
        let snapshotDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28)))
        let oldManufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2005, month: 12, day: 31)))
        let snapshot = BatterySnapshot(
            timestamp: snapshotDate,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: oldManufactureDate,
            batteryAgeComponents: DateComponents(year: 6, month: 6),
            temperatureCelsius: 32,
            adapterMaxWatts: 70,
            notes: []
        )

        store.save(snapshot)

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: snapshotDate.addingTimeInterval(30), maximumAge: 60))
        XCTAssertNil(loadedSnapshot.manufactureDate)
        XCTAssertNil(loadedSnapshot.batteryAgeComponents)
    }

    func testWidgetSnapshotStoreClearsUndecodableSnapshot() throws {
        let store = try makeWidgetSnapshotStore()
        let defaults = try XCTUnwrap(store.defaults)
        defaults.set(Data("not-json".utf8), forKey: "latestBatteryWidgetSnapshot")

        XCTAssertNil(store.snapshot(now: Date(timeIntervalSince1970: 1_500), maximumAge: 60))
        XCTAssertNil(defaults.data(forKey: "latestBatteryWidgetSnapshot"))
    }

    func testWidgetSnapshotStoreDoesNotFallBackToStandardDefaultsWhenSharedSuiteIsUnavailable() {
        let key = "latestBatteryWidgetSnapshot"
        let previousStandardValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let previousStandardValue {
                UserDefaults.standard.set(previousStandardValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)

        let store = BatteryWidgetSnapshotStore(defaults: nil)
        store.save(makeLowBatterySnapshot())

        XCTAssertNil(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    func testWidgetSnapshotStoreClearDoesNotSynchronizeWhenAlreadyEmpty() throws {
        let suiteName = "BatteryStatsTests.BatteryWidgetSnapshotStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(TrackingWidgetUserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.resetTracking()
        let store = BatteryWidgetSnapshotStore(defaults: defaults)

        store.clear()

        XCTAssertEqual(defaults.removeObjectCallCount, 0)
        XCTAssertEqual(defaults.synchronizeCallCount, 0)

        store.save(makeLowBatterySnapshot())
        defaults.resetTracking()

        store.clear()

        XCTAssertEqual(defaults.removeObjectCallCount, 1)
        XCTAssertEqual(defaults.synchronizeCallCount, 1)
    }

    func testRefreshPublishesSharedWidgetSnapshot() async throws {
        let store = try makeWidgetSnapshotStore()
        let publicationDate = Date(timeIntervalSince1970: 1_000)
        let snapshot = makeLowBatterySnapshot()
        let reader = StubBatteryReader(snapshots: [snapshot])
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetSnapshotStore: store,
            widgetTimelineReloader: {},
            now: { publicationDate }
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: publicationDate.addingTimeInterval(30), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, snapshot.stateOfChargePercent)
    }

    func testRefreshPublishesOneTimestampAcrossMainHistoryAndWidgetSurfaces() async throws {
        let store = try makeWidgetSnapshotStore()
        let historyStore = try makeHistoryStore()
        let sampleDate = Date(timeIntervalSince1970: 1_000)
        let publicationDate = Date(timeIntervalSince1970: 2_000)
        let snapshot = makeLowBatterySnapshot(timestamp: sampleDate)
        let reader = StubBatteryReader(snapshots: [snapshot])
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            widgetSnapshotStore: store,
            widgetTimelineReloader: {},
            now: { publicationDate }
        )
        monitor.updateHistory(
            store: historyStore,
            policy: BatteryHistoryPolicy(isEnabled: true, syncsToICloud: false)
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertEqual(monitor.lastUpdated, publicationDate)
        XCTAssertEqual(monitor.snapshot?.timestamp, publicationDate)
        XCTAssertEqual(historyStore.entries.first?.timestamp, publicationDate)
        let requestDates = await reader.requestDates
        XCTAssertEqual(requestDates, [publicationDate])

        let loadedSnapshot = try XCTUnwrap(store.snapshot(now: publicationDate.addingTimeInterval(30), maximumAge: 60))
        XCTAssertEqual(loadedSnapshot.timestamp, publicationDate)
        XCTAssertNotEqual(loadedSnapshot.timestamp, sampleDate)
        XCTAssertEqual(loadedSnapshot.stateOfChargePercent, snapshot.stateOfChargePercent)
    }

    func testUnsupportedRefreshClearsSharedWidgetSnapshot() async throws {
        let store = try makeWidgetSnapshotStore()
        store.save(makeLowBatterySnapshot())

        let monitor = BatteryMonitor(
            reader: BatteryReadingClient(
                read: { _, _ in
                    BatteryReadResult(snapshot: nil, rawSnapshotText: nil, parsedSnapshotText: nil)
                },
                makeNotificationToken: { _ in
                    nil
                }
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: {}
        )

        monitor.refresh()
        await monitor.waitForIdleForTesting()

        XCTAssertNil(store.snapshot(now: Date(timeIntervalSince1970: 1_030), maximumAge: 60))
    }

    func testAlertPolicyChangeClearsStaleActiveAlertState() async {
        let reader = StubBatteryReader(snapshots: [makeLowBatterySnapshot()])
        let deliverer = MonitorFakeBatteryAlertNotificationDeliverer()
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            alertCoordinator: coordinator,
            widgetTimelineReloader: {}
        )
        let enabledPolicy = BatteryAlertPolicy(isLowBatteryAlertEnabled: true)

        monitor.updateAlerts(enabledPolicy)
        monitor.refresh()
        await monitor.waitForIdleForTesting()
        await coordinator.waitForIdleForTesting()
        monitor.updateAlerts(.disabled)
        monitor.updateAlerts(enabledPolicy)
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(
            deliverer.notifications.map(\.identifier),
            ["BatteryStats.LowBattery", "BatteryStats.LowBattery"]
        )
    }

    func testUnsupportedRefreshClearsStaleActiveAlertState() async {
        let reader = ControlledDiagnosticsReader()
        let deliverer = MonitorFakeBatteryAlertNotificationDeliverer()
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let monitor = BatteryMonitor(
            reader: makeClient(reader),
            alertCoordinator: coordinator,
            widgetTimelineReloader: {}
        )
        let enabledPolicy = BatteryAlertPolicy(isLowBatteryAlertEnabled: true)

        monitor.updateAlerts(enabledPolicy)

        monitor.refresh()
        await reader.waitForRequestCount(1)
        reader.resumeRequest(at: 0, snapshot: makeLowBatterySnapshot())
        await monitor.waitForIdleForTesting()
        await coordinator.waitForIdleForTesting()

        monitor.refresh()
        await reader.waitForRequestCount(2)
        reader.resumeRequest(at: 1, snapshot: nil)
        await monitor.waitForIdleForTesting()

        monitor.refresh()
        await reader.waitForRequestCount(3)
        reader.resumeRequest(at: 2, snapshot: makeLowBatterySnapshot(timestamp: Date(timeIntervalSince1970: 1_060)))
        await monitor.waitForIdleForTesting()
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(
            deliverer.notifications.map(\.identifier),
            ["BatteryStats.LowBattery", "BatteryStats.LowBattery"]
        )
    }

    private func makeMonitor(_ reader: StubBatteryReader) -> BatteryMonitor {
        BatteryMonitor(reader: makeClient(reader), widgetTimelineReloader: {})
    }

    private func enableEnergyProbeDemand(on monitor: BatteryMonitor) {
        monitor.updateMonitoringDemand(BatteryMonitoringDemand(needsEnergyChangeAwareness: true))
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

    private func makeClient(_ reader: ControlledDiagnosticsReader) -> BatteryReadingClient {
        BatteryReadingClient(
            read: { date, options in
                await reader.read(at: date, options: options)
            },
            makeNotificationToken: { _ in
                nil
            }
        )
    }

    private func makeWidgetSnapshotStore() throws -> BatteryWidgetSnapshotStore {
        let suiteName = "BatteryStatsTests.BatteryWidgetSnapshotStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return BatteryWidgetSnapshotStore(defaults: defaults)
    }

    private func makeHistoryStore() throws -> BatteryHistoryStore {
        let suiteName = "BatteryStatsTests.BatteryHistoryStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return BatteryHistoryStore(defaults: defaults)
    }

    private func makePreferencesStore() throws -> PreferencesStore {
        let suiteName = "BatteryStatsTests.PreferencesStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return PreferencesStore(defaults: defaults, sync: MonitorNoopPreferencesSync())
    }

    private func makeWidgetReloadSnapshot(
        stateOfChargePercent: Double,
        healthPercent: Double = 83
    ) -> BatterySnapshot {
        return BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 1_000,
            currentChargeWattHours: 12.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78.0,
            healthPercent: healthPercent,
            stateOfChargePercent: stateOfChargePercent,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 50,
            systemTimeRemainingMinutes: 50,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )
    }

    private func makeEnergyProbeSnapshot(
        powerState: BatteryPowerState,
        stateOfChargePercent: Double,
        powerWatts: Double,
        timeToFullMinutes: Int = 82,
        healthPercent: Double = 83,
        currentMilliamps: Int = 1_200,
        voltageMillivolts: Int = 12_000,
        temperatureCelsius: Double = 32.0,
        cycleCount: Int = 120,
        currentChargeMilliampHours: Int = 3_050,
        currentChargeWattHours: Double = 39.6,
        fullChargeCapacityMilliampHours: Int = 5_000,
        fullChargeCapacityWattHours: Double = 65.0,
        designCapacityMilliampHours: Int = 6_000,
        designCapacityWattHours: Double = 78.0,
        inputPowerWatts: Double? = nil
    ) -> BatterySnapshot {
        let isDischarging = powerState == .onBattery || powerState == .connectedDischarging

        return BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: powerState,
            isCharging: powerState == .charging,
            isExternalPowerConnected: powerState != .onBattery,
            currentChargeMilliampHours: currentChargeMilliampHours,
            currentChargeWattHours: currentChargeWattHours,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours,
            fullChargeCapacityWattHours: fullChargeCapacityWattHours,
            designCapacityMilliampHours: designCapacityMilliampHours,
            designCapacityWattHours: designCapacityWattHours,
            healthPercent: healthPercent,
            stateOfChargePercent: stateOfChargePercent,
            voltageMillivolts: voltageMillivolts,
            currentMilliampsSigned: powerState == .charging ? currentMilliamps : (isDischarging ? -currentMilliamps : nil),
            dischargeRateMilliamps: isDischarging ? currentMilliamps : nil,
            chargeRateWatts: powerState == .charging ? powerWatts : nil,
            inputPowerWatts: powerState == .onBattery ? nil : inputPowerWatts,
            dischargeRateWatts: isDischarging ? powerWatts : nil,
            rateBasedTimeRemainingMinutes: isDischarging ? 154 : nil,
            systemTimeRemainingMinutes: isDischarging ? 150 : nil,
            timeToFullMinutes: powerState == .charging ? timeToFullMinutes : nil,
            cycleCount: cycleCount,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: temperatureCelsius,
            adapterMaxWatts: powerState == .onBattery ? nil : 70,
            notes: []
        )
    }

    private func makeNonFiniteSnapshot() -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 40.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78.0,
            healthPercent: .infinity,
            stateOfChargePercent: .nan,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: .infinity,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )
    }

    private func makeOutOfRangeSnapshot() -> BatterySnapshot {
        BatterySnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: -1,
            currentChargeWattHours: -1,
            fullChargeCapacityMilliampHours: 0,
            fullChargeCapacityWattHours: -65.0,
            designCapacityMilliampHours: -6_000,
            designCapacityWattHours: -78.0,
            healthPercent: 150,
            stateOfChargePercent: -4,
            voltageMillivolts: 250_000,
            currentMilliampsSigned: .max,
            dischargeRateMilliamps: 2_000_000,
            chargeRateWatts: -14.4,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: -25,
            systemTimeRemainingMinutes: -24,
            timeToFullMinutes: -1,
            cycleCount: -120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 180,
            adapterMaxWatts: -70,
            notes: []
        )
    }

    private func makeLowBatterySnapshot(timestamp: Date = Date(timeIntervalSince1970: 1_000)) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: timestamp,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 500,
            currentChargeWattHours: 6.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 65.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 78.0,
            healthPercent: 83,
            stateOfChargePercent: 10,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: 14.4,
            rateBasedTimeRemainingMinutes: 25,
            systemTimeRemainingMinutes: 24,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )
    }

    private func makeTemperatureSnapshot(
        celsius: Double,
        powerWatts: Double,
        timestamp: Date = Date(timeIntervalSince1970: 1_000)
    ) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: timestamp,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 3_000,
            currentChargeWattHours: 36.0,
            fullChargeCapacityMilliampHours: 5_000,
            fullChargeCapacityWattHours: 60.0,
            designCapacityMilliampHours: 6_000,
            designCapacityWattHours: 72.0,
            healthPercent: 83,
            stateOfChargePercent: 60,
            voltageMillivolts: 12_000,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: nil,
            dischargeRateWatts: powerWatts,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            timeToFullMinutes: nil,
            cycleCount: 120,
            manufactureDate: nil,
            batteryAgeComponents: nil,
            temperatureCelsius: celsius,
            adapterMaxWatts: nil,
            notes: []
        )
    }
}

@MainActor
private final class MonitorFakeBatteryAlertNotificationDeliverer: BatteryAlertNotificationDelivering {
    private(set) var notifications: [BatteryAlertNotification] = []

    func deliver(_ notification: BatteryAlertNotification) async -> Bool {
        notifications.append(notification)
        return true
    }
}

@MainActor
private final class MonitorNoopPreferencesSync: PreferencesSyncing {
    var isEnabled = false
    var isAvailable = true
    var isICloudAccountAvailable = true
    var availabilityDescription = "iCloud is available for tests."

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol {
        NSObject()
    }

    func removeObserver(_ token: NSObjectProtocol) {}

    func hasValue(forKey key: String) -> Bool {
        false
    }

    func bool(forKey key: String) -> Bool? {
        nil
    }

    func string(forKey key: String) -> String? {
        nil
    }

    func set(_ value: Bool, forKey key: String) {}

    func set(_ value: String, forKey key: String) {}

    func removeValue(forKey key: String) {}

    func flush() {}
}

private final class TrackingWidgetUserDefaults: UserDefaults {
    private(set) var removeObjectCallCount = 0
    private(set) var synchronizeCallCount = 0

    override func removeObject(forKey defaultName: String) {
        removeObjectCallCount += 1
        super.removeObject(forKey: defaultName)
    }

    override func synchronize() -> Bool {
        synchronizeCallCount += 1
        return super.synchronize()
    }

    func resetTracking() {
        removeObjectCallCount = 0
        synchronizeCallCount = 0
    }
}

private actor StubBatteryReader {
    private let delayNanoseconds: UInt64
    private var snapshots: [BatterySnapshot]
    private(set) var requests: [BatteryReadOptions] = []
    private(set) var requestDates: [Date] = []

    init(delayNanoseconds: UInt64 = 0, snapshots: [BatterySnapshot]) {
        self.delayNanoseconds = delayNanoseconds
        self.snapshots = snapshots
    }

    var requestCount: Int {
        requests.count
    }

    func read(at date: Date, options: BatteryReadOptions) async -> BatteryReadResult {
        requests.append(options)
        requestDates.append(date)

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

@MainActor
private final class ControlledDiagnosticsReader {
    private var continuations: [CheckedContinuation<BatteryReadResult, Never>?] = []
    private(set) var requests: [BatteryReadOptions] = []
    private(set) var requestDates: [Date] = []

    func read(at date: Date, options: BatteryReadOptions) async -> BatteryReadResult {
        requests.append(options)
        requestDates.append(date)

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while requests.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func resumeRequest(at index: Int, rawSnapshotText: String) {
        resumeRequest(
            at: index,
            snapshot: .previewDischarging,
            rawSnapshotText: rawSnapshotText,
            parsedSnapshotText: "parsed \(rawSnapshotText)"
        )
    }

    func resumeRequest(
        at index: Int,
        snapshot: BatterySnapshot?,
        rawSnapshotText: String? = nil,
        parsedSnapshotText: String? = nil
    ) {
        guard continuations.indices.contains(index),
              let continuation = continuations[index] else {
            return
        }

        continuations[index] = nil
        continuation.resume(returning: BatteryReadResult(
            snapshot: snapshot,
            rawSnapshotText: rawSnapshotText,
            parsedSnapshotText: parsedSnapshotText
        ))
    }
}
