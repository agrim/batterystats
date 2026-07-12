import XCTest
@testable import BatteryStats

@MainActor
final class BatteryAlertSettingsModelTests: XCTestCase {
    func testEnablingAlertRequestsAuthorizationAndPersistsWhenGranted() async {
        let preferences = makePreferencesStore()
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .notDetermined,
            requestStatus: .authorized
        )
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        await model.setAlertEnabled(
            true,
            preferences: preferences,
            keyPath: \.isLowBatteryAlertEnabled
        )

        XCTAssertEqual(authorizer.authorizationRequestCount, 1)
        XCTAssertEqual(model.authorizationStatus, .authorized)
        XCTAssertTrue(preferences.isLowBatteryAlertEnabled)
    }

    func testDeniedAuthorizationKeepsEnabledAlertPreferenceOff() async {
        let preferences = makePreferencesStore()
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .denied,
            requestStatus: .denied
        )
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        await model.setAlertEnabled(
            true,
            preferences: preferences,
            keyPath: \.isChargeCompleteAlertEnabled
        )

        XCTAssertEqual(authorizer.authorizationRequestCount, 1)
        XCTAssertEqual(model.authorizationStatus, .denied)
        XCTAssertFalse(preferences.isChargeCompleteAlertEnabled)
    }

    func testDeniedAuthorizationClearsAllStoredAlertPreferences() async {
        let preferences = makePreferencesStore()
        preferences.isLowBatteryAlertEnabled = true
        preferences.isChargeCompleteAlertEnabled = true
        preferences.isHighTemperatureAlertEnabled = true
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .denied,
            requestStatus: .denied
        )
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        await model.setAlertEnabled(
            true,
            preferences: preferences,
            keyPath: \.isLowBatteryAlertEnabled
        )

        XCTAssertFalse(preferences.isLowBatteryAlertEnabled)
        XCTAssertFalse(preferences.isChargeCompleteAlertEnabled)
        XCTAssertFalse(preferences.isHighTemperatureAlertEnabled)
    }

    func testRefreshingDeniedAuthorizationClearsStoredAlertPreferences() async {
        let preferences = makePreferencesStore()
        preferences.isLowBatteryAlertEnabled = true
        preferences.isChargeCompleteAlertEnabled = true
        preferences.isHighTemperatureAlertEnabled = true
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .denied,
            requestStatus: .authorized
        )
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        model.refreshAuthorizationStatus(preferences: preferences)
        await Task.yield()

        XCTAssertEqual(authorizer.statusRequestCount, 1)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        XCTAssertEqual(model.authorizationStatus, .denied)
        XCTAssertFalse(preferences.isLowBatteryAlertEnabled)
        XCTAssertFalse(preferences.isChargeCompleteAlertEnabled)
        XCTAssertFalse(preferences.isHighTemperatureAlertEnabled)
    }

    func testRefreshDoesNotCancelAuthorizationRequestInFlight() async {
        let preferences = makePreferencesStore()
        let authorizer = ControlledBatteryAlertAuthorizer(status: .denied)
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        let task = Task { @MainActor in
            await model.setAlertEnabled(
                true,
                preferences: preferences,
                keyPath: \.isLowBatteryAlertEnabled
            )
        }

        while authorizer.authorizationRequestCount == 0 {
            await Task.yield()
        }

        XCTAssertTrue(model.isResolvingAuthorization)

        model.refreshAuthorizationStatus(preferences: preferences)
        await Task.yield()

        XCTAssertEqual(authorizer.statusRequestCount, 0)
        XCTAssertTrue(model.isResolvingAuthorization)

        authorizer.resumeRequest(with: .authorized)
        await task.value

        XCTAssertFalse(model.isResolvingAuthorization)
        XCTAssertTrue(preferences.isLowBatteryAlertEnabled)
    }

    func testEnablingAlertInvalidatesAuthorizationRefreshAlreadyInFlight() async {
        let preferences = makePreferencesStore()
        let authorizer = ControlledStatusAndRequestBatteryAlertAuthorizer()
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        model.refreshAuthorizationStatus(preferences: preferences)
        await waitUntil { authorizer.statusRequestCount == 1 }

        let task = Task { @MainActor in
            await model.setAlertEnabled(
                true,
                preferences: preferences,
                keyPath: \.isLowBatteryAlertEnabled
            )
        }
        await waitUntil { authorizer.authorizationRequestCount == 1 }

        authorizer.resumeStatus(with: .denied)
        await Task.yield()

        XCTAssertEqual(model.authorizationStatus, .notDetermined)
        XCTAssertTrue(model.isResolvingAuthorization)
        XCTAssertFalse(preferences.hasEnabledAlerts)

        authorizer.resumeRequest(with: .authorized)
        await task.value

        XCTAssertEqual(model.authorizationStatus, .authorized)
        XCTAssertFalse(model.isResolvingAuthorization)
        XCTAssertTrue(preferences.isLowBatteryAlertEnabled)
    }

    func testDisablingAlertDoesNotInvalidateAuthorizationRefreshAlreadyInFlight() async {
        let preferences = makePreferencesStore()
        preferences.isLowBatteryAlertEnabled = true
        preferences.isChargeCompleteAlertEnabled = true
        let authorizer = ControlledStatusAndRequestBatteryAlertAuthorizer()
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        model.refreshAuthorizationStatus(preferences: preferences)
        await waitUntil { authorizer.statusRequestCount == 1 }

        await model.setAlertEnabled(
            false,
            preferences: preferences,
            keyPath: \.isLowBatteryAlertEnabled
        )

        XCTAssertTrue(model.isResolvingAuthorization)
        XCTAssertFalse(preferences.isLowBatteryAlertEnabled)
        XCTAssertTrue(preferences.isChargeCompleteAlertEnabled)

        authorizer.resumeStatus(with: .denied)
        await waitUntil { model.isResolvingAuthorization == false }

        XCTAssertEqual(model.authorizationStatus, .denied)
        XCTAssertFalse(preferences.isLowBatteryAlertEnabled)
        XCTAssertFalse(preferences.isChargeCompleteAlertEnabled)
        XCTAssertFalse(preferences.hasEnabledAlerts)
    }

    func testConcurrentAlertEnableRequestsPersistEachSelectedAlertWhenAuthorized() async {
        let preferences = makePreferencesStore()
        let authorizer = MultiRequestBatteryAlertAuthorizer(status: .notDetermined)
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        let lowBatteryTask = Task { @MainActor in
            await model.setAlertEnabled(
                true,
                preferences: preferences,
                keyPath: \.isLowBatteryAlertEnabled
            )
        }
        await waitUntil { authorizer.authorizationRequestCount == 1 }

        let chargeCompleteTask = Task { @MainActor in
            await model.setAlertEnabled(
                true,
                preferences: preferences,
                keyPath: \.isChargeCompleteAlertEnabled
            )
        }
        await waitUntil { authorizer.authorizationRequestCount == 2 }

        XCTAssertTrue(model.isResolvingAuthorization)

        authorizer.resumeRequest(at: 0, with: .authorized)
        await waitUntil { preferences.isLowBatteryAlertEnabled }

        XCTAssertTrue(model.isResolvingAuthorization)
        XCTAssertTrue(preferences.isLowBatteryAlertEnabled)
        XCTAssertFalse(preferences.isChargeCompleteAlertEnabled)

        authorizer.resumeRequest(at: 1, with: .authorized)
        await lowBatteryTask.value
        await chargeCompleteTask.value

        XCTAssertFalse(model.isResolvingAuthorization)
        XCTAssertTrue(preferences.isLowBatteryAlertEnabled)
        XCTAssertTrue(preferences.isChargeCompleteAlertEnabled)
        XCTAssertEqual(authorizer.authorizationRequestCount, 2)
    }

    func testDisablingAlertDoesNotRequestAuthorization() async {
        let preferences = makePreferencesStore()
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .notDetermined,
            requestStatus: .authorized
        )
        let model = BatteryAlertSettingsModel(authorizer: authorizer)
        preferences.isHighTemperatureAlertEnabled = true

        await model.setAlertEnabled(
            false,
            preferences: preferences,
            keyPath: \.isHighTemperatureAlertEnabled
        )

        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        XCTAssertFalse(preferences.isHighTemperatureAlertEnabled)
    }

    func testDeniedAuthorizationStillClearsAlertsAfterRequestedAlertWasDisabled() async {
        let preferences = makePreferencesStore()
        preferences.isChargeCompleteAlertEnabled = true
        let authorizer = ControlledBatteryAlertAuthorizer(status: .notDetermined)
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        let task = Task { @MainActor in
            await model.setAlertEnabled(
                true,
                preferences: preferences,
                keyPath: \.isLowBatteryAlertEnabled
            )
        }
        await waitUntil { authorizer.authorizationRequestCount == 1 }

        await model.setAlertEnabled(
            false,
            preferences: preferences,
            keyPath: \.isLowBatteryAlertEnabled
        )

        authorizer.resumeRequest(with: .denied)
        await task.value

        XCTAssertEqual(model.authorizationStatus, .denied)
        XCTAssertFalse(model.isResolvingAuthorization)
        XCTAssertFalse(preferences.isLowBatteryAlertEnabled)
        XCTAssertFalse(preferences.isChargeCompleteAlertEnabled)
        XCTAssertFalse(preferences.hasEnabledAlerts)
    }

    func testResetCancelsPendingAlertEnableWriteAfterAuthorizationCompletes() async {
        let preferences = makePreferencesStore()
        let authorizer = ControlledBatteryAlertAuthorizer(status: .notDetermined)
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        let task = Task { @MainActor in
            await model.setAlertEnabled(
                true,
                preferences: preferences,
                keyPath: \.isLowBatteryAlertEnabled
            )
        }
        await waitUntil { authorizer.authorizationRequestCount == 1 }

        model.cancelPendingAlertEnables()
        preferences.reset()

        authorizer.resumeRequest(with: .authorized)
        await task.value

        XCTAssertEqual(model.authorizationStatus, .authorized)
        XCTAssertFalse(model.isResolvingAuthorization)
        XCTAssertFalse(preferences.isLowBatteryAlertEnabled)
        XCTAssertFalse(preferences.hasEnabledAlerts)
    }

    func testRefreshAuthorizationStatusDoesNotRequestAuthorization() async {
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .authorized,
            requestStatus: .denied
        )
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        model.refreshAuthorizationStatus()
        await Task.yield()

        XCTAssertEqual(authorizer.statusRequestCount, 1)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        XCTAssertEqual(model.authorizationStatus, .authorized)
    }

    func testRefreshAuthorizationStatusShowsResolvingWhileInFlight() async {
        let authorizer = ControlledStatusAndRequestBatteryAlertAuthorizer()
        let model = BatteryAlertSettingsModel(authorizer: authorizer)

        model.refreshAuthorizationStatus()
        await waitUntil { authorizer.statusRequestCount == 1 }

        XCTAssertTrue(model.isResolvingAuthorization)

        authorizer.resumeStatus(with: .authorized)
        await waitUntil { model.isResolvingAuthorization == false }

        XCTAssertFalse(model.isResolvingAuthorization)
        XCTAssertEqual(model.authorizationStatus, .authorized)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
    }

    func testRuntimeAuthorizationObserverClearsDeniedStoredAlertsWithoutSettingsView() async {
        let preferences = makePreferencesStore()
        preferences.isLowBatteryAlertEnabled = true
        preferences.isChargeCompleteAlertEnabled = true
        preferences.isHighTemperatureAlertEnabled = true
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .denied,
            requestStatus: .authorized
        )
        let observer = BatteryAlertAuthorizationObserver(
            preferences: preferences,
            authorizer: authorizer
        )

        observer.start()
        await waitUntil { preferences.hasEnabledAlerts == false }

        XCTAssertEqual(authorizer.statusRequestCount, 1)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        XCTAssertFalse(preferences.isLowBatteryAlertEnabled)
        XCTAssertFalse(preferences.isChargeCompleteAlertEnabled)
        XCTAssertFalse(preferences.isHighTemperatureAlertEnabled)
        withExtendedLifetime(observer) {}
    }

    func testRuntimeAuthorizationObserverClearsDeniedAlertChangesWithoutSettingsView() async {
        let preferences = makePreferencesStore()
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .denied,
            requestStatus: .authorized
        )
        let observer = BatteryAlertAuthorizationObserver(
            preferences: preferences,
            authorizer: authorizer
        )

        observer.start()
        await Task.yield()

        XCTAssertEqual(authorizer.statusRequestCount, 0)

        preferences.isHighTemperatureAlertEnabled = true
        await waitUntil { preferences.hasEnabledAlerts == false }

        XCTAssertEqual(authorizer.statusRequestCount, 1)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        XCTAssertFalse(preferences.isHighTemperatureAlertEnabled)
        withExtendedLifetime(observer) {}
    }

    func testRuntimeAuthorizationObserverKeepsNotDeterminedSyncedAlertsForSettingsPrompt() async {
        let preferences = makePreferencesStore()
        preferences.isLowBatteryAlertEnabled = true
        preferences.isChargeCompleteAlertEnabled = true
        preferences.isHighTemperatureAlertEnabled = true
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .notDetermined,
            requestStatus: .authorized
        )
        let observer = BatteryAlertAuthorizationObserver(
            preferences: preferences,
            authorizer: authorizer
        )

        observer.start()
        await waitUntil { authorizer.statusRequestCount == 1 }

        XCTAssertEqual(authorizer.statusRequestCount, 1)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        XCTAssertTrue(preferences.isLowBatteryAlertEnabled)
        XCTAssertTrue(preferences.isChargeCompleteAlertEnabled)
        XCTAssertTrue(preferences.isHighTemperatureAlertEnabled)
        XCTAssertTrue(preferences.hasEnabledAlerts)
        withExtendedLifetime(observer) {}
    }

    func testRuntimeAuthorizationObserverKeepsNotDeterminedAlertChangesForSettingsPrompt() async {
        let preferences = makePreferencesStore()
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .notDetermined,
            requestStatus: .authorized
        )
        let observer = BatteryAlertAuthorizationObserver(
            preferences: preferences,
            authorizer: authorizer
        )

        observer.start()
        await Task.yield()

        XCTAssertEqual(authorizer.statusRequestCount, 0)

        preferences.isHighTemperatureAlertEnabled = true
        await waitUntil { authorizer.statusRequestCount == 1 }

        XCTAssertEqual(authorizer.statusRequestCount, 1)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        XCTAssertTrue(preferences.isHighTemperatureAlertEnabled)
        XCTAssertTrue(preferences.hasEnabledAlerts)
        withExtendedLifetime(observer) {}
    }

    func testRuntimeAuthorizationObserverLeavesAuthorizedAlertsEnabled() async {
        let preferences = makePreferencesStore()
        preferences.isLowBatteryAlertEnabled = true
        let authorizer = FakeBatteryAlertAuthorizer(
            status: .authorized,
            requestStatus: .denied
        )
        let observer = BatteryAlertAuthorizationObserver(
            preferences: preferences,
            authorizer: authorizer
        )

        observer.start()
        await waitUntil { authorizer.statusRequestCount == 1 }

        XCTAssertTrue(preferences.isLowBatteryAlertEnabled)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        withExtendedLifetime(observer) {}
    }

    func testRuntimeAuthorizationRefreshBeforeStartDoesNotRequestStatus() async {
        let preferences = makePreferencesStore()
        preferences.isChargeCompleteAlertEnabled = true
        let authorizer = MutableBatteryAlertAuthorizer(status: .denied)
        let observer = BatteryAlertAuthorizationObserver(
            preferences: preferences,
            authorizer: authorizer
        )

        observer.refreshAuthorizationStatus()
        await Task.yield()

        XCTAssertTrue(preferences.isChargeCompleteAlertEnabled)
        XCTAssertEqual(authorizer.statusRequestCount, 0)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        withExtendedLifetime(observer) {}
    }

    func testRuntimeAuthorizationRefreshClearsAlertsAfterExternalPermissionDenial() async {
        let preferences = makePreferencesStore()
        preferences.isChargeCompleteAlertEnabled = true
        let authorizer = MutableBatteryAlertAuthorizer(status: .authorized)
        let observer = BatteryAlertAuthorizationObserver(
            preferences: preferences,
            authorizer: authorizer
        )

        observer.start()
        await waitUntil { authorizer.statusRequestCount == 1 }

        XCTAssertTrue(preferences.isChargeCompleteAlertEnabled)

        authorizer.status = .denied
        observer.refreshAuthorizationStatus()
        await waitUntil { preferences.hasEnabledAlerts == false }

        XCTAssertEqual(authorizer.statusRequestCount, 2)
        XCTAssertEqual(authorizer.authorizationRequestCount, 0)
        XCTAssertFalse(preferences.isChargeCompleteAlertEnabled)
        withExtendedLifetime(observer) {}
    }

    private func makePreferencesStore() -> PreferencesStore {
        PreferencesStore(
            defaults: makeIsolatedUserDefaults(prefix: "BatteryAlertSettingsModelTests").defaults,
            sync: NoopAlertPreferencesSync()
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if condition() {
                return
            }

            await Task.yield()
        }
    }
}

@MainActor
private final class FakeBatteryAlertAuthorizer: BatteryAlertAuthorizing {
    private let status: BatteryAlertAuthorizationStatus
    private let requestStatus: BatteryAlertAuthorizationStatus
    private(set) var statusRequestCount = 0
    private(set) var authorizationRequestCount = 0

    init(
        status: BatteryAlertAuthorizationStatus,
        requestStatus: BatteryAlertAuthorizationStatus
    ) {
        self.status = status
        self.requestStatus = requestStatus
    }

    func authorizationStatus() async -> BatteryAlertAuthorizationStatus {
        statusRequestCount += 1
        return status
    }

    func requestAuthorization() async -> BatteryAlertAuthorizationStatus {
        authorizationRequestCount += 1
        return requestStatus
    }
}

@MainActor
private final class MutableBatteryAlertAuthorizer: BatteryAlertAuthorizing {
    var status: BatteryAlertAuthorizationStatus
    private(set) var statusRequestCount = 0
    private(set) var authorizationRequestCount = 0

    init(status: BatteryAlertAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> BatteryAlertAuthorizationStatus {
        statusRequestCount += 1
        return status
    }

    func requestAuthorization() async -> BatteryAlertAuthorizationStatus {
        authorizationRequestCount += 1
        return status
    }
}

@MainActor
private final class ControlledBatteryAlertAuthorizer: BatteryAlertAuthorizing {
    private let status: BatteryAlertAuthorizationStatus
    private var continuation: CheckedContinuation<BatteryAlertAuthorizationStatus, Never>?
    private(set) var statusRequestCount = 0
    private(set) var authorizationRequestCount = 0

    init(status: BatteryAlertAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> BatteryAlertAuthorizationStatus {
        statusRequestCount += 1
        return status
    }

    func requestAuthorization() async -> BatteryAlertAuthorizationStatus {
        authorizationRequestCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resumeRequest(with status: BatteryAlertAuthorizationStatus) {
        continuation?.resume(returning: status)
        continuation = nil
    }
}

@MainActor
private final class ControlledStatusAndRequestBatteryAlertAuthorizer: BatteryAlertAuthorizing {
    private var statusContinuation: CheckedContinuation<BatteryAlertAuthorizationStatus, Never>?
    private var requestContinuation: CheckedContinuation<BatteryAlertAuthorizationStatus, Never>?
    private(set) var statusRequestCount = 0
    private(set) var authorizationRequestCount = 0

    func authorizationStatus() async -> BatteryAlertAuthorizationStatus {
        statusRequestCount += 1
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
        }
    }

    func requestAuthorization() async -> BatteryAlertAuthorizationStatus {
        authorizationRequestCount += 1
        return await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func resumeStatus(with status: BatteryAlertAuthorizationStatus) {
        statusContinuation?.resume(returning: status)
        statusContinuation = nil
    }

    func resumeRequest(with status: BatteryAlertAuthorizationStatus) {
        requestContinuation?.resume(returning: status)
        requestContinuation = nil
    }
}

@MainActor
private final class MultiRequestBatteryAlertAuthorizer: BatteryAlertAuthorizing {
    private let status: BatteryAlertAuthorizationStatus
    private var continuations: [CheckedContinuation<BatteryAlertAuthorizationStatus, Never>?] = []
    private(set) var statusRequestCount = 0
    private(set) var authorizationRequestCount = 0

    init(status: BatteryAlertAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> BatteryAlertAuthorizationStatus {
        statusRequestCount += 1
        return status
    }

    func requestAuthorization() async -> BatteryAlertAuthorizationStatus {
        authorizationRequestCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeRequest(at index: Int, with status: BatteryAlertAuthorizationStatus) {
        continuations[index]?.resume(returning: status)
        continuations[index] = nil
    }
}

@MainActor
private final class NoopAlertPreferencesSync: PreferencesSyncing {
    let isEnabled = false
    let isAvailable = true
    let availabilityDescription = "iCloud sync is not used in these tests."

    func setEnabled(_ enabled: Bool) {}

    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol {
        NSObject()
    }

    func removeObserver(_ token: NSObjectProtocol) {}

    func hasValue(forKey key: String) -> Bool {
        false
    }

    func bool(forKey key: String) -> Bool? {
        nil
    }

    func string(forKey key: String) -> String? {
        nil
    }

    func set(_ value: Bool, forKey key: String) {}

    func set(_ value: String, forKey key: String) {}

    func removeValue(forKey key: String) {}

    func flush() {}
}
