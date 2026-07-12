import XCTest

final class WidgetSourceTests: XCTestCase {
    func testSmallWidgetUsesRetainedTimelineProjection() throws {
        let source = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryStatusWidgetView.swift")
        let componentSource = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryWidgetComponents.swift")
        let providerSource = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryStatusWidget.swift")

        XCTAssertTrue(source.contains("let snapshot = entry.snapshotIsDisplayable ? entry.snapshot : nil"))
        XCTAssertTrue(source.contains("let displayedTimeMinutes = snapshot == nil ? nil : entry.displayedTimeMinutes"))
        XCTAssertFalse(source.contains("BatterySnapshotFreshnessPolicy.isLive"))
        XCTAssertFalse(source.contains("BatteryMediumWidgetView"))
        XCTAssertTrue(source.contains("BatteryPresentationStyle.healthTintStyle(for: snapshot).color"))
        XCTAssertTrue(source.contains("BatteryPresentationStyle.chargeTintStyle(for: snapshot).color"))
        XCTAssertTrue(source.contains("BatteryPresentationStyle.statusDescriptor(for: snapshot)"))
        XCTAssertTrue(source.contains("BatteryWidgetMetricFormatting.timeText(minutes: displayedTimeMinutes)"))
        XCTAssertFalse(componentSource.contains("BatteryMediumWidgetView"))
        XCTAssertFalse(componentSource.contains("BatteryMediumMetricView"))
        XCTAssertFalse(componentSource.contains("mediumTimeText"))
        XCTAssertTrue(componentSource.contains(".trim(from: 0, to: progress)"))
        XCTAssertTrue(componentSource.contains("case empty"))
        XCTAssertTrue(componentSource.contains(".accessibilityLabel(Text(metric.accessibilityLabel))"))
        XCTAssertFalse(componentSource.contains(".accessoryCircularCapacity"))
        XCTAssertTrue(providerSource.contains("BatteryWidgetTimelinePlan.make(snapshot: snapshot, now: now)"))
        XCTAssertTrue(providerSource.contains("snapshotIsDisplayable: projection.snapshotIsDisplayable"))
        XCTAssertTrue(providerSource.contains("plan.reloadAfter.map { .after($0) } ?? .never"))
        XCTAssertTrue(providerSource.contains(".supportedFamilies([.systemSmall])"))
        XCTAssertFalse(providerSource.contains(".systemMedium"))
        XCTAssertTrue(providerSource.contains(".contentMarginsDisabled()"))
        XCTAssertFalse(providerSource.contains("BatteryWidgetUpdateFormatting.nextStatusChangeDate"))
    }

    func testMainSummarySeparatesAdapterCapabilityFromChargingSpeed() throws {
        let source = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatterySummaryGridView.swift")

        XCTAssertTrue(source.contains("BatteryPowerDisplayRole.role(for: snapshot).title"))
        XCTAssertTrue(source.contains("let chargingSpeed = snapshot.powerState == .charging"))
        XCTAssertTrue(source.contains("? BatterySummaryDetailFormatting.power(snapshot.activePowerWatts)"))
        XCTAssertFalse(source.contains("BatterySummaryDetailFormatting.chargingSpeed(for: snapshot)"))
        XCTAssertTrue(source.contains("powerConnectionRows(chargingSpeed: chargingSpeed)\n\n                    if showsAdvancedValues {"))
        XCTAssertTrue(source.contains("advancedRows(chargingSpeed: chargingSpeed)"))
        XCTAssertTrue(source.contains("BatteryFormatting.adapterWatts(snapshot.adapterMaxWatts)"))
        XCTAssertTrue(source.contains("title: \"Adapter Rating\""))
        XCTAssertTrue(source.contains("value: adapter"))
        XCTAssertTrue(source.contains("BatteryDetailRowView(title: \"Charging Speed\", value: chargingSpeed)"))
        XCTAssertTrue(source.contains("if chargingSpeed == nil,"))
    }

}
