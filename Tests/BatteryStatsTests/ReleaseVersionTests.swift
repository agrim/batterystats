import XCTest
@testable import BatteryStats

final class ReleaseVersionTests: XCTestCase {
    func testReleaseVersionFormatsBundleMetadata() {
        let version = ReleaseVersion.from([
            "CFBundleShortVersionString": " 1.0.3 ",
            "CFBundleVersion": " 4 "
        ])

        XCTAssertEqual(version?.displayText, "Version 1.0.3 (4)")
    }

    func testReleaseVersionFormatsNumericPlistMetadata() {
        let version = ReleaseVersion.from([
            "CFBundleShortVersionString": NSNumber(value: 1.03),
            "CFBundleVersion": NSNumber(value: 4)
        ])

        XCTAssertEqual(version?.displayText, "Version 1.03 (4)")
    }

    func testReleaseVersionRejectsIncompleteMetadata() {
        XCTAssertNil(ReleaseVersion.from([
            "CFBundleShortVersionString": "1.0.3"
        ]))

        XCTAssertNil(ReleaseVersion.from([
            "CFBundleShortVersionString": "   ",
            "CFBundleVersion": "4"
        ]))

        XCTAssertNil(ReleaseVersion.from([
            "CFBundleShortVersionString": "1.0.3",
            "CFBundleVersion": "\n\t"
        ]))

        XCTAssertNil(ReleaseVersion.from([
            "CFBundleShortVersionString": true,
            "CFBundleVersion": 4
        ]))
    }
}
