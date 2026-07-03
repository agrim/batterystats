import XCTest

final class WidgetSourceTests: XCTestCase {
    func testMediumWidgetUsesLiveDisplaySnapshotForVisibleMetrics() throws {
        let source = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryStatusWidgetView.swift")
        let componentSource = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryWidgetComponents.swift")

        XCTAssertTrue(source.contains("private var displaySnapshot: BatterySnapshot?"))
        XCTAssertTrue(source.contains("guard let snapshot = entry.snapshot,"))
        XCTAssertTrue(source.contains("let updatedAt = entry.updatedAt,"))
        XCTAssertTrue(source.contains("BatterySnapshotFreshnessPolicy.isLive(updatedAt: updatedAt, now: entry.date)"))
        XCTAssertTrue(source.contains("let snapshot = displaySnapshot"))
        XCTAssertTrue(source.contains("BatteryMediumWidgetView(\n                    snapshot: snapshot,\n                    updatedAt: entry.updatedAt,"))
        XCTAssertTrue(source.contains("updatedAt: entry.updatedAt"))
        XCTAssertFalse(source.contains("private var displayUpdatedAt: Date?"))
        XCTAssertFalse(source.contains("displaySnapshot?.timestamp"))
        XCTAssertFalse(source.contains("BatteryWidgetCompactDisplayPolicy.snapshotForMetrics("))
        XCTAssertFalse(source.contains("healthTint: BatteryPresentationStyle.healthTintStyle(for: snapshot).color"))
        XCTAssertTrue(componentSource.contains("BatteryPresentationStyle.healthTintStyle(for: snapshot).color"))
        XCTAssertTrue(componentSource.contains("BatteryPresentationStyle.chargeTintStyle(for: snapshot).color"))
        XCTAssertTrue(componentSource.contains("BatteryPresentationStyle.timeTintStyle(for: snapshot).color"))
        XCTAssertTrue(componentSource.contains("BatteryPresentationStyle.statusDescriptor(for: snapshot)"))
        XCTAssertFalse(source.contains("BatteryMediumWidgetView(\n                    snapshot: entry.snapshot"))
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
