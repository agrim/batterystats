import XCTest
@testable import BatteryStats

@MainActor
final class LaunchAtLoginSettingsModelTests: XCTestCase {
    func testRefreshPublishesCurrentSystemState() {
        let manager = FakeLaunchAtLoginManager(isEnabled: false, statusDescription: "Off")
        let model = LaunchAtLoginSettingsModel(manager: manager)

        manager.isEnabled = true
        manager.statusDescription = "Enabled"
        model.refresh()

        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.statusDescription, "Enabled")
    }

    func testSuccessfulUpdateClearsErrorAndRefreshesState() {
        let manager = FakeLaunchAtLoginManager(isEnabled: false, statusDescription: "Off")
        let model = LaunchAtLoginSettingsModel(manager: manager)
        manager.error = TestLaunchAtLoginError.message("Register failed")
        model.setEnabled(true)
        XCTAssertEqual(model.errorMessage, "Register failed")

        manager.error = nil
        manager.statusDescription = "Enabled"
        model.setEnabled(true)

        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.statusDescription, "Enabled")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isUpdating)
    }

    func testFailedUpdateFallsBackToManagerState() {
        let manager = FakeLaunchAtLoginManager(isEnabled: false, statusDescription: "Off")
        let model = LaunchAtLoginSettingsModel(manager: manager)
        manager.error = TestLaunchAtLoginError.message("Register failed")

        model.setEnabled(true)

        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.statusDescription, "Off")
        XCTAssertEqual(model.errorMessage, "Register failed")
        XCTAssertFalse(model.isUpdating)
    }

    func testRefreshClearsStaleErrorMessage() {
        let manager = FakeLaunchAtLoginManager(isEnabled: false, statusDescription: "Off")
        let model = LaunchAtLoginSettingsModel(manager: manager)
        manager.error = TestLaunchAtLoginError.message("Register failed")
        model.setEnabled(true)

        manager.error = nil
        manager.isEnabled = true
        manager.statusDescription = "Enabled"
        model.refresh()

        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.statusDescription, "Enabled")
        XCTAssertNil(model.errorMessage)
    }

    func testSettingAlreadyCurrentStateDoesNotCallServiceAgain() {
        let manager = FakeLaunchAtLoginManager(isEnabled: true, statusDescription: "Enabled")
        let model = LaunchAtLoginSettingsModel(manager: manager)

        manager.error = TestLaunchAtLoginError.message("Register failed")
        manager.statusDescription = "Already Enabled"
        model.setEnabled(true)

        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.statusDescription, "Already Enabled")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(manager.setEnabledCallCount, 0)
        XCTAssertFalse(model.isUpdating)
    }
}

@MainActor
private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool
    var statusDescription: String
    var error: Error?
    private(set) var setEnabledCallCount = 0

    init(isEnabled: Bool, statusDescription: String) {
        self.isEnabled = isEnabled
        self.statusDescription = statusDescription
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCallCount += 1

        if let error {
            throw error
        }

        isEnabled = enabled
    }
}

private enum TestLaunchAtLoginError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}
