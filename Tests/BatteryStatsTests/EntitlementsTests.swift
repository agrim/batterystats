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

        XCTAssertSource(
            script,
            contains: ["else\n    local status=$?\n  fi", "return \"$status\""],
            excludes: ["local status\n  local error_text\n  status=$?"]
        )
    }

    func testTestModeForwardsExtraXcodebuildArguments() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertSource(
            script,
            contains: [
                "EXTRA_XCODEBUILD_ARGS=(\"$@\")", "\"${EXTRA_XCODEBUILD_ARGS[@]}\"", "TEST_DERIVED_DATA_PATH=",
                "-derivedDataPath \"$TEST_DERIVED_DATA_PATH\"", "pluginkit -r \"$TEST_WIDGET_BUNDLE\""
            ]
        )
    }

    func testTestModeNormalizesCommonDoubleDashTestingFilters() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertSource(
            script,
            contains: [
                "normalize_xcodebuild_args()", "if ((${#EXTRA_XCODEBUILD_ARGS[@]} == 0)); then",
                "--only-testing|--skip-testing|--only-testing:*|--skip-testing:*", "normalized+=(\"-${arg#--}\")",
                "normalize_xcodebuild_args"
            ]
        )
    }

    func testRuntimeBuildsUseAutomaticSigningAndVerifyTheProduct() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertSource(
            script,
            contains: [
                "SIGNING_MODE=\"${BATTERYSTATS_SIGNING_MODE:-automatic}\"", "\"CODE_SIGN_STYLE=Automatic\"",
                "-allowProvisioningDeviceRegistration", "\"$PRODUCT_VERIFIER\" \"$APP_BUNDLE\"",
                "require_signed_runtime", "requires a signed build"
            ]
        )
    }

    func testUnsignedBuildIsAnExplicitFallback() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertSource(
            script,
            contains: ["BATTERYSTATS_SIGNING_MODE=unsigned", "SIGNING_ARGS=(\"CODE_SIGNING_ALLOWED=NO\")"],
            excludes: ["args+=(\n    CODE_SIGNING_ALLOWED=NO\n    build"]
        )
    }

    func testInstallReplacesAndRegistersTheEmbeddedWidget() throws {
        let script = try Self.loadSource(relativePath: "script/build_and_run.sh")

        XCTAssertSource(
            script,
            contains: [
                "pluginkit -r \"$old_widget\"", "pluginkit -r \"$built_widget\"", "pluginkit -r \"$registered_widget\"",
                "pluginkit -a \"$new_widget\"", "BATTERYSTATS_REQUIRE_SHARED_SNAPSHOT=1",
                "BATTERYSTATS_EXPECT_SNAPSHOT_AFTER",
                "BATTERYSTATS_INSTALL_PATH must be an absolute path ending in /BatteryStats.app"
            ]
        )
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

        XCTAssertSource(
            script,
            contains: [
                "codesign --verify --deep --strict", "codesign -d --entitlements :-", "derq macho --input", "skip=8",
                "com\\.apple\\.security\\.application-groups.0", "com\\.apple\\.developer\\.ubiquity-kvstore-identifier",
                "embedded.provisionprofile", "security cms -D -i", "BATTERYSTATS_REQUIRE_DEVELOPER_ID",
                "Developer ID products must not contain get-task-allow",
                "release bundle is missing a trusted signing timestamp", "signed app contains an embedded test bundle",
                "lipo -archs"
            ]
        )
    }

    func testInstallationVerifierChecksTheActiveWidgetPathAndSharedSnapshot() throws {
        let script = try Self.loadSource(relativePath: "script/verify_installed_widget.sh")
        let appSource = try Self.loadSource(relativePath: "BatteryStats/App/BatteryStatsApp.swift")

        XCTAssertSource(
            script,
            contains: [
                "pluginkit -m -A -D -v -i", "$WIDGET_BUNDLE", "PLUGIN_PATH_COUNT",
                "duplicate or stale BatteryStats widget registrations", "\"$APP_BINARY\" --verify-shared-widget-snapshot",
                "BATTERYSTATS_EXPECT_SNAPSHOT_AFTER"
            ],
            excludes: ["defaults export"]
        )
        XCTAssertSource(
            appSource,
            contains: [
                "SharedWidgetSnapshotRuntimeVerifier.exitIfRequested()", "BatteryWidgetSnapshotStore.shared.snapshot",
                "snapshot.timestamp.timeIntervalSinceReferenceDate"
            ]
        )
    }

    func testReleasePipelineExportsDeveloperIDThenVerifiesAndNotarizes() throws {
        let script = try Self.loadSource(relativePath: "script/package_release.sh")

        XCTAssertSource(
            script,
            contains: [
                "xcodebuild archive", "xcodebuild -exportArchive", "verify_signed_product.sh",
                "BATTERYSTATS_REQUIRE_DEVELOPER_ID=1", "xcrun notarytool submit", "xcrun stapler validate",
                "spctl -a -t open", "shasum -a 256", "require_safe_build_path",
                "OUTPUT_DMG must be a versioned BatteryStats DMG", "ARCHS=arm64"
            ]
        )
    }
}

final class ProjectSigningConfigurationTests: XCTestCase {
    func testProjectVersionAndAutomaticSigningAreReleaseCoherent() throws {
        let source = try Self.loadSource(relativePath: "project.yml")

        XCTAssertSource(
            source,
            contains: [
                "CURRENT_PROJECT_VERSION: 5", "MARKETING_VERSION: 1.0.4", "ARCHS: arm64",
                "DEVELOPMENT_TEAM: Q293G85PG5", "CODE_SIGN_STYLE: Automatic"
            ],
            excludes: [
                "CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO", "MARKETING_VERSION: 1.0.3",
                "- path: BatteryStats/Features/Battery/Data/BatteryReadingService.swift",
                "- path: BatteryStats/Features/Battery/Data/SmartBatteryReader.swift"
            ]
        )
    }
}
