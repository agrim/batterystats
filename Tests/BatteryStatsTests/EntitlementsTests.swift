import XCTest

final class EntitlementsTests: XCTestCase {
    func testAppEntitlementsIncludeICloudKeyValueStoreAndAppGroup() throws {
        let entitlements = try loadEntitlements(
            relativePath: "BatteryStats/Resources/BatteryStats.entitlements"
        )

        XCTAssertEqual(
            entitlements["com.apple.developer.ubiquity-kvstore-identifier"] as? String,
            "$(TeamIdentifierPrefix)io.github.agrim.batterystats"
        )
        XCTAssertEqual(
            entitlements["com.apple.security.application-groups"] as? [String],
            ["group.io.github.agrim.batterystats"]
        )
    }

    func testWidgetEntitlementsIncludeSharedAppGroup() throws {
        let entitlements = try loadEntitlements(
            relativePath: "BatteryStatsWidgets/BatteryStatsWidgets.entitlements"
        )

        XCTAssertEqual(
            entitlements["com.apple.security.application-groups"] as? [String],
            ["group.io.github.agrim.batterystats"]
        )
    }

    private func loadEntitlements(relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.sourceURL(relativePath: relativePath))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        return try XCTUnwrap(plist as? [String: Any])
    }
}

final class BuildRunScriptTests: XCTestCase {
    func testVerifyModePreservesFailedProcessCheckStatus() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertTrue(script.contains("else\n    local status=$?\n  fi"))
        XCTAssertTrue(script.contains("return \"$status\""))
        XCTAssertFalse(script.contains("local status\n  local error_text\n  status=$?"))
    }

    func testTestModeForwardsExtraXcodebuildArguments() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertTrue(script.contains("EXTRA_XCODEBUILD_ARGS=(\"$@\")"))
        XCTAssertTrue(script.contains("\"${EXTRA_XCODEBUILD_ARGS[@]}\""))
    }

    func testTestModeNormalizesCommonDoubleDashTestingFilters() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertTrue(script.contains("normalize_xcodebuild_args()"))
        XCTAssertTrue(script.contains("if ((${#EXTRA_XCODEBUILD_ARGS[@]} == 0)); then"))
        XCTAssertTrue(script.contains("--only-testing|--skip-testing|--only-testing:*|--skip-testing:*"))
        XCTAssertTrue(script.contains("normalized+=(\"-${arg#--}\")"))
        XCTAssertTrue(script.contains("normalize_xcodebuild_args"))
    }
}
