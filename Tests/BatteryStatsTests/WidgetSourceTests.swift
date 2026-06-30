import XCTest

final class WidgetSourceTests: XCTestCase {
    func testMediumWidgetUsesLiveDisplaySnapshotForVisibleMetrics() throws {
        let source = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryStatusWidgetView.swift")

        XCTAssertTrue(source.contains("private var displaySnapshot: BatterySnapshot?"))
        XCTAssertTrue(source.contains("BatteryWidgetCompactDisplayPolicy.snapshotForMetrics("))
        XCTAssertTrue(source.contains("BatteryMediumWidgetView(\n                    snapshot: displaySnapshot,\n                    updatedAt: entry.updatedAt,"))
        XCTAssertTrue(source.contains("updatedAt: entry.updatedAt"))
        XCTAssertFalse(source.contains("private var displayUpdatedAt: Date?"))
        XCTAssertFalse(source.contains("displaySnapshot?.timestamp"))
        XCTAssertTrue(source.contains("healthTint: BatteryPresentationStyle.healthTint(for: displaySnapshot)"))
        XCTAssertTrue(source.contains("chargeTint: BatteryPresentationStyle.chargeTint(for: displaySnapshot)"))
        XCTAssertTrue(source.contains("timeTint: BatteryPresentationStyle.timeTint(for: displaySnapshot)"))
        XCTAssertTrue(source.contains("statusDescriptor: BatteryPresentationStyle.statusDescriptor(for: displaySnapshot)"))
        XCTAssertFalse(source.contains("BatteryMediumWidgetView(\n                    snapshot: entry.snapshot"))
    }

    func testMainSummarySeparatesAdapterCapabilityFromChargingSpeed() throws {
        let source = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Presentation/BatterySummaryGridView.swift")

        XCTAssertTrue(source.contains("BatterySummaryDetailFormatting.powerTitle(for: snapshot)"))
        XCTAssertTrue(source.contains("return \"Input Power\""))
        XCTAssertTrue(source.contains("return \"Charge Rate\""))
        XCTAssertTrue(source.contains("powerConnectionRows\n\n                    if showsAdvancedValues {"))
        XCTAssertTrue(source.contains("BatterySummaryDetailFormatting.adapter(snapshot.adapterMaxWatts)"))
        XCTAssertTrue(source.contains("BatterySummaryDetailFormatting.chargingSpeed(for: snapshot)"))
        XCTAssertTrue(source.contains("BatteryDetailRowView(title: \"Adapter Rating\", value: adapter)"))
        XCTAssertTrue(source.contains("BatteryDetailRowView(title: \"Charging Speed\", value: chargingSpeed)"))
        XCTAssertTrue(source.contains("if BatterySummaryDetailFormatting.chargingSpeed(for: snapshot) == nil,"))
    }

    func testMediumWidgetUsesMeasuredPowerTitleWhileCharging() throws {
        let widgetSource = try Self.loadSource(relativePath: "BatteryStatsWidgets/BatteryWidgetComponents.swift")
        let sharedSource = try Self.loadSource(relativePath: "BatteryStats/Shared/Widget/BatteryWidgetSnapshotStore.swift")
        let monitorSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Data/BatteryMonitor.swift")

        XCTAssertTrue(widgetSource.contains("title: powerTitle"))
        XCTAssertTrue(widgetSource.contains("BatteryPresentationStyle.batterySymbolName(for: snapshot)"))
        XCTAssertTrue(widgetSource.contains("BatteryMediumWidgetFormatting.powerTitle(for: snapshot)"))
        XCTAssertTrue(monitorSource.contains("BatteryPresentationStyle.batterySymbolName(for: snapshot)"))
        XCTAssertTrue(sharedSource.contains("static func powerTitle(for snapshot: BatterySnapshot?) -> String"))
        XCTAssertTrue(sharedSource.contains("return \"Input Power\""))
        XCTAssertTrue(sharedSource.contains("return \"Charge Rate\""))
        XCTAssertFalse(widgetSource.contains("title: \"Power\""))
        XCTAssertFalse(widgetSource.contains("snapshot?.batterySymbolName ?? \"questionmark\""))
        XCTAssertFalse(monitorSource.contains("snapshot?.batterySymbolName ?? \"questionmark\""))
    }

    func testMonitorRejectsDuplicateReadSequencePublications() throws {
        let monitorSource = try Self.loadSource(relativePath: "BatteryStats/Features/Battery/Data/BatteryMonitor.swift")

        XCTAssertTrue(monitorSource.contains("guard readSequence > lastAppliedReadSequence else"))
        XCTAssertFalse(monitorSource.contains("guard readSequence >= lastAppliedReadSequence else"))
    }

    private static func loadSource(relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
