import XCTest
@testable import BatteryStats

final class FormatterTests: XCTestCase {
    func testFormatsMilliampHours() {
        XCTAssertEqual(BatteryFormatting.milliampHours(5_338), "5,338 mAh")
        XCTAssertEqual(BatteryFormatting.milliampHours(0), "0 mAh")
        XCTAssertEqual(BatteryFormatting.milliampHours(0, allowsZero: false), "Unavailable")
    }

    func testFormatsImpossiblePhysicalValuesAsUnavailable() {
        XCTAssertEqual(BatteryFormatting.milliampHours(-1), "Unavailable")
        XCTAssertEqual(BatteryFormatting.milliampHours(Int.max), "Unavailable")
        XCTAssertEqual(BatteryFormatting.millivolts(-12_000), "Unavailable")
        XCTAssertEqual(BatteryFormatting.millivolts(Int.max), "Unavailable")
        XCTAssertEqual(BatteryFormatting.compactWattHours(-4.2), "Unavailable")
        XCTAssertEqual(BatteryFormatting.compactWattHours(.greatestFiniteMagnitude), "Unavailable")
        XCTAssertEqual(BatteryFormatting.watts(-4.2), "Unavailable")
        XCTAssertEqual(BatteryFormatting.watts(0), "Unavailable")
        XCTAssertEqual(BatteryFormatting.watts(0.09), "Unavailable")
        XCTAssertEqual(BatteryFormatting.watts(.greatestFiniteMagnitude), "Unavailable")
        XCTAssertEqual(BatteryFormatting.milliamps(Int.max), "Unavailable")
        XCTAssertEqual(BatteryFormatting.signedMilliamps(Int.max), "Unavailable")
        XCTAssertEqual(BatteryFormatting.temperature(180, unitPreference: .celsius), "Unavailable")
    }

    func testFormatsSmallestDisplayablePowerWithoutRoundedZero() {
        XCTAssertEqual(BatteryFormatting.watts(0.1), "0.1 W")
    }

    func testFormatsAdapterWatts() {
        XCTAssertEqual(BatteryFormatting.adapterWatts(70), "70 W")
        XCTAssertNil(BatteryFormatting.adapterWatts(-70))
        XCTAssertNil(BatteryFormatting.adapterWatts(Int.max))
    }

    func testFormatsCompactCapacityPair() {
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 4_912, maximum: 5_338),
            "4,912 / 5,338 mAh"
        )
    }

    func testFormatsCompactCapacityPairWithPartialValues() {
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 4_912, maximum: nil),
            "4,912 mAh"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: nil, maximum: 5_338),
            "5,338 mAh max"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: -1, maximum: 5_338),
            "5,338 mAh max"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: Int.max, maximum: 5_338),
            "5,338 mAh max"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 4_912, maximum: 0),
            "4,912 mAh"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: nil, maximum: 0),
            "Unavailable"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: nil, maximum: nil),
            "Unavailable"
        )
    }

    func testCompactCapacityPairKeepsSmallMeasuredOverMaximumValues() {
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 4_641, maximum: 4_629, currentAllowsZero: false),
            "4,641 / 4,629 mAh"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 5_050, maximum: 5_000),
            "5,050 / 5,000 mAh"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 6_000, maximum: 5_000),
            "5,000 mAh max"
        )
    }

    func testCompactCapacityPairCanTreatZeroCurrentAsUnavailableForMaximumLikeCapacities() {
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 0, maximum: 5_338),
            "0 / 5,338 mAh"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 0, maximum: 5_338, currentAllowsZero: false),
            "5,338 mAh max"
        )
        XCTAssertEqual(
            BatteryFormatting.compactCapacityPair(current: 0, maximum: nil, currentAllowsZero: false),
            "Unavailable"
        )
    }

    func testFormatsPercentWithOneDecimal() {
        XCTAssertEqual(BatteryFormatting.percent(81.38, decimals: 1), "81.4%")
    }

    func testFormatsNonFinitePercentAsUnavailable() {
        XCTAssertEqual(BatteryFormatting.percent(.nan), "Unavailable")
    }

    func testFormatsOutOfRangePercentAsUnavailable() {
        XCTAssertEqual(BatteryFormatting.percent(-4), "Unavailable")
        XCTAssertEqual(BatteryFormatting.percent(150), "Unavailable")
    }

    func testFormatsCompactDuration() {
        XCTAssertEqual(BatteryFormatting.duration(minutes: 0), "0m")
        XCTAssertEqual(BatteryFormatting.compactDuration(minutes: 125), "2h 5m")
        XCTAssertEqual(BatteryFormatting.compactDuration(minutes: 45), "45m")
    }

    func testFormatsNegativeDurationsAsUnavailable() {
        XCTAssertEqual(BatteryFormatting.duration(minutes: -1), "Unavailable")
        XCTAssertEqual(BatteryFormatting.compactDuration(minutes: -1), "—")
        XCTAssertEqual(BatteryFormatting.compactWidgetDuration(minutes: -1), "—")
    }

    func testFormatsAbsurdDurationsAsUnavailable() {
        XCTAssertEqual(BatteryFormatting.duration(minutes: Int.max), "Unavailable")
        XCTAssertEqual(BatteryFormatting.compactDuration(minutes: Int.max), "—")
        XCTAssertEqual(BatteryFormatting.compactWidgetDuration(minutes: Int.max), "—")
    }

    func testFormatsWidgetDuration() {
        XCTAssertEqual(BatteryFormatting.compactWidgetDuration(minutes: 0), "0m")
        XCTAssertEqual(BatteryFormatting.compactWidgetDuration(minutes: 45), "45m")
        XCTAssertEqual(BatteryFormatting.compactWidgetDuration(minutes: 90), "1h30m")
        XCTAssertEqual(BatteryFormatting.compactWidgetDuration(minutes: 125), "2h5m")
        XCTAssertEqual(BatteryFormatting.compactWidgetDuration(minutes: nil), "—")
    }

    func testWidgetStoreUsesTeamPrefixedMacOSAppGroup() {
        XCTAssertEqual(
            BatteryWidgetSnapshotStore.appGroupIdentifier,
            "Q293G85PG5.io.github.agrim.batterystats"
        )
    }

    func testWidgetStoreDropsLegacyCapacityEnergyWhileKeepingCurrentChargeEstimate() throws {
        let defaults = makeIsolatedUserDefaults(prefix: "FormatterTests.WidgetCapacityEnergy").defaults
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = BatteryWidgetSnapshotStore(defaults: defaults)
        let legacySnapshot = """
        {
          "timestamp": 800000000,
          "powerState": "onBattery",
          "isCharging": false,
          "isExternalPowerConnected": false,
          "currentChargeMilliampHours": 3000,
          "currentChargeWattHours": 999,
          "fullChargeCapacityMilliampHours": 5000,
          "fullChargeCapacityWattHours": 65,
          "designCapacityMilliampHours": 6000,
          "designCapacityWattHours": 78,
          "stateOfChargePercent": 60,
          "voltageMillivolts": 12000,
          "manufactureDate": 700000000,
          "batteryAgeComponents": { "year": 9, "month": 9 },
          "notes": []
        }
        """
        defaults.set(try XCTUnwrap(legacySnapshot.data(using: .utf8)), forKey: "latestBatteryWidgetSnapshot")

        let stored = try XCTUnwrap(store.snapshot(now: now))
        XCTAssertEqual(try XCTUnwrap(stored.currentChargeWattHours), 36, accuracy: 0.001)
        XCTAssertEqual(stored.designCapacityMilliampHours, 6_000)
        let expectedAge = try XCTUnwrap(BatteryCalculations.batteryAgeComponents(
            from: Date(timeIntervalSinceReferenceDate: 700_000_000),
            now: now
        ))
        let storedAge = try XCTUnwrap(stored.validatedBatteryAgeComponents)
        XCTAssertEqual(storedAge.year, expectedAge.year)
        XCTAssertEqual(storedAge.month, expectedAge.month)
        let normalizedSnapshot = try XCTUnwrap(defaults.data(forKey: "latestBatteryWidgetSnapshot"))
        let normalizedJSON = try XCTUnwrap(String(data: normalizedSnapshot, encoding: .utf8))
        XCTAssertFalse(normalizedJSON.contains("currentChargeWattHours"))
        XCTAssertFalse(normalizedJSON.contains("fullChargeCapacityWattHours"))
        XCTAssertFalse(normalizedJSON.contains("designCapacityWattHours"))
        XCTAssertFalse(normalizedJSON.contains("batteryAgeComponents"))
    }

    func testWidgetTimeMetricKeepsUnavailableTimeProgressEmpty() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 80,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: -5,
            systemTimeRemainingMinutes: -3
        )

        XCTAssertNil(snapshot.displayedTimeMinutes)
        XCTAssertEqual(BatteryMetricFormatting.timeText(minutes: snapshot.displayedTimeMinutes), "—")
        XCTAssertNil(BatteryMetricFormatting.timeProgress(minutes: snapshot.displayedTimeMinutes))
    }

    func testWidgetPercentMetricTextTracksVisibleSnapshotValues() {
        XCTAssertEqual(BatteryMetricFormatting.percentText(83.3), "83%")
        XCTAssertEqual(BatteryMetricFormatting.percentText(100), "100%")
        XCTAssertEqual(BatteryMetricFormatting.percentText(105), "100%")
        XCTAssertEqual(BatteryMetricFormatting.percentText(nil), "—")
        XCTAssertEqual(BatteryMetricFormatting.percentText(.nan), "—")
        XCTAssertEqual(BatteryMetricFormatting.percentText(-4), "—")
    }

    func testWidgetPercentMetricProgressKeepsUnavailableDistinctFromZero() {
        XCTAssertNil(BatteryMetricFormatting.clampedProgress(nil))
        XCTAssertNil(BatteryMetricFormatting.clampedProgress(.nan))
        XCTAssertNil(BatteryMetricFormatting.clampedProgress(-4))
        XCTAssertEqual(BatteryMetricFormatting.clampedProgress(0), 0)
        XCTAssertEqual(BatteryMetricFormatting.clampedProgress(105), 1)
    }

    func testWidgetTimeMetricProgressUsesDisplayedTime() throws {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 80,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: 720
        )

        XCTAssertEqual(BatteryMetricFormatting.timeText(minutes: snapshot.displayedTimeMinutes), "12:00")
        XCTAssertEqual(try XCTUnwrap(BatteryMetricFormatting.timeProgress(minutes: snapshot.displayedTimeMinutes)), 0.5, accuracy: 0.001)
    }

    func testWidgetTimeMetricTextUsesHourMinuteClockFormat() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 80,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: 125
        )

        XCTAssertEqual(BatteryFormatting.compactDuration(minutes: snapshot.displayedTimeMinutes), "2h 5m")
        XCTAssertEqual(BatteryMetricFormatting.timeText(minutes: snapshot.displayedTimeMinutes), "2:05")
        XCTAssertEqual(BatteryMetricFormatting.timeText(minutes: 408), "6:48")
        XCTAssertEqual(BatteryMetricFormatting.timeText(minutes: 49), "0:49")
        XCTAssertEqual(BatteryMetricFormatting.timeText(minutes: nil), "—")
    }

    func testWidgetFreshnessUsesLiveSnapshotWithinFreshnessWindow() {
        let now = Date(timeIntervalSinceReferenceDate: 12_345)

        XCTAssertTrue(
            BatterySnapshotFreshnessPolicy.isLive(
                updatedAt: now.addingTimeInterval(-BatteryWidgetSnapshotStore.defaultMaximumAge),
                now: now
            )
        )
    }

    func testSnapshotFreshnessMarksRetainedSnapshotStale() {
        let now = Date(timeIntervalSinceReferenceDate: 12_345)

        XCTAssertFalse(
            BatterySnapshotFreshnessPolicy.isLive(
                updatedAt: now.addingTimeInterval(-(BatteryWidgetSnapshotStore.defaultMaximumAge + 1)),
                now: now
            )
        )
    }

    func testSnapshotFreshnessRejectsFarFutureSnapshot() {
        let now = Date(timeIntervalSinceReferenceDate: 12_345)

        XCTAssertFalse(
            BatterySnapshotFreshnessPolicy.isLive(
                updatedAt: now.addingTimeInterval(61),
                now: now
            )
        )
    }

    func testWidgetDisplayPolicyKeepsRetainedStaleSnapshotVisible() {
        let now = Date(timeIntervalSinceReferenceDate: 12_345)
        let updatedAt = now.addingTimeInterval(-12 * 60)

        XCTAssertFalse(BatterySnapshotFreshnessPolicy.isLive(updatedAt: updatedAt, now: now))
        XCTAssertTrue(BatteryWidgetSnapshotDisplayPolicy.isDisplayable(updatedAt: updatedAt, now: now))
    }

    func testWidgetDisplayPolicyRejectsSnapshotBeyondRetentionWindow() {
        let now = Date(timeIntervalSinceReferenceDate: 12_345)
        let updatedAt = now.addingTimeInterval(-(BatteryWidgetSnapshotStore.defaultRetentionAge + 1))

        XCTAssertFalse(BatteryWidgetSnapshotDisplayPolicy.isDisplayable(updatedAt: updatedAt, now: now))
    }

    func testWidgetTimeMetricProgressIsEmptyForZeroMinutes() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 100,
            powerState: .charging,
            timeToFullMinutes: 0
        )

        XCTAssertEqual(BatteryMetricFormatting.timeText(minutes: snapshot.displayedTimeMinutes), "0:00")
        XCTAssertEqual(BatteryMetricFormatting.timeProgress(minutes: snapshot.displayedTimeMinutes), 0)
    }

    func testWidgetPowerMetricDoesNotFallBackToStatusText() {
        let onBattery = makeSnapshot(stateOfChargePercent: 80, powerState: .onBattery)
        let connectedDischarging = makeSnapshot(stateOfChargePercent: 80, powerState: .connectedDischarging)
        let connectedNotCharging = makeSnapshot(stateOfChargePercent: 100, powerState: .connectedNotCharging)

        XCTAssertEqual(formattedActivePower(for: onBattery), "14.0 W")
        XCTAssertEqual(formattedActivePower(for: connectedDischarging), "14.0 W")
        XCTAssertEqual(formattedActivePower(for: connectedNotCharging), "—")
        XCTAssertEqual(formattedActivePower(for: nil), "—")
    }

    func testWidgetStatusMetricProgressIsEmptyForUnknownStatus() {
        let missingSnapshot: BatterySnapshot? = nil
        let unknown = makeSnapshot(stateOfChargePercent: 80, powerState: .unknown)
        let invalidOnBattery = makeSnapshot(stateOfChargePercent: .nan, powerState: .onBattery)

        XCTAssertNil(BatteryPresentationStyle.statusDescriptor(for: missingSnapshot).progress)
        XCTAssertNil(BatteryPresentationStyle.statusDescriptor(for: unknown).progress)
        XCTAssertNil(BatteryPresentationStyle.statusDescriptor(for: invalidOnBattery).progress)
    }

    func testWidgetStatusMetricProgressIsFullForKnownStatus() {
        let onBattery = makeSnapshot(stateOfChargePercent: 80, powerState: .onBattery)
        let lowBattery = makeSnapshot(stateOfChargePercent: 12, powerState: .onBattery)
        let charging = makeSnapshot(stateOfChargePercent: 80, powerState: .charging)
        let connectedDischarging = makeSnapshot(stateOfChargePercent: 80, powerState: .connectedDischarging)
        let connectedNotCharging = makeSnapshot(stateOfChargePercent: 100, powerState: .connectedNotCharging)
        let fullOnAC = makeSnapshot(stateOfChargePercent: 100, powerState: .fullOnAC)

        for snapshot in [onBattery, lowBattery, charging, connectedDischarging, connectedNotCharging, fullOnAC] {
            XCTAssertEqual(BatteryPresentationStyle.statusDescriptor(for: snapshot).progress, 1)
        }
    }

    func testWidgetUpdateTextDoesNotInventTimestampWithoutSnapshot() {
        let plan = BatteryWidgetTimelinePlan.make(
            snapshot: nil,
            now: Date(timeIntervalSinceReferenceDate: 12_345)
        )

        XCTAssertEqual(plan.entries.count, 1)
        XCTAssertFalse(plan.entries[0].snapshotIsDisplayable)
        XCTAssertNil(plan.reloadAfter)
    }

    func testWidgetUpdateTextUsesRelativeSnapshotTimestampWhenAvailable() {
        let now = Date(timeIntervalSinceReferenceDate: 12_345)

        XCTAssertEqual(BatterySnapshotFreshnessPolicy.relativeUpdateText(
            updatedAt: now.addingTimeInterval(-20), now: now
        ), "just now")
        XCTAssertEqual(BatterySnapshotFreshnessPolicy.relativeUpdateText(
            updatedAt: now.addingTimeInterval(-125), now: now
        ), "2m ago")
        let staleDate = now.addingTimeInterval(-720)
        XCTAssertEqual(BatterySnapshotFreshnessPolicy.relativeUpdateText(updatedAt: staleDate, now: now), "12m ago")
        XCTAssertFalse(BatterySnapshotFreshnessPolicy.isLive(updatedAt: staleDate, now: now))
    }

    func testWidgetUpdateTextHandlesFutureClockSkew() {
        let now = Date(timeIntervalSinceReferenceDate: 12_345)

        let toleratedDate = now.addingTimeInterval(30)
        let rejectedDate = now.addingTimeInterval(120)

        XCTAssertTrue(BatterySnapshotFreshnessPolicy.isWithinFutureSkew(updatedAt: toleratedDate, now: now))
        XCTAssertEqual(BatterySnapshotFreshnessPolicy.relativeUpdateText(updatedAt: toleratedDate, now: now), "just now")
        XCTAssertFalse(BatterySnapshotFreshnessPolicy.isWithinFutureSkew(updatedAt: rejectedDate, now: now))
    }

    func testWidgetCountdownUsesSnapshotTimeAsDeadlineAndDecays() throws {
        let now = Date(timeIntervalSinceReferenceDate: 12_000)
        let snapshot = makeSnapshot(
            stateOfChargePercent: 70,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: 90,
            timestamp: now
        )
        let countdown = try XCTUnwrap(BatteryWidgetCountdown(snapshot: snapshot))

        XCTAssertEqual(countdown.deadline, now.addingTimeInterval(90 * 60))
        XCTAssertEqual(countdown.remainingMinutes(at: now), 90)
        XCTAssertEqual(countdown.remainingMinutes(at: now.addingTimeInterval(5 * 60)), 85)
        XCTAssertEqual(countdown.remainingMinutes(at: now.addingTimeInterval(90 * 60)), 0)
        XCTAssertEqual(countdown.remainingMinutes(at: now.addingTimeInterval(2 * 60 * 60)), 0)
    }

    func testWidgetTimelineProjectsCountdownThroughRetentionAndExpiresSnapshot() throws {
        let now = Date(timeIntervalSinceReferenceDate: 12_000)
        let snapshot = makeSnapshot(
            stateOfChargePercent: 70,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: 90,
            timestamp: now
        )
        let plan = BatteryWidgetTimelinePlan.make(snapshot: snapshot, now: now)
        let displayExpiryDate = now.addingTimeInterval(BatteryWidgetSnapshotStore.defaultRetentionAge + 1)

        XCTAssertEqual(
            plan.entries.first { $0.date == now.addingTimeInterval(90 * 60) }?.displayedTimeMinutes,
            0
        )
        XCTAssertEqual(plan.entries.first?.date, now)
        XCTAssertTrue(try XCTUnwrap(plan.entries.first).snapshotIsDisplayable)
        XCTAssertEqual(plan.entries.first?.displayedTimeMinutes, 90)

        let fiveMinuteEntry = try XCTUnwrap(
            plan.entries.first { $0.date == now.addingTimeInterval(5 * 60) }
        )
        XCTAssertTrue(fiveMinuteEntry.snapshotIsDisplayable)
        XCTAssertEqual(fiveMinuteEntry.displayedTimeMinutes, 85)

        let retainedStaleEntry = try XCTUnwrap(
            plan.entries.first { $0.date == now.addingTimeInterval(15 * 60) }
        )
        XCTAssertFalse(BatterySnapshotFreshnessPolicy.isLive(updatedAt: snapshot.timestamp, now: retainedStaleEntry.date))
        XCTAssertTrue(retainedStaleEntry.snapshotIsDisplayable)
        XCTAssertEqual(retainedStaleEntry.displayedTimeMinutes, 75)

        XCTAssertEqual(plan.entries.last?.date, displayExpiryDate)
        XCTAssertFalse(try XCTUnwrap(plan.entries.last).snapshotIsDisplayable)
        XCTAssertNil(plan.entries.last?.displayedTimeMinutes)
        XCTAssertEqual(
            plan.reloadAfter,
            displayExpiryDate.addingTimeInterval(5 * 60)
        )

        for (earlier, later) in zip(plan.entries, plan.entries.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                later.date.timeIntervalSince(earlier.date),
                BatteryWidgetTimelinePlan.minimumEntryInterval
            )
        }
    }

    func testWidgetTimelineBackdatesCurrentEntryNearRetentionExpiry() {
        let now = Date(timeIntervalSinceReferenceDate: 12_000)
        let snapshotAge = BatteryWidgetSnapshotStore.defaultRetentionAge - 210
        let snapshot = makeSnapshot(
            stateOfChargePercent: 20,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: 360,
            timestamp: now.addingTimeInterval(-snapshotAge)
        )
        let displayExpiryDate = snapshot.timestamp.addingTimeInterval(
            BatteryWidgetSnapshotDisplayPolicy.maximumDisplayAge + 1
        )
        let plan = BatteryWidgetTimelinePlan.make(snapshot: snapshot, now: now)

        XCTAssertEqual(plan.entries.count, 2)
        XCTAssertEqual(plan.entries[0].date, displayExpiryDate.addingTimeInterval(-5 * 60))
        XCTAssertTrue(plan.entries[0].snapshotIsDisplayable)
        XCTAssertEqual(plan.entries[0].displayedTimeMinutes, 4)
        XCTAssertEqual(BatteryWidgetCountdown(snapshot: snapshot)?.remainingMinutes(at: plan.entries[0].date), 5)
        XCTAssertEqual(plan.entries[1].date, displayExpiryDate)
        XCTAssertFalse(plan.entries[1].snapshotIsDisplayable)
        XCTAssertNil(plan.entries[1].displayedTimeMinutes)
        XCTAssertEqual(
            plan.entries[1].date.timeIntervalSince(plan.entries[0].date),
            BatteryWidgetTimelinePlan.minimumEntryInterval
        )
    }

    func testWidgetTimelineKeepsRetainedStaleSnapshotVisibleAndMissingSnapshotUnavailable() throws {
        let now = Date(timeIntervalSinceReferenceDate: 12_000)
        let staleSnapshot = makeSnapshot(
            stateOfChargePercent: 70,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: 90,
            timestamp: now.addingTimeInterval(-12 * 60)
        )
        let stalePlan = BatteryWidgetTimelinePlan.make(snapshot: staleSnapshot, now: now)
        let unavailablePlan = BatteryWidgetTimelinePlan.make(snapshot: nil, now: now)

        XCTAssertFalse(BatterySnapshotFreshnessPolicy.isLive(updatedAt: staleSnapshot.timestamp, now: now))
        XCTAssertTrue(try XCTUnwrap(stalePlan.entries.first).snapshotIsDisplayable)
        XCTAssertEqual(stalePlan.entries.first?.displayedTimeMinutes, 78)
        XCTAssertEqual(BatteryWidgetCountdown(snapshot: staleSnapshot)?.deadline, staleSnapshot.timestamp.addingTimeInterval(90 * 60))
        XCTAssertNotNil(stalePlan.reloadAfter)

        XCTAssertEqual(unavailablePlan.entries.count, 1)
        XCTAssertFalse(unavailablePlan.entries[0].snapshotIsDisplayable)
        XCTAssertNil(unavailablePlan.entries[0].displayedTimeMinutes)
        XCTAssertNil(unavailablePlan.reloadAfter)
    }

    func testWidgetTimelineKeepsUnavailableTimeDistinctFromExpiredSnapshot() throws {
        let now = Date(timeIntervalSinceReferenceDate: 12_000)
        let snapshot = makeSnapshot(
            stateOfChargePercent: 80,
            powerState: .connectedNotCharging,
            timestamp: now
        )
        let plan = BatteryWidgetTimelinePlan.make(snapshot: snapshot, now: now)

        XCTAssertTrue(plan.entries[0].snapshotIsDisplayable)
        XCTAssertNil(plan.entries[0].displayedTimeMinutes)
        XCTAssertNil(BatteryWidgetCountdown(snapshot: snapshot))
        XCTAssertFalse(try XCTUnwrap(plan.entries.last).snapshotIsDisplayable)
    }

    func testFormatsCompactWattHours() {
        XCTAssertEqual(BatteryFormatting.compactWattHours(40.2), "40.2 Wh")
        XCTAssertEqual(BatteryFormatting.compactWattHours(0), "0.0 Wh")
        XCTAssertEqual(BatteryFormatting.compactWattHours(nil), "Unavailable")
        XCTAssertEqual(BatteryFormatting.compactWattHours(.nan), "Unavailable")
    }

    func testFormatsFahrenheitTemperature() {
        XCTAssertEqual(BatteryFormatting.temperature(34.2, unitPreference: .fahrenheit), "93.6 °F")
    }

    func testFormatsAge() {
        let formattedAge = BatteryFormatting.age(DateComponents(year: 2, month: 3))

        XCTAssertTrue(formattedAge.contains("2"))
        XCTAssertTrue(formattedAge.contains("3"))
    }

    func testFormatsAgeUsingCompletedMonthsWithoutRoundingDaysUp() {
        let formattedAge = BatteryFormatting.age(DateComponents(year: 2, month: 3, day: 30))

        XCTAssertTrue(formattedAge.contains("2"))
        XCTAssertTrue(formattedAge.contains("3"))
        XCTAssertFalse(formattedAge.contains("4"))
    }

    func testFormatsManufactureDateUsingStableCalendarMonth() throws {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let manufactureDate = try XCTUnwrap(utcCalendar.date(from: DateComponents(year: 2023, month: 1, day: 1)))

        let formattedDate = BatteryFormatting.date(manufactureDate)

        XCTAssertTrue(formattedDate.contains("2023"))
        XCTAssertFalse(formattedDate.contains("2022"))
    }

    func testFormatsZeroAge() {
        XCTAssertEqual(BatteryFormatting.age(DateComponents(year: 0, month: 0)), "0 mo")
        XCTAssertEqual(BatteryFormatting.age(DateComponents()), "0 mo")
    }

    func testFormatsMalformedAgeAsUnavailable() {
        XCTAssertEqual(BatteryFormatting.age(DateComponents(year: -1, month: 2)), "Unavailable")
        XCTAssertEqual(BatteryFormatting.age(DateComponents(year: 1, month: -2)), "Unavailable")
        XCTAssertEqual(BatteryFormatting.age(DateComponents(year: 1, month: 12)), "Unavailable")
        XCTAssertEqual(BatteryFormatting.age(DateComponents(year: 1, month: 2, day: -1)), "Unavailable")
    }

    func testSummaryAgeRecomputesFromManufactureDateInsteadOfTrustingStoredAge() throws {
        let calendar = Calendar(identifier: .gregorian)
        let manufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let timestamp = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 3, day: 1)))
        let snapshot = makeSnapshot(
            stateOfChargePercent: 60,
            powerState: .onBattery,
            manufactureDate: manufactureDate,
            timestamp: timestamp
        )

        XCTAssertEqual(snapshot.validatedBatteryAgeComponents?.year, 0)
        XCTAssertEqual(snapshot.validatedBatteryAgeComponents?.month, 2)
        let formattedAge = BatteryFormatting.age(snapshot.validatedBatteryAgeComponents)
        XCTAssertTrue(formattedAge.contains("2"))
        XCTAssertFalse(formattedAge.contains("9"))
        XCTAssertFalse(snapshot.debugSummary.contains("Age since made"))
    }

    func testSummaryHidesFutureManufactureDateAndOrphanAge() throws {
        let calendar = Calendar(identifier: .gregorian)
        let manufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let timestamp = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 12, day: 31)))
        let snapshot = makeSnapshot(
            stateOfChargePercent: 60,
            powerState: .onBattery,
            manufactureDate: manufactureDate,
            timestamp: timestamp
        )

        XCTAssertNil(snapshot.validatedManufactureDate)
        XCTAssertNil(snapshot.validatedBatteryAgeComponents)
        XCTAssertTrue(snapshot.debugSummary.contains("Manufacture date: Unavailable"))
        XCTAssertFalse(snapshot.debugSummary.contains("Age since made"))
    }

    func testSummaryDetailFormattingHidesUnavailableValues() {
        XCTAssertEqual(BatterySummaryDetailFormatting.compactPercent(nil), "—")
        XCTAssertEqual(BatterySummaryDetailFormatting.compactPercent(.nan), "—")
        XCTAssertEqual(BatterySummaryDetailFormatting.compactPercent(-4), "—")
        XCTAssertEqual(BatterySummaryDetailFormatting.compactPercent(150), "—")
        XCTAssertNil(BatterySummaryDetailFormatting.power(-4.2))
        XCTAssertNil(BatterySummaryDetailFormatting.power(.greatestFiniteMagnitude))
    }

    func testSummaryDetailFormattingShowsValidAndPartialValues() {
        XCTAssertEqual(BatterySummaryDetailFormatting.compactPercent(81.38), "81%")
        XCTAssertEqual(BatterySummaryDetailFormatting.compactPercent(100), "100%")
        XCTAssertEqual(BatterySummaryDetailFormatting.power(13.9), "13.9 W")
    }

    func testSummaryChargingSpeedUsesLiveInputPowerWhileCharging() throws {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: 25.4,
            inputPowerWatts: 69.42,
            inputPowerEvidence: .counterBacked,
            adapterMaxWatts: 70
        )
        XCTAssertEqual(BatterySummaryDetailFormatting.power(snapshot.activePowerWatts), "69.4 W")
    }

    func testSummaryChargingSpeedFallsBackToChargeRateWhenInputPowerIsUnavailable() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: 25.4,
            inputPowerWatts: 100,
            adapterMaxWatts: 100
        )

        XCTAssertEqual(BatterySummaryDetailFormatting.power(snapshot.activePowerWatts), "25.4 W")
    }

    func testPowerDisplayRoleReflectsChargingPowerSource() {
        XCTAssertEqual(
            BatteryPowerDisplayRole.role(for: makeSnapshot(stateOfChargePercent: 55, powerState: .charging)).title,
            "Charge Rate"
        )
        XCTAssertEqual(
            BatteryPowerDisplayRole.role(for: makeSnapshot(
                stateOfChargePercent: 55,
                powerState: .charging,
                chargeRateWatts: 25.4,
                inputPowerWatts: 39.8
            )).title,
            "Input Power"
        )
        XCTAssertEqual(
            BatteryPowerDisplayRole.role(for: makeSnapshot(
                stateOfChargePercent: 55,
                powerState: .charging,
                chargeRateWatts: 0.04,
                inputPowerWatts: 39.8
            )).title,
            "Input Power"
        )
        XCTAssertEqual(
            BatteryPowerDisplayRole.role(for: makeSnapshot(
                stateOfChargePercent: 55,
                powerState: .connectedDischarging,
                inputPowerWatts: 39.8
            )).title,
            "Input Power"
        )
        XCTAssertEqual(
            BatteryPowerDisplayRole.role(for: makeSnapshot(
                stateOfChargePercent: 85,
                powerState: .connectedNotCharging,
                inputPowerWatts: 39.8
            )).title,
            "Input Power"
        )
        XCTAssertEqual(
            BatteryPowerDisplayRole.role(for: makeSnapshot(
                stateOfChargePercent: 100,
                powerState: .fullOnAC,
                inputPowerWatts: 27.4
            )).title,
            "Input Power"
        )
        XCTAssertEqual(
            BatteryPowerDisplayRole.role(for: makeSnapshot(stateOfChargePercent: 55, powerState: .onBattery)).title,
            "Power"
        )
        XCTAssertEqual(
            BatteryPowerDisplayRole.role(for: makeSnapshot(stateOfChargePercent: 55, powerState: .connectedDischarging)).title,
            "Battery Drain"
        )
    }

    func testCapacityProgressPresentationUsesSharedMetricNormalization() throws {
        let source = try Self.loadSource(
            relativePath: "BatteryStats/Features/Battery/Presentation/BatterySummaryGridView.swift"
        )

        XCTAssertSource(
            source,
            contains: ["let fillFraction = BatteryMetricFormatting.clampedProgress(progress)"],
            excludes: ["BatteryCapacityProgressPresentation"]
        )
    }

    func testSummaryTimeFormattingFallsBackFromInvalidRateBasedTimeToSystemTime() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: -5,
            systemTimeRemainingMinutes: 145
        )

        XCTAssertEqual(snapshot.displayedTimeMinutes, 145)
        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "2h 25m / 1,200 mA")
    }

    func testSummaryTimeFormattingPrefersValidSystemEstimateOverCustomEstimate() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: 90,
            systemTimeRemainingMinutes: 145
        )

        XCTAssertEqual(snapshot.displayedTimeMinutes, 145)
        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "2h 25m / 1,200 mA")
    }

    func testTimeTitlesReflectPowerState() {
        let onBattery = makeSnapshot(stateOfChargePercent: 55, powerState: .onBattery)
        let charging = makeSnapshot(stateOfChargePercent: 55, powerState: .charging)
        let connectedDischarging = makeSnapshot(stateOfChargePercent: 55, powerState: .connectedDischarging)
        let connectedNotCharging = makeSnapshot(stateOfChargePercent: 100, powerState: .connectedNotCharging)
        let fullOnAC = makeSnapshot(stateOfChargePercent: 100, powerState: .fullOnAC)
        let unknown = makeSnapshot(stateOfChargePercent: 55, powerState: .unknown)

        XCTAssertEqual(onBattery.powerState.timeTitle(charging: "Time to Full", discharging: "Time Left"), "Time Left")
        XCTAssertEqual(charging.powerState.timeTitle(charging: "Time to Full", discharging: "Time Left"), "Time to Full")
        XCTAssertEqual(connectedDischarging.powerState.timeTitle(charging: "Time to Full", discharging: "Time Left"), "Time Left")
        XCTAssertEqual(connectedNotCharging.powerState.timeTitle(charging: "Time to Full", discharging: "Time Left"), "Time")
        XCTAssertEqual(fullOnAC.powerState.timeTitle(charging: "Time to Full", discharging: "Time Left"), "Time")
        XCTAssertEqual(unknown.powerState.timeTitle(charging: "Time to Full", discharging: "Time Left"), "Time")

        XCTAssertEqual(onBattery.powerState.timeTitle(charging: "To Full", discharging: "Time Left"), "Time Left")
        XCTAssertEqual(charging.powerState.timeTitle(charging: "To Full", discharging: "Time Left"), "To Full")
        XCTAssertEqual(connectedDischarging.powerState.timeTitle(charging: "To Full", discharging: "Time Left"), "Time Left")
        XCTAssertEqual(connectedNotCharging.powerState.timeTitle(charging: "To Full", discharging: "Time Left"), "Time")
        XCTAssertEqual(fullOnAC.powerState.timeTitle(charging: "To Full", discharging: "Time Left"), "Time")
        XCTAssertEqual(unknown.powerState.timeTitle(charging: "To Full", discharging: "Time Left"), "Time")
    }

    func testNonTimingPowerStatesDoNotExposeSystemTimeRemaining() {
        let connectedNotCharging = makeSnapshot(
            stateOfChargePercent: 85,
            powerState: .connectedNotCharging,
            systemTimeRemainingMinutes: 45
        )
        let fullOnAC = makeSnapshot(
            stateOfChargePercent: 100,
            powerState: .fullOnAC,
            systemTimeRemainingMinutes: 0
        )
        let unknown = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .unknown,
            systemTimeRemainingMinutes: 30
        )

        for snapshot in [connectedNotCharging, fullOnAC, unknown] {
            XCTAssertNil(snapshot.displayedTimeMinutes)
            XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "—")
            XCTAssertEqual(BatteryMetricFormatting.timeText(minutes: snapshot.displayedTimeMinutes), "—")
            XCTAssertNil(BatteryMetricFormatting.timeProgress(minutes: snapshot.displayedTimeMinutes))
        }
    }

    func testChargingTimeSummaryPrefersVerifiedInputPowerOverChargeRate() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            currentMilliampsSigned: 1_200,
            chargeRateWatts: 25.4,
            inputPowerWatts: 39.8
        )

        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "50m / 39.8 W")
    }

    func testChargingTimeSummaryFallsBackToInputPowerWhenChargeRateIsUnavailable() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            currentMilliampsSigned: 1_200,
            chargeRateWatts: 0.04,
            inputPowerWatts: 39.8
        )

        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "50m / 39.8 W")
    }

    func testChargingTimeSummaryFallsBackToChargeWattsWhenInputPowerIsUnavailable() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            currentMilliampsSigned: 1_200
        )

        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "50m / 18.0 W")
    }

    func testChargingTimeSummaryFallsBackToCurrentWhenPowerIsUnavailable() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            currentMilliampsSigned: 1_200,
            chargeRateWatts: 0.04
        )

        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "50m / 1,200 mA")
    }

    func testTimeSummaryLabelsRateAsEstimatingWhenTimeIsUnavailable() {
        let onBattery = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: Int.max,
            systemTimeRemainingMinutes: Int.max,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200
        )
        let charging = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            rateBasedTimeRemainingMinutes: Int.max,
            systemTimeRemainingMinutes: Int.max,
            timeToFullMinutes: Int.max,
            currentMilliampsSigned: 1_200,
            inputPowerWatts: 39.8
        )

        XCTAssertNil(onBattery.displayedTimeMinutes)
        XCTAssertNil(charging.displayedTimeMinutes)
        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: onBattery), "Estimating / 1,200 mA")
        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: charging), "Estimating / 39.8 W")
    }

    func testSnapshotUsesChargeForStatusAndMenuBarIcon() {
        let emptySnapshot = makeSnapshot(stateOfChargePercent: 0, powerState: .onBattery)
        XCTAssertEqual(emptySnapshot.batterySymbolName, "battery.0")

        let veryLowSnapshot = makeSnapshot(stateOfChargePercent: 8, powerState: .onBattery)
        XCTAssertEqual(veryLowSnapshot.batterySymbolName, "battery.25")

        let lowPowerSnapshot = makeSnapshot(stateOfChargePercent: 15, powerState: .onBattery)
        XCTAssertEqual(lowPowerSnapshot.statusDisplayTitle, "On Battery Low Power")
        XCTAssertEqual(lowPowerSnapshot.batterySymbolName, "battery.25")

        let halfChargedSnapshot = makeSnapshot(stateOfChargePercent: 55, powerState: .charging)
        XCTAssertEqual(halfChargedSnapshot.statusDisplayTitle, "Charging")
        XCTAssertEqual(halfChargedSnapshot.batterySymbolName, "battery.50")
    }

    func testSnapshotStatusPreservesConnectedAndFullStates() {
        let connectedSnapshot = makeSnapshot(stateOfChargePercent: 85, powerState: .connectedNotCharging)
        let fullSnapshot = makeSnapshot(stateOfChargePercent: 100, powerState: .fullOnAC)

        XCTAssertEqual(connectedSnapshot.statusDisplayTitle, "Connected, Not Charging")
        XCTAssertEqual(fullSnapshot.statusDisplayTitle, "Fully Charged")
    }

    func testSnapshotUsesUnknownIconWhenChargePercentIsUnavailable() {
        let snapshot = makeSnapshot(stateOfChargePercent: nil, powerState: .charging)

        XCTAssertEqual(snapshot.batterySymbolName, "questionmark")
    }

    func testSnapshotTreatsNonFinitePercentagesAsUnavailableForPresentation() {
        let snapshot = makeSnapshot(stateOfChargePercent: .nan, healthPercent: .infinity, powerState: .onBattery)

        XCTAssertNil(snapshot.presentationStateOfChargePercent)
        XCTAssertNil(snapshot.presentationHealthPercent)
        XCTAssertEqual(snapshot.batterySymbolName, "questionmark")
        XCTAssertEqual(snapshot.chargeTone, .green)
        XCTAssertEqual(snapshot.healthTone, .green)
        XCTAssertEqual(BatteryPresentationStyle.chargeTintStyle(for: snapshot), .secondary)
        XCTAssertEqual(BatteryPresentationStyle.healthTintStyle(for: snapshot), .secondary)

        let descriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)
        XCTAssertEqual(descriptor.symbolName, "questionmark")
        XCTAssertEqual(descriptor.ringTintStyle, .secondary)
        XCTAssertEqual(descriptor.contentTintStyle, .secondary)
    }

    func testSnapshotTreatsOutOfRangePercentagesAsUnavailableForPresentation() {
        let snapshot = makeSnapshot(stateOfChargePercent: -4, healthPercent: -2, powerState: .onBattery)

        XCTAssertNil(snapshot.presentationStateOfChargePercent)
        XCTAssertNil(snapshot.presentationHealthPercent)
        XCTAssertEqual(snapshot.statusDisplayTitle, "On Battery")
        XCTAssertEqual(snapshot.batterySymbolName, "questionmark")
        XCTAssertEqual(snapshot.chargeTone, .green)
        XCTAssertEqual(snapshot.healthTone, .green)
        XCTAssertEqual(BatteryPresentationStyle.chargeTintStyle(for: snapshot), .secondary)
        XCTAssertEqual(BatteryPresentationStyle.healthTintStyle(for: snapshot), .secondary)

        let descriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)
        XCTAssertEqual(descriptor.symbolName, "questionmark")
        XCTAssertEqual(descriptor.ringTintStyle, .secondary)
        XCTAssertEqual(descriptor.contentTintStyle, .secondary)
    }

    func testSnapshotClampsSmallPercentOveragesForPresentation() {
        let snapshot = makeSnapshot(stateOfChargePercent: 105, healthPercent: 115, powerState: .charging)

        XCTAssertEqual(snapshot.presentationStateOfChargePercent, 100)
        XCTAssertEqual(snapshot.presentationHealthPercent, 100)
        XCTAssertEqual(snapshot.batterySymbolName, "battery.100")
        XCTAssertEqual(BatteryFormatting.percent(snapshot.presentationStateOfChargePercent), "100%")
        XCTAssertEqual(BatteryFormatting.percent(snapshot.presentationHealthPercent), "100%")
    }

    func testPresentationBatterySymbolFallsBackToKnownPowerStateWhenPercentIsUnavailable() {
        XCTAssertEqual(
            BatteryPresentationStyle.batterySymbolName(
                for: makeSnapshot(stateOfChargePercent: nil, powerState: .charging)
            ),
            "battery.100.bolt"
        )
        XCTAssertEqual(
            BatteryPresentationStyle.batterySymbolName(
                for: makeSnapshot(stateOfChargePercent: nil, powerState: .connectedNotCharging)
            ),
            "powerplug"
        )
        XCTAssertEqual(
            BatteryPresentationStyle.batterySymbolName(
                for: makeSnapshot(stateOfChargePercent: nil, powerState: .fullOnAC)
            ),
            "battery.100"
        )
        XCTAssertEqual(
            BatteryPresentationStyle.batterySymbolName(
                for: makeSnapshot(stateOfChargePercent: nil, powerState: .onBattery)
            ),
            "questionmark"
        )
    }

    func testPresentationBatterySymbolUsesChargeBucketWhenPercentIsAvailable() {
        XCTAssertEqual(
            BatteryPresentationStyle.batterySymbolName(
                for: makeSnapshot(stateOfChargePercent: 42, powerState: .charging)
            ),
            "battery.50"
        )
        XCTAssertEqual(
            BatteryPresentationStyle.batterySymbolName(
                for: makeSnapshot(stateOfChargePercent: 42, powerState: .connectedNotCharging)
            ),
            "battery.50"
        )
        XCTAssertEqual(
            BatteryPresentationStyle.batterySymbolName(
                for: makeSnapshot(stateOfChargePercent: 42, powerState: .connectedDischarging)
            ),
            "battery.50"
        )
        XCTAssertEqual(
            BatteryPresentationStyle.batterySymbolName(
                for: makeSnapshot(stateOfChargePercent: 100, powerState: .fullOnAC)
            ),
            "battery.100"
        )
    }

    func testSnapshotTreatsImpossibleTemperatureAsUnavailableForPresentation() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            temperatureCelsius: 180
        )

        XCTAssertNil(snapshot.presentationTemperatureCelsius)
        XCTAssertTrue(snapshot.debugSummary.contains("Temperature: Unavailable"))
    }

    func testSnapshotDebugSummaryHidesAbsurdCycleCount() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            cycleCount: Int.max
        )

        XCTAssertTrue(snapshot.debugSummary.contains("Cycle count: Unavailable"))
    }

    func testSnapshotDebugSummaryIncludesDisplayedBatteryMetrics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let manufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2023, month: 1, day: 1)))
        let timestamp = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 4, day: 1)))
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            timeToFullMinutes: 89,
            chargeRateWatts: 25.4,
            inputPowerWatts: 69.42,
            inputPowerEvidence: .counterBacked,
            manufactureDate: manufactureDate,
            adapterMaxWatts: 70,
            timestamp: timestamp
        )

        let summary = snapshot.debugSummary
        XCTAssertTrue(summary.contains("Health: 83.3%"))
        XCTAssertTrue(summary.contains("Estimated Energy: 36.0 Wh"))
        XCTAssertTrue(summary.contains("Time to full: \(BatteryFormatting.duration(minutes: 89))"))
        XCTAssertTrue(summary.contains("Active power: 69.4 W"))
        XCTAssertTrue(summary.contains("Input power: 69.4 W"))
        XCTAssertTrue(summary.contains("Charge rate: 25.4 W"))
        XCTAssertTrue(summary.contains("Discharge rate: Unavailable"))
        XCTAssertTrue(summary.contains("Adapter max power: 70 W"))
        XCTAssertTrue(summary.contains("Manufacture date: \(BatteryFormatting.date(manufactureDate))"))
        XCTAssertFalse(summary.contains("Age since made"))
    }

    func testSnapshotTreatsInvalidActivePowerAsUnavailable() {
        let chargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: -18
        )
        XCTAssertNil(chargingSnapshot.activePowerWatts)

        let dischargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            dischargeRateWatts: .nan
        )
        XCTAssertNil(dischargingSnapshot.activePowerWatts)
        XCTAssertEqual(dischargingSnapshot.energyUseComparisonValue ?? 0, 1.2, accuracy: 0.001)
    }

    func testSnapshotLabelsCurrentOnlyWattHoursAsEstimatedEnergy() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery
        )

        XCTAssertTrue(snapshot.debugSummary.contains("Estimated Energy: 36.0 Wh"))
        XCTAssertFalse(snapshot.debugSummary.contains("\nEnergy: 36.0 Wh"))
    }

    func testSnapshotTreatsRoundedZeroActivePowerAsUnavailable() {
        let chargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            currentMilliampsSigned: 0,
            chargeRateWatts: 0.09,
            inputPowerWatts: 0.04
        )
        XCTAssertNil(chargingSnapshot.activePowerWatts)
        XCTAssertEqual(BatterySummaryDetailFormatting.power(chargingSnapshot.activePowerWatts), nil)
        XCTAssertEqual(formattedActivePower(for: chargingSnapshot), "—")
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: chargingSnapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).value,
            "—"
        )

        let dischargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            currentMilliampsSigned: 0,
            dischargeRateMilliamps: 0,
            dischargeRateWatts: 0.09
        )
        XCTAssertNil(dischargingSnapshot.activePowerWatts)
        XCTAssertNil(dischargingSnapshot.energyUseComparisonValue)
    }

    func testSnapshotPrefersVerifiedInputPowerForChargingActivePower() throws {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: 25.4,
            inputPowerWatts: 39.8
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.chargeRateWatts), 25.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.inputPowerWatts), 39.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.activePowerWatts), 39.8, accuracy: 0.001)
        XCTAssertEqual(snapshot.energyUseComparisonValue ?? 0, 39.8, accuracy: 0.001)
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: snapshot).title, "Input Power")
        XCTAssertEqual(formattedActivePower(for: snapshot), "39.8 W")
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).accessibilityLabel,
            "Battery input power 39.8 W"
        )
    }

    func testSnapshotFallsBackToInputPowerWhenChargingRateIsUnavailable() throws {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: 0.04,
            inputPowerWatts: 39.8
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.inputPowerWatts), 39.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.activePowerWatts), 39.8, accuracy: 0.001)
        XCTAssertEqual(snapshot.energyUseComparisonValue ?? 0, 39.8, accuracy: 0.001)
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: snapshot).title, "Input Power")
        XCTAssertEqual(formattedActivePower(for: snapshot), "39.8 W")
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).accessibilityLabel,
            "Battery input power 39.8 W"
        )
    }

    func testSnapshotRejectsInputPowerAboveAdapterCapability() {
        let chargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: 25.4,
            inputPowerWatts: 100
        )

        XCTAssertEqual(chargingSnapshot.activePowerWatts, 25.4)
        XCTAssertEqual(chargingSnapshot.energyUseComparisonValue ?? 0, 25.4, accuracy: 0.001)
        XCTAssertEqual(formattedActivePower(for: chargingSnapshot), "25.4 W")
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: chargingSnapshot).title, "Charge Rate")
        XCTAssertTrue(chargingSnapshot.debugSummary.contains("Input power: Unavailable"))
        XCTAssertFalse(chargingSnapshot.debugSummary.contains("Input power: 100.0 W"))
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: chargingSnapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).accessibilityLabel,
            "Battery charge rate 25.4 W"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: chargingSnapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).value,
            "25.4W"
        )

        let idleSnapshot = makeSnapshot(
            stateOfChargePercent: 85,
            powerState: .connectedNotCharging,
            inputPowerWatts: 100
        )

        XCTAssertNil(idleSnapshot.activePowerWatts)
        XCTAssertEqual(formattedActivePower(for: idleSnapshot), "—")
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: idleSnapshot).title, "Power")
    }

    func testSnapshotRejectsUnverifiedHundredWattInputPowerWithoutAdapterCapability() {
        let chargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: 0.04,
            inputPowerWatts: 100,
            adapterMaxWatts: nil
        )

        XCTAssertNil(chargingSnapshot.activePowerWatts)
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: chargingSnapshot).title, "Charge Rate")
        XCTAssertEqual(formattedActivePower(for: chargingSnapshot), "—")
        XCTAssertTrue(chargingSnapshot.debugSummary.contains("Input power: Unavailable"))
        XCTAssertFalse(chargingSnapshot.debugSummary.contains("Input power: 100.0 W"))
    }

    func testSnapshotRejectsInputPowerThatMirrorsAdapterCapability() {
        let chargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: 25.4,
            inputPowerWatts: 100,
            adapterMaxWatts: 100
        )

        XCTAssertEqual(chargingSnapshot.activePowerWatts, 25.4)
        XCTAssertEqual(formattedActivePower(for: chargingSnapshot), "25.4 W")
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: chargingSnapshot).title, "Charge Rate")
        XCTAssertTrue(chargingSnapshot.debugSummary.contains("Input power: Unavailable"))
        XCTAssertFalse(chargingSnapshot.debugSummary.contains("Input power: 100.0 W"))
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: chargingSnapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).value,
            "25.4W"
        )
    }

    func testSnapshotAcceptsCounterBackedInputPowerNearAdapterCapability() throws {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            chargeRateWatts: 25.4,
            inputPowerWatts: 69.42,
            inputPowerEvidence: .counterBacked,
            adapterMaxWatts: 70
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.visibleInputPowerWatts), 69.42, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.activePowerWatts), 69.42, accuracy: 0.001)
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: snapshot).title, "Input Power")
        XCTAssertEqual(formattedActivePower(for: snapshot), "69.4 W")
        XCTAssertTrue(snapshot.debugSummary.contains("Input power: 69.4 W"))
    }

    func testConnectedDischargingShowsLiveInputPowerWhenAvailable() throws {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .connectedDischarging,
            inputPowerWatts: 39.8,
            dischargeRateWatts: 14
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.activePowerWatts), 39.8, accuracy: 0.001)
        XCTAssertEqual(formattedActivePower(for: snapshot), "39.8 W")
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: snapshot).title, "Input Power")
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).accessibilityLabel,
            "Battery input power 39.8 W, battery discharging"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).value,
            "In 39.8W"
        )
    }

    func testConnectedDischargingFallsBackToDischargePowerWhenInputPowerIsUnavailable() throws {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .connectedDischarging,
            dischargeRateWatts: 14
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.activePowerWatts), 14, accuracy: 0.001)
        XCTAssertEqual(formattedActivePower(for: snapshot), "14.0 W")
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: snapshot).title, "Battery Drain")
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).accessibilityLabel,
            "Battery drain 14.0 W"
        )
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: snapshot,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).value,
            "14.0W"
        )
    }

    func testSnapshotHidesStaleActivePowerForIdleStates() {
        let connectedNotCharging = makeSnapshot(
            stateOfChargePercent: 85,
            powerState: .connectedNotCharging,
            currentMilliampsSigned: 1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: 18,
            dischargeRateWatts: 14
        )
        let fullOnAC = makeSnapshot(
            stateOfChargePercent: 100,
            powerState: .fullOnAC,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: 18,
            dischargeRateWatts: 14
        )
        let unknown = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .unknown,
            currentMilliampsSigned: 1_200,
            dischargeRateMilliamps: 1_200,
            chargeRateWatts: 18,
            dischargeRateWatts: 14
        )

        for snapshot in [connectedNotCharging, fullOnAC, unknown] {
            XCTAssertNil(snapshot.activePowerWatts)
            XCTAssertNil(snapshot.activeCurrentMilliamps)
            XCTAssertNil(snapshot.energyUseComparisonValue)
            XCTAssertTrue(snapshot.debugSummary.contains("Charge rate: Unavailable"))
            XCTAssertTrue(snapshot.debugSummary.contains("Discharge rate: Unavailable"))
            XCTAssertFalse(snapshot.debugSummary.contains("Charge rate: 18.0 W"))
            XCTAssertFalse(snapshot.debugSummary.contains("Discharge rate: 14.0 W"))
            XCTAssertNil(BatterySummaryDetailFormatting.power(snapshot.activePowerWatts))
            XCTAssertEqual(formattedActivePower(for: snapshot), "—")
            XCTAssertEqual(
                MenuBarBatteryLabelFormatting.presentation(
                    snapshot: snapshot,
                    displayMode: .iconAndPower,
                    temperatureUnitPreference: .celsius
                ).value,
                "—"
            )
        }
    }

    func testSnapshotShowsLiveInputPowerForExternalIdleStates() throws {
        let connectedNotCharging = makeSnapshot(
            stateOfChargePercent: 85,
            powerState: .connectedNotCharging,
            inputPowerWatts: 39.8
        )
        let fullOnAC = makeSnapshot(
            stateOfChargePercent: 100,
            powerState: .fullOnAC,
            inputPowerWatts: 27.4
        )

        XCTAssertEqual(try XCTUnwrap(connectedNotCharging.activePowerWatts), 39.8, accuracy: 0.001)
        XCTAssertEqual(formattedActivePower(for: connectedNotCharging), "39.8 W")
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: connectedNotCharging).title, "Input Power")
        XCTAssertEqual(
            MenuBarBatteryLabelFormatting.presentation(
                snapshot: connectedNotCharging,
                displayMode: .iconAndPower,
                temperatureUnitPreference: .celsius
            ).value,
            "In 39.8W"
        )

        XCTAssertEqual(try XCTUnwrap(fullOnAC.activePowerWatts), 27.4, accuracy: 0.001)
        XCTAssertEqual(formattedActivePower(for: fullOnAC), "27.4 W")
        XCTAssertEqual(BatteryPowerDisplayRole.role(for: fullOnAC).title, "Input Power")
    }

    func testSummaryTimeFormattingUsesSignedCurrentWhenDischargeRateIsInvalid() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            dischargeRateMilliamps: -500
        )

        XCTAssertEqual(snapshot.activeCurrentMilliamps, 1_200)
        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "2h 25m / 1,200 mA")
    }

    func testSummaryTimeFormattingHidesInvalidCurrentRate() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            currentMilliampsSigned: Int.max,
            dischargeRateMilliamps: -500
        )

        XCTAssertNil(snapshot.activeCurrentMilliamps)
        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "2h 25m")
    }

    func testSummaryTimeFormattingHidesInvalidTimeAndCurrentTogether() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: Int.max,
            systemTimeRemainingMinutes: Int.max,
            currentMilliampsSigned: Int.max,
            dischargeRateMilliamps: Int.max
        )

        XCTAssertNil(snapshot.displayedTimeMinutes)
        XCTAssertNil(snapshot.activeCurrentMilliamps)
        XCTAssertEqual(BatterySummaryDetailFormatting.timeSummary(for: snapshot), "—")
    }

    func testSnapshotUsesRequestedHealthAndChargeThresholdBands() {
        let redSnapshot = makeSnapshot(stateOfChargePercent: 8, healthPercent: 79.5, powerState: .onBattery)
        XCTAssertEqual(redSnapshot.healthTone, .red)
        XCTAssertEqual(redSnapshot.chargeTone, .red)
        XCTAssertEqual(BatteryPresentationStyle.healthTintStyle(for: redSnapshot), .red)
        XCTAssertEqual(BatteryPresentationStyle.chargeTintStyle(for: redSnapshot), .red)

        let yellowSnapshot = makeSnapshot(stateOfChargePercent: 15, healthPercent: 82, powerState: .onBattery)
        XCTAssertEqual(yellowSnapshot.healthTone, .yellow)
        XCTAssertEqual(yellowSnapshot.chargeTone, .yellow)
        XCTAssertEqual(BatteryPresentationStyle.healthTintStyle(for: yellowSnapshot), .yellow)
        XCTAssertEqual(BatteryPresentationStyle.chargeTintStyle(for: yellowSnapshot), .yellow)

        let greenYellowSnapshot = makeSnapshot(stateOfChargePercent: 35, healthPercent: 88, powerState: .onBattery)
        XCTAssertEqual(greenYellowSnapshot.healthTone, .greenYellow)
        XCTAssertEqual(greenYellowSnapshot.chargeTone, .greenYellow)
        XCTAssertEqual(BatteryPresentationStyle.healthTintStyle(for: greenYellowSnapshot), .yellow)
        XCTAssertEqual(BatteryPresentationStyle.chargeTintStyle(for: greenYellowSnapshot), .yellow)

        let midGreenSnapshot = makeSnapshot(stateOfChargePercent: 55, healthPercent: 93, powerState: .onBattery)
        XCTAssertEqual(midGreenSnapshot.healthTone, .midGreen)
        XCTAssertEqual(midGreenSnapshot.chargeTone, .midGreen)
        XCTAssertEqual(BatteryPresentationStyle.healthTintStyle(for: midGreenSnapshot), .green)
        XCTAssertEqual(BatteryPresentationStyle.chargeTintStyle(for: midGreenSnapshot), .green)

        let greenSnapshot = makeSnapshot(stateOfChargePercent: 76, healthPercent: 97, powerState: .onBattery)
        XCTAssertEqual(greenSnapshot.healthTone, .green)
        XCTAssertEqual(greenSnapshot.chargeTone, .green)
        XCTAssertEqual(BatteryPresentationStyle.healthTintStyle(for: greenSnapshot), .green)
        XCTAssertEqual(BatteryPresentationStyle.chargeTintStyle(for: greenSnapshot), .green)
    }

    func testSnapshotIgnoresNegativeDisplayedTimeValues() {
        let onBatterySnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: -5,
            systemTimeRemainingMinutes: -3
        )
        XCTAssertNil(onBatterySnapshot.displayedTimeMinutes)

        let chargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            timeToFullMinutes: -8
        )
        XCTAssertNil(chargingSnapshot.displayedTimeMinutes)
    }

    func testSnapshotIgnoresAbsurdDisplayedTimeValues() {
        let onBatterySnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: Int.max,
            systemTimeRemainingMinutes: Int.max
        )
        XCTAssertNil(onBatterySnapshot.displayedTimeMinutes)

        let chargingSnapshot = makeSnapshot(
            stateOfChargePercent: 55,
            powerState: .charging,
            timeToFullMinutes: Int.max
        )
        XCTAssertNil(chargingSnapshot.displayedTimeMinutes)
    }

    func testTimeTintIsSecondaryWhenTimeAndChargeAreUnavailable() {
        let snapshot = makeSnapshot(
            stateOfChargePercent: .nan,
            powerState: .onBattery,
            rateBasedTimeRemainingMinutes: -5,
            systemTimeRemainingMinutes: -3
        )

        XCTAssertNil(snapshot.displayedTimeMinutes)
        XCTAssertNil(snapshot.presentationStateOfChargePercent)
        XCTAssertEqual(
            BatteryPresentationStyle.timeTintStyle(
                for: snapshot,
                displayedTimeMinutes: snapshot.displayedTimeMinutes
            ),
            .secondary
        )
    }

    func testStatusDescriptorUsesActualBatterySymbolOnBattery() {
        let snapshot = makeSnapshot(stateOfChargePercent: 8, powerState: .onBattery)
        let descriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)

        XCTAssertEqual(descriptor.symbolName, "battery.25")
        XCTAssertEqual(descriptor.ringTintStyle, .yellow)
        XCTAssertEqual(descriptor.contentTintStyle, .yellow)
    }

    func testStatusDescriptorUsesAdaptiveContentTintForNonWarningStates() {
        let missingDescriptor = BatteryPresentationStyle.statusDescriptor(for: nil)
        XCTAssertEqual(missingDescriptor.symbolName, "questionmark")
        XCTAssertEqual(missingDescriptor.ringTintStyle, .secondary)
        XCTAssertEqual(missingDescriptor.contentTintStyle, .secondary)

        let onBatteryDescriptor = BatteryPresentationStyle.statusDescriptor(
            for: makeSnapshot(stateOfChargePercent: 55, powerState: .onBattery)
        )
        XCTAssertEqual(onBatteryDescriptor.symbolName, "battery.50")
        XCTAssertEqual(onBatteryDescriptor.ringTintStyle, .green)
        XCTAssertEqual(onBatteryDescriptor.contentTintStyle, .primary)

        let chargingDescriptor = BatteryPresentationStyle.statusDescriptor(
            for: makeSnapshot(stateOfChargePercent: 55, powerState: .charging)
        )
        XCTAssertEqual(chargingDescriptor.symbolName, "powerplug")
        XCTAssertEqual(chargingDescriptor.ringTintStyle, .green)
        XCTAssertEqual(chargingDescriptor.contentTintStyle, .primary)

        let connectedDischargingDescriptor = BatteryPresentationStyle.statusDescriptor(
            for: makeSnapshot(stateOfChargePercent: 55, powerState: .connectedDischarging)
        )
        XCTAssertEqual(connectedDischargingDescriptor.symbolName, "powerplug")
        XCTAssertEqual(connectedDischargingDescriptor.ringTintStyle, .yellow)
        XCTAssertEqual(connectedDischargingDescriptor.contentTintStyle, .primary)
    }

    func testTwentyPercentLowBatteryPresentationIsConsistent() {
        let snapshot = makeSnapshot(stateOfChargePercent: 20, powerState: .onBattery)
        let descriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)

        XCTAssertEqual(snapshot.statusDisplayTitle, "On Battery Low Power")
        XCTAssertEqual(
            BatteryPresentationStyle.timeTintStyle(
                for: snapshot,
                displayedTimeMinutes: snapshot.displayedTimeMinutes
            ),
            .red
        )
        XCTAssertEqual(descriptor.ringTintStyle, .yellow)
        XCTAssertEqual(descriptor.contentTintStyle, .yellow)
    }

    func testPreviewSnapshotAgeMatchesPreviewManufactureDate() throws {
        let snapshot = BatterySnapshot.previewDischarging
        let manufactureDate = try XCTUnwrap(snapshot.manufactureDate)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let manufactureComponents = utcCalendar.dateComponents(
            [.year, .month, .day],
            from: manufactureDate
        )
        let expectedComponents = try XCTUnwrap(BatteryCalculations.batteryAgeComponents(
            from: snapshot.manufactureDate,
            now: snapshot.timestamp
        ))

        XCTAssertEqual(manufactureComponents.year, 2023)
        XCTAssertEqual(manufactureComponents.month, 9)
        XCTAssertEqual(manufactureComponents.day, 12)
        XCTAssertEqual(snapshot.validatedBatteryAgeComponents?.year, expectedComponents.year)
        XCTAssertEqual(snapshot.validatedBatteryAgeComponents?.month, expectedComponents.month)
    }

    func testSnapshotUpdatingRefreshesBatteryAgeForNewTimestamp() throws {
        let calendar = Calendar(identifier: .gregorian)
        let manufactureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2023, month: 9, day: 12)))
        let originalTimestamp = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 9, day: 12)))
        let nextTimestamp = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 10, day: 12)))
        let snapshot = makeBatterySnapshot(
            timestamp: originalTimestamp,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            healthPercent: 83.3,
            currentMilliampsSigned: -1_200,
            dischargeRateMilliamps: 1_200,
            inputPowerWatts: 27.4,
            inputPowerEvidence: .counterBacked,
            dischargeRateWatts: 14.0,
            rateBasedTimeRemainingMinutes: 150,
            systemTimeRemainingMinutes: 145,
            manufactureDate: manufactureDate,
            adapterMaxWatts: 70,
            notes: ["preserve me"],
        )

        let updatedSnapshot = snapshot.updating(
            rateBasedTimeRemainingMinutes: 140,
            timestamp: nextTimestamp
        )

        XCTAssertEqual(updatedSnapshot.timestamp, nextTimestamp)
        XCTAssertEqual(updatedSnapshot.rateBasedTimeRemainingMinutes, 140)
        XCTAssertEqual(updatedSnapshot.validatedBatteryAgeComponents?.year, 2)
        XCTAssertEqual(updatedSnapshot.validatedBatteryAgeComponents?.month, 1)
        var expectedFields = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        let updatedFields = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(updatedSnapshot)) as? [String: Any]
        )
        expectedFields["timestamp"] = updatedFields["timestamp"]
        expectedFields["rateBasedTimeRemainingMinutes"] = updatedFields["rateBasedTimeRemainingMinutes"]
        XCTAssertEqual(expectedFields as NSDictionary, updatedFields as NSDictionary)
    }

    private func makeSnapshot(
        stateOfChargePercent: Double?,
        healthPercent: Double = 83.3,
        powerState: BatteryPowerState,
        rateBasedTimeRemainingMinutes: Int? = nil,
        systemTimeRemainingMinutes: Int? = nil,
        timeToFullMinutes: Int? = nil,
        temperatureCelsius: Double = 32.0,
        currentMilliampsSigned: Int? = nil,
        dischargeRateMilliamps: Int? = nil,
        chargeRateWatts: Double? = nil,
        inputPowerWatts: Double? = nil,
        inputPowerEvidence: BatteryInputPowerEvidence? = nil,
        dischargeRateWatts: Double? = nil,
        cycleCount: Int? = 120,
        manufactureDate: Date? = nil,
        adapterMaxWatts: Int? = 70,
        timestamp: Date = .now
    ) -> BatterySnapshot {
        makeBatterySnapshot(
            timestamp: timestamp,
            powerState: powerState,
            isCharging: powerState == .charging,
            isExternalPowerConnected: powerState != .onBattery && powerState != .unknown,
            healthPercent: healthPercent,
            stateOfChargePercent: stateOfChargePercent,
            currentMilliampsSigned: currentMilliampsSigned ?? (powerState == .charging ? 1_200 : -1_200),
            dischargeRateMilliamps: dischargeRateMilliamps ?? ((powerState == .onBattery || powerState == .connectedDischarging) ? 1_200 : nil),
            chargeRateWatts: chargeRateWatts ?? (powerState == .charging ? 18.0 : nil),
            inputPowerWatts: inputPowerWatts,
            inputPowerEvidence: inputPowerEvidence,
            dischargeRateWatts: dischargeRateWatts ?? ((powerState == .onBattery || powerState == .connectedDischarging) ? 14.0 : nil),
            rateBasedTimeRemainingMinutes: rateBasedTimeRemainingMinutes ?? ((powerState == .onBattery || powerState == .connectedDischarging) ? 150 : nil),
            systemTimeRemainingMinutes: systemTimeRemainingMinutes
                ?? (rateBasedTimeRemainingMinutes == nil
                    && (powerState == .onBattery || powerState == .connectedDischarging) ? 145 : nil),
            timeToFullMinutes: timeToFullMinutes ?? (powerState == .charging ? 50 : nil),
            cycleCount: cycleCount,
            manufactureDate: manufactureDate,
            temperatureCelsius: temperatureCelsius,
            adapterMaxWatts: adapterMaxWatts,
        )
    }
}
