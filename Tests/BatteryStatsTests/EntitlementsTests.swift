import XCTest
@testable import BatteryStats

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
            [BatteryWidgetSnapshotStore.appGroupIdentifier]
        )
    }

    func testWidgetEntitlementsIncludeSharedAppGroup() throws {
        let entitlements = try loadEntitlements(
            relativePath: "BatteryStatsWidgets/BatteryStatsWidgets.entitlements"
        )

        XCTAssertEqual(
            entitlements["com.apple.security.application-groups"] as? [String],
            [BatteryWidgetSnapshotStore.appGroupIdentifier]
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
        XCTAssertTrue(script.contains("TEST_DERIVED_DATA_PATH="))
        XCTAssertTrue(script.contains("-derivedDataPath \"$TEST_DERIVED_DATA_PATH\""))
        XCTAssertTrue(script.contains("pluginkit -r \"$TEST_WIDGET_BUNDLE\""))
    }

    func testTestModeNormalizesCommonDoubleDashTestingFilters() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertTrue(script.contains("normalize_xcodebuild_args()"))
        XCTAssertTrue(script.contains("if ((${#EXTRA_XCODEBUILD_ARGS[@]} == 0)); then"))
        XCTAssertTrue(script.contains("--only-testing|--skip-testing|--only-testing:*|--skip-testing:*"))
        XCTAssertTrue(script.contains("normalized+=(\"-${arg#--}\")"))
        XCTAssertTrue(script.contains("normalize_xcodebuild_args"))
    }

    func testRuntimeBuildsUseAutomaticSigningAndVerifyTheProduct() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertTrue(script.contains("SIGNING_MODE=\"${BATTERYSTATS_SIGNING_MODE:-automatic}\""))
        XCTAssertTrue(script.contains("\"CODE_SIGN_STYLE=Automatic\""))
        XCTAssertTrue(script.contains("-allowProvisioningDeviceRegistration"))
        XCTAssertTrue(script.contains("\"$PRODUCT_VERIFIER\" \"$APP_BUNDLE\""))
        XCTAssertTrue(script.contains("require_signed_runtime"))
        XCTAssertTrue(script.contains("requires a signed build"))
    }

    func testUnsignedBuildIsAnExplicitFallback() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertTrue(script.contains("BATTERYSTATS_SIGNING_MODE=unsigned"))
        XCTAssertTrue(script.contains("SIGNING_ARGS=(\"CODE_SIGNING_ALLOWED=NO\")"))
        XCTAssertFalse(script.contains("args+=(\n    CODE_SIGNING_ALLOWED=NO\n    build"))
    }

    func testInstallReplacesAndRegistersTheEmbeddedWidget() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertTrue(script.contains("pluginkit -r \"$old_widget\""))
        XCTAssertTrue(script.contains("pluginkit -r \"$built_widget\""))
        XCTAssertTrue(script.contains("pluginkit -r \"$registered_widget\""))
        XCTAssertTrue(script.contains("pluginkit -a \"$new_widget\""))
        XCTAssertTrue(script.contains("BATTERYSTATS_REQUIRE_SHARED_SNAPSHOT=1"))
        XCTAssertTrue(script.contains("BATTERYSTATS_EXPECT_SNAPSHOT_AFTER"))
        XCTAssertTrue(script.contains("BATTERYSTATS_INSTALL_PATH must be an absolute path ending in /BatteryStats.app"))
    }

    func testUnknownRuntimeModeIsRejectedBeforeBuild() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")
        let validation = try XCTUnwrap(script.range(of: "run|install|--debug|debug"))
        let build = try XCTUnwrap(script.range(of: "require_signed_runtime\npkill"))

        XCTAssertLessThan(validation.lowerBound, build.lowerBound)
    }
}

final class SignedProductVerifierSourceTests: XCTestCase {
    func testVerifierChecksEffectiveEntitlementsAndProvisioning() throws {
        let script = try Self.loadSource(relativePath: "script/verify_signed_product.sh")

        XCTAssertTrue(script.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(script.contains("codesign -d --entitlements :-"))
        XCTAssertTrue(script.contains("derq macho --input"))
        XCTAssertTrue(script.contains("skip=8"))
        XCTAssertTrue(script.contains("com\\.apple\\.security\\.application-groups.0"))
        XCTAssertTrue(script.contains("com\\.apple\\.developer\\.ubiquity-kvstore-identifier"))
        XCTAssertTrue(script.contains("embedded.provisionprofile"))
        XCTAssertTrue(script.contains("security cms -D -i"))
        XCTAssertTrue(script.contains("BATTERYSTATS_REQUIRE_DEVELOPER_ID"))
        XCTAssertTrue(script.contains("Developer ID products must not contain get-task-allow"))
        XCTAssertTrue(script.contains("release bundle is missing a trusted signing timestamp"))
        XCTAssertTrue(script.contains("signed app contains an embedded test bundle"))
        XCTAssertTrue(script.contains("lipo -archs"))
    }

    func testInstallationVerifierChecksTheActiveWidgetPathAndSharedSnapshot() throws {
        let script = try Self.loadSource(relativePath: "script/verify_installed_widget.sh")
        let appSource = try Self.loadSource(relativePath: "BatteryStats/App/BatteryStatsApp.swift")

        XCTAssertTrue(script.contains("pluginkit -m -A -D -v -i"))
        XCTAssertTrue(script.contains("$WIDGET_BUNDLE"))
        XCTAssertTrue(script.contains("PLUGIN_PATH_COUNT"))
        XCTAssertTrue(script.contains("duplicate or stale BatteryStats widget registrations"))
        XCTAssertTrue(script.contains("\"$APP_BINARY\" --verify-shared-widget-snapshot"))
        XCTAssertTrue(script.contains("BATTERYSTATS_EXPECT_SNAPSHOT_AFTER"))
        XCTAssertFalse(script.contains("defaults export"))
        XCTAssertTrue(appSource.contains("SharedWidgetSnapshotRuntimeVerifier.exitIfRequested()"))
        XCTAssertTrue(appSource.contains("BatteryWidgetSnapshotStore.shared.snapshot"))
        XCTAssertTrue(appSource.contains("snapshot.timestamp.timeIntervalSinceReferenceDate"))
    }

    func testReleasePipelineExportsDeveloperIDThenVerifiesAndNotarizes() throws {
        let script = try Self.loadSource(relativePath: "script/package_release.sh")

        XCTAssertTrue(script.contains("xcodebuild archive"))
        XCTAssertTrue(script.contains("xcodebuild -exportArchive"))
        XCTAssertTrue(script.contains("verify_signed_product.sh"))
        XCTAssertTrue(script.contains("BATTERYSTATS_REQUIRE_DEVELOPER_ID=1"))
        XCTAssertTrue(script.contains("xcrun notarytool submit"))
        XCTAssertTrue(script.contains("xcrun stapler validate"))
        XCTAssertTrue(script.contains("spctl -a -t open"))
        XCTAssertTrue(script.contains("shasum -a 256"))
        XCTAssertTrue(script.contains("require_safe_build_path"))
        XCTAssertTrue(script.contains("OUTPUT_DMG must be a versioned BatteryStats DMG"))
        XCTAssertTrue(script.contains("ARCHS=arm64"))
    }
}

final class ProjectSigningConfigurationTests: XCTestCase {
    func testProjectVersionAndAutomaticSigningAreReleaseCoherent() throws {
        let source = try Self.loadSource(relativePath: "project.yml")

        XCTAssertTrue(source.contains("CURRENT_PROJECT_VERSION: 5"))
        XCTAssertTrue(source.contains("MARKETING_VERSION: 1.0.4"))
        XCTAssertTrue(source.contains("ARCHS: arm64"))
        XCTAssertTrue(source.contains("DEVELOPMENT_TEAM: Q293G85PG5"))
        XCTAssertTrue(source.contains("CODE_SIGN_STYLE: Automatic"))
        XCTAssertFalse(source.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO"))
        XCTAssertFalse(source.contains("MARKETING_VERSION: 1.0.3"))
        XCTAssertFalse(source.contains("- path: BatteryStats/Features/Battery/Data/BatteryReadingService.swift"))
        XCTAssertFalse(source.contains("- path: BatteryStats/Features/Battery/Data/SmartBatteryReader.swift"))
    }
}
