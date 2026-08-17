import XCTest

final class WidgetSourceTests: XCTestCase {
    func testSmallWidgetUsesRetainedTimelineProjection() throws {
        let source = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryStatusWidgetView.swift")
        let componentSource = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryWidgetComponents.swift")
        let providerSource = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryStatusWidget.swift")

        XCTAssertSource(source, contains: [
            "let snapshot = entry.snapshot",
            "let displayedTimeMinutes = snapshot == nil ? nil : entry.displayedTimeMinutes",
            "ringTint: BatteryPresentationStyle.healthTintStyle(for: snapshot)",
            "ringTint: BatteryPresentationStyle.chargeTintStyle(for: snapshot)",
            "BatteryPresentationStyle.timeTintStyle(\n                for: snapshot,\n                displayedTimeMinutes: displayedTimeMinutes",
            "BatteryPresentationStyle.statusDescriptor(for: snapshot)",
            "BatteryMetricFormatting.timeText(minutes: displayedTimeMinutes)"
        ], excludes: [
            "entry.snapshotIsDisplayable",
            "BatterySnapshotFreshnessPolicy.isLive",
            "BatteryMediumWidgetView",
            ").color", "statusDescriptor.ringTint,", "contentTint: statusDescriptor.contentTint\n"
        ])
        XCTAssertSource(componentSource, contains: [
            ".trim(from: 0, to: progress)",
            "case empty",
            ".accessibilityLabel(Text(metric.accessibilityLabel))",
            "let ringTint: BatteryPresentationTint",
            "var contentTint: BatteryPresentationTint = .primary",
            ".stroke(metric.ringTint.color, lineWidth: lineWidth)",
            ".foregroundStyle(metric.contentTint.color)"
        ], excludes: ["BatteryMediumWidgetView", "BatteryMediumMetricView", "mediumTimeText", ".accessoryCircularCapacity", "let ringTint: Color", "var contentTint: Color"])
        XCTAssertSource(providerSource, contains: [
            "BatteryWidgetTimelinePlan.make(snapshot: snapshot, now: now)",
            "snapshot: projection.snapshotIsDisplayable ? snapshot : nil",
            "plan.reloadAfter.map { .after($0) } ?? .never",
            ".supportedFamilies([.systemSmall])",
            ".contentMarginsDisabled()"
        ], excludes: ["let snapshotIsDisplayable", ".systemMedium", "BatteryWidgetUpdateFormatting.nextStatusChangeDate"])
    }

    func testMainSummarySeparatesAdapterCapabilityFromChargingSpeed() throws {
        let source = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatterySummaryGridView.swift")

        XCTAssertSource(source, contains: [
            "BatteryPowerDisplayRole.role(for: snapshot).title",
            "let chargingSpeed = snapshot.powerState == .charging",
            "? BatterySummaryDetailFormatting.power(snapshot.activePowerWatts)",
            "powerConnectionRows(chargingSpeed: chargingSpeed)\n\n                    if showsAdvancedValues {",
            "advancedRows(chargingSpeed: chargingSpeed)",
            "BatteryFormatting.adapterWatts(snapshot.adapterMaxWatts)",
            "title: \"Adapter Rating\"",
            "value: adapter",
            "BatteryDetailRowView(title: \"Charging Speed\", value: chargingSpeed)",
            "if chargingSpeed == nil,",
            "title: \"Estimated Energy\"",
            "value: BatteryFormatting.compactWattHours(currentEnergy)",
            "let tint: BatteryPresentationTint",
            ".fill(tint.color)"
        ], excludes: ["BatterySummaryDetailFormatting.chargingSpeed(for: snapshot)", "snapshot.fullChargeCapacityWattHours", "let tint: Color"])
    }

}
