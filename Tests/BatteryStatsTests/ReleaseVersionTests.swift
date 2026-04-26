import XCTest
@testable import BatteryStats

final class ReleaseVersionTests: XCTestCase {
    func testReleaseVersionFormatsBundleMetadata() {
        let version = ReleaseVersion.from([
            "CFBundleShortVersionString": "1.0.3",
            "CFBundleVersion": "4"
        ])

        XCTAssertEqual(version?.displayText, "Version 1.0.3 (4)")
    }

    func testReleaseVersionRejectsIncompleteMetadata() {
        XCTAssertNil(ReleaseVersion.from([
            "CFBundleShortVersionString": "1.0.3"
        ]))
    }
}
