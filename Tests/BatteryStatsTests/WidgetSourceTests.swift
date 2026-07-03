import XCTest

final class WidgetSourceTests: XCTestCase {
    func testMediumWidgetUsesLiveDisplaySnapshotForVisibleMetrics() throws {
        let source = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryStatusWidgetView.swift")

        XCTAssertTrue(source.contains("private var displaySnapshot: BatterySnapshot?"))
        XCTAssertTrue(source.contains("BatteryWidgetCompactDisplayPolicy.snapshotForMetrics("))
        XCTAssertTrue(source.contains("let snapshot = displaySnapshot"))
        XCTAssertTrue(source.contains("BatteryMediumWidgetView(\n                    snapshot: snapshot,\n                    updatedAt: entry.updatedAt,"))
        XCTAssertTrue(source.contains("updatedAt: entry.updatedAt"))
        XCTAssertFalse(source.contains("private var displayUpdatedAt: Date?"))
        XCTAssertFalse(source.contains("displaySnapshot?.timestamp"))
        XCTAssertTrue(source.contains("healthTint: BatteryPresentationStyle.healthTint(for: snapshot)"))
        XCTAssertTrue(source.contains("chargeTint: BatteryPresentationStyle.chargeTint(for: snapshot)"))
        XCTAssertTrue(source.contains("timeTint: BatteryPresentationStyle.timeTint(for: snapshot)"))
        XCTAssertTrue(source.contains("statusDescriptor: BatteryPresentationStyle.statusDescriptor(for: snapshot)"))
        XCTAssertFalse(source.contains("BatteryMediumWidgetView(\n                    snapshot: entry.snapshot"))
    }

    func testMainSummarySeparatesAdapterCapabilityFromChargingSpeed() throws {
        let source = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatterySummaryGridView.swift")

        XCTAssertTrue(source.contains("BatteryPowerDisplayRole.role(for: snapshot).title"))
        XCTAssertTrue(source.contains("let chargingSpeed = BatterySummaryDetailFormatting.chargingSpeed(for: snapshot)"))
        XCTAssertTrue(source.contains("powerConnectionRows(chargingSpeed: chargingSpeed)\n\n                    if showsAdvancedValues {"))
        XCTAssertTrue(source.contains("advancedRows(chargingSpeed: chargingSpeed)"))
        XCTAssertTrue(source.contains("BatterySummaryDetailFormatting.adapter(snapshot.adapterMaxWatts)"))
        XCTAssertTrue(source.contains("BatteryDetailRowView(title: \"Adapter Rating\", value: adapter)"))
        XCTAssertTrue(source.contains("BatteryDetailRowView(title: \"Charging Speed\", value: chargingSpeed)"))
        XCTAssertTrue(source.contains("if chargingSpeed == nil,"))
    }

    func testMediumWidgetUsesMeasuredPowerTitleWhileCharging() throws {
        let widgetSource = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryWidgetComponents.swift")
        let sharedSource = try Self.loadSource(relativePath: "BatteryStats/Shared/Widget/BatteryWidgetSnapshotStore.swift")
        let monitorSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Data/BatteryMonitor.swift")

        XCTAssertTrue(widgetSource.contains("title: powerTitle"))
        XCTAssertTrue(widgetSource.contains("BatteryPresentationStyle.batterySymbolName(for: snapshot)"))
        XCTAssertTrue(widgetSource.contains("BatteryPowerDisplayRole.role(for: snapshot).title"))
        XCTAssertTrue(monitorSource.contains("BatteryPresentationStyle.batterySymbolName(for: snapshot)"))
        XCTAssertFalse(sharedSource.contains("enum BatteryMediumWidgetFormatting"))
        XCTAssertTrue(sharedSource.contains("enum BatteryPowerDisplayRole"))
        XCTAssertTrue(sharedSource.contains("case inputPower"))
        XCTAssertTrue(sharedSource.contains("case chargeRate"))
        XCTAssertFalse(widgetSource.contains("title: \"Power\""))
        XCTAssertFalse(widgetSource.contains("snapshot?.batterySymbolName ?? \"questionmark\""))
        XCTAssertFalse(monitorSource.contains("snapshot?.batterySymbolName ?? \"questionmark\""))
    }

    func testMonitorRejectsDuplicateReadSequencePublications() throws {
        let monitorSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Data/BatteryMonitor.swift")

        XCTAssertTrue(monitorSource.contains("guard readSequence > lastAppliedReadSequence else"))
        XCTAssertFalse(monitorSource.contains("guard readSequence >= lastAppliedReadSequence else"))
    }

}
