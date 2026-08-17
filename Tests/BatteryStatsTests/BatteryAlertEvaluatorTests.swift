import XCTest
import UserNotifications
@testable import BatteryStats

@MainActor
final class BatteryAlertEvaluatorTests: XCTestCase {
    func testChargeCompleteAlertDoesNotFireForHighChargeOnBattery() {
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: 99
        )
        let policy = BatteryAlertPolicy(isChargeCompleteAlertEnabled: true)

        XCTAssertFalse(
            BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy).contains(.chargeComplete)
        )
    }

    func testChargeCompleteAlertDoesNotFireWhenExternalFlagDisagreesWithBatteryPowerState() {
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: true,
            stateOfChargePercent: 99
        )
        let policy = BatteryAlertPolicy(isChargeCompleteAlertEnabled: true)

        XCTAssertFalse(
            BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy).contains(.chargeComplete)
        )
    }

    func testChargeCompleteAlertDoesNotFireForConnectedDischarging() {
        let snapshot = makeSnapshot(
            powerState: .connectedDischarging,
            isCharging: false,
            isExternalPowerConnected: true,
            stateOfChargePercent: 99
        )
        let policy = BatteryAlertPolicy(isChargeCompleteAlertEnabled: true)

        XCTAssertFalse(
            BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy).contains(.chargeComplete)
        )
    }

    func testChargeCompleteAlertCanFireForHighChargeOnExternalPower() {
        let snapshot = makeSnapshot(
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            stateOfChargePercent: 99
        )
        let policy = BatteryAlertPolicy(isChargeCompleteAlertEnabled: true)

        XCTAssertTrue(
            BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy).contains(.chargeComplete)
        )
    }

    func testChargeCompleteAlertUsesDerivedFullACStateWhenExternalFlagDisagrees() {
        let snapshot = makeSnapshot(
            powerState: .fullOnAC,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: 100
        )
        let policy = BatteryAlertPolicy(isChargeCompleteAlertEnabled: true)

        XCTAssertTrue(
            BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy).contains(.chargeComplete)
        )
    }

    func testLowBatteryAlertIgnoresInvalidNegativeChargePercent() {
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: -1
        )
        let policy = BatteryAlertPolicy(isLowBatteryAlertEnabled: true)

        XCTAssertFalse(
            BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy).contains(.lowBattery)
        )
    }

    func testLowBatteryAlertCanFireForConnectedDischarging() {
        let snapshot = makeSnapshot(
            powerState: .connectedDischarging,
            isCharging: false,
            isExternalPowerConnected: true,
            stateOfChargePercent: 10
        )
        let policy = BatteryAlertPolicy(isLowBatteryAlertEnabled: true)

        XCTAssertTrue(
            BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy).contains(.lowBattery)
        )
    }

    func testHighTemperatureAlertIgnoresImplausibleTemperature() {
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: 55,
            temperatureCelsius: 180
        )
        let policy = BatteryAlertPolicy(isHighTemperatureAlertEnabled: true)

        XCTAssertFalse(
            BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy).contains(.highTemperature)
        )
    }

    func testHighTemperatureAlertUsesSelectedTemperatureUnit() async {
        let deliverer = FakeBatteryAlertNotificationDeliverer()
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: 55,
            temperatureCelsius: 42
        )
        let policy = BatteryAlertPolicy(
            isHighTemperatureAlertEnabled: true,
            temperatureUnitPreference: .fahrenheit
        )

        coordinator.evaluate(snapshot: snapshot, policy: policy)
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(deliverer.notifications.first?.title, "Battery Temperature High")
        XCTAssertEqual(deliverer.notifications.first?.body, "Battery temperature is 107.6 °F.")
    }

    func testCoordinatorClearsDisabledAlertStateWhenPolicyChanges() async {
        let deliverer = FakeBatteryAlertNotificationDeliverer()
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: 10
        )
        let enabledPolicy = BatteryAlertPolicy(isLowBatteryAlertEnabled: true)

        coordinator.evaluate(snapshot: snapshot, policy: enabledPolicy)
        await coordinator.waitForIdleForTesting()
        coordinator.updatePolicy(enabledPolicy, currentSnapshot: snapshot)
        await coordinator.waitForIdleForTesting()
        coordinator.updatePolicy(.disabled, currentSnapshot: snapshot)
        coordinator.updatePolicy(enabledPolicy, currentSnapshot: snapshot)
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(
            deliverer.notifications.map(\.identifier),
            ["BatteryStats.LowBattery", "BatteryStats.LowBattery"]
        )
    }

    func testCoordinatorRetriesActiveAlertWhenDeliveryFails() async {
        let deliverer = FakeBatteryAlertNotificationDeliverer(deliveryResults: [false, true])
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: 10
        )
        let policy = BatteryAlertPolicy(isLowBatteryAlertEnabled: true)

        coordinator.evaluate(snapshot: snapshot, policy: policy)
        await coordinator.waitForIdleForTesting()
        coordinator.evaluate(snapshot: snapshot, policy: policy)
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(
            deliverer.notifications.map(\.identifier),
            ["BatteryStats.LowBattery", "BatteryStats.LowBattery"]
        )
    }

    func testCoordinatorCancelsPendingAlertDeliveryWhenAlertClears() async {
        let deliverer = SuspendingBatteryAlertNotificationDeliverer()
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let lowBatterySnapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: 10
        )
        let recoveredSnapshot = makeSnapshot(
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            stateOfChargePercent: 55
        )
        let policy = BatteryAlertPolicy(isLowBatteryAlertEnabled: true)

        coordinator.evaluate(snapshot: lowBatterySnapshot, policy: policy)
        await deliverer.waitForStartedDeliveryCount(1)

        coordinator.evaluate(snapshot: recoveredSnapshot, policy: policy)
        deliverer.resumeAll()
        await deliverer.waitForCancelledDeliveryCount(1)
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(deliverer.startedNotifications.map(\.identifier), ["BatteryStats.LowBattery"])
        XCTAssertEqual(deliverer.cancelledNotifications.map(\.identifier), ["BatteryStats.LowBattery"])
        XCTAssertTrue(deliverer.deliveredNotifications.isEmpty)
    }

    func testCoordinatorCancelsPendingAlertDeliveryWhenPolicyDisablesAlert() async {
        let deliverer = SuspendingBatteryAlertNotificationDeliverer()
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let snapshot = makeSnapshot(
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            stateOfChargePercent: 10
        )
        let policy = BatteryAlertPolicy(isLowBatteryAlertEnabled: true)

        coordinator.evaluate(snapshot: snapshot, policy: policy)
        await deliverer.waitForStartedDeliveryCount(1)

        coordinator.updatePolicy(.disabled, currentSnapshot: snapshot)
        deliverer.resumeAll()
        await deliverer.waitForCancelledDeliveryCount(1)
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(deliverer.startedNotifications.map(\.identifier), ["BatteryStats.LowBattery"])
        XCTAssertEqual(deliverer.cancelledNotifications.map(\.identifier), ["BatteryStats.LowBattery"])
        XCTAssertTrue(deliverer.deliveredNotifications.isEmpty)
    }

    func testChargeCompleteNotificationUsesFallbackBodyWhenPercentIsUnavailable() async {
        let deliverer = FakeBatteryAlertNotificationDeliverer()
        let coordinator = BatteryAlertCoordinator(notificationDeliverer: deliverer)
        let snapshot = makeSnapshot(
            powerState: .fullOnAC,
            isCharging: false,
            isExternalPowerConnected: true,
            stateOfChargePercent: nil
        )
        let policy = BatteryAlertPolicy(isChargeCompleteAlertEnabled: true)

        coordinator.evaluate(snapshot: snapshot, policy: policy)
        await coordinator.waitForIdleForTesting()

        XCTAssertEqual(deliverer.notifications.first?.title, "Battery Charged")
        XCTAssertEqual(deliverer.notifications.first?.body, "Battery is fully charged.")
    }

    func testUserNotificationDelivererDoesNotRequestPermissionWhenAuthorizationIsNotDetermined() async {
        let notificationCenter = FakeBatteryAlertNotificationCenter(authorizationStatus: .notDetermined)
        let deliverer = UserNotificationBatteryAlertDeliverer(notificationCenter: notificationCenter)

        let didDeliver = await deliverer.deliver(makeNotification())

        XCTAssertFalse(didDeliver)
        XCTAssertEqual(notificationCenter.authorizationStatusRequestCount, 1)
        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func testUserNotificationDelivererDoesNotAddRequestWhenAuthorizationIsDenied() async {
        let notificationCenter = FakeBatteryAlertNotificationCenter(authorizationStatus: .denied)
        let deliverer = UserNotificationBatteryAlertDeliverer(notificationCenter: notificationCenter)

        let didDeliver = await deliverer.deliver(makeNotification())

        XCTAssertFalse(didDeliver)
        XCTAssertEqual(notificationCenter.authorizationStatusRequestCount, 1)
        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func testUserNotificationDelivererAddsRequestWhenAuthorizationIsGranted() async throws {
        let notificationCenter = FakeBatteryAlertNotificationCenter(authorizationStatus: .authorized)
        let deliverer = UserNotificationBatteryAlertDeliverer(notificationCenter: notificationCenter)

        let didDeliver = await deliverer.deliver(makeNotification())

        XCTAssertTrue(didDeliver)
        XCTAssertEqual(notificationCenter.authorizationStatusRequestCount, 1)
        let request = try XCTUnwrap(notificationCenter.addedRequests.first)
        XCTAssertEqual(request.identifier, "BatteryStats.Test")
        XCTAssertEqual(request.content.title, "Test")
        XCTAssertEqual(request.content.body, "Body")
    }

    func testUserNotificationDelivererReportsFailureWhenAddFails() async {
        let notificationCenter = FakeBatteryAlertNotificationCenter(
            authorizationStatus: .authorized,
            addError: TestNotificationCenterError.addFailed
        )
        let deliverer = UserNotificationBatteryAlertDeliverer(notificationCenter: notificationCenter)

        let didDeliver = await deliverer.deliver(makeNotification())

        XCTAssertFalse(didDeliver)
        XCTAssertEqual(notificationCenter.addedRequests.count, 1)
    }

    private func makeSnapshot(
        powerState: BatteryPowerState,
        isCharging: Bool,
        isExternalPowerConnected: Bool,
        stateOfChargePercent: Double?,
        temperatureCelsius: Double = 32
    ) -> BatterySnapshot {
        makeBatterySnapshot(
            powerState: powerState,
            isCharging: isCharging,
            isExternalPowerConnected: isExternalPowerConnected,
            currentChargeMilliampHours: 4_950,
            healthPercent: 83.3,
            stateOfChargePercent: stateOfChargePercent,
            voltageMillivolts: 12_800,
            currentMilliampsSigned: isCharging ? 900 : -500,
            dischargeRateMilliamps: isCharging ? nil : 500,
            chargeRateWatts: isCharging ? 11.5 : nil,
            dischargeRateWatts: isCharging ? nil : 6.4,
            rateBasedTimeRemainingMinutes: isCharging ? nil : 594,
            systemTimeRemainingMinutes: isCharging ? nil : 590,
            timeToFullMinutes: isCharging ? 5 : nil,
            cycleCount: 100,
            temperatureCelsius: temperatureCelsius,
            adapterMaxWatts: 70,
        )
    }

    private func makeNotification() -> BatteryAlertNotification {
        BatteryAlertNotification(
            identifier: "BatteryStats.Test",
            title: "Test",
            body: "Body"
        )
    }
}

@MainActor
private final class FakeBatteryAlertNotificationDeliverer: BatteryAlertNotificationDelivering {
    private(set) var notifications: [BatteryAlertNotification] = []
    private var deliveryResults: [Bool]

    init(deliveryResults: [Bool] = []) {
        self.deliveryResults = deliveryResults
    }

    func deliver(_ notification: BatteryAlertNotification) async -> Bool {
        notifications.append(notification)
        guard deliveryResults.isEmpty == false else {
            return true
        }

        return deliveryResults.removeFirst()
    }
}

@MainActor
private final class SuspendingBatteryAlertNotificationDeliverer: BatteryAlertNotificationDelivering {
    private(set) var startedNotifications: [BatteryAlertNotification] = []
    private(set) var deliveredNotifications: [BatteryAlertNotification] = []
    private(set) var cancelledNotifications: [BatteryAlertNotification] = []

    private var deliveryContinuations: [CheckedContinuation<Void, Never>] = []
    private var startContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancelContinuations: [(Int, CheckedContinuation<Void, Never>)] = []

    func deliver(_ notification: BatteryAlertNotification) async -> Bool {
        startedNotifications.append(notification)
        resumeSatisfiedStartContinuations()

        await withCheckedContinuation { continuation in
            deliveryContinuations.append(continuation)
        }

        if Task.isCancelled {
            cancelledNotifications.append(notification)
            resumeSatisfiedCancelContinuations()
            return false
        }

        deliveredNotifications.append(notification)
        return true
    }

    func waitForStartedDeliveryCount(_ count: Int) async {
        guard startedNotifications.count < count else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append((count, continuation))
        }
    }

    func waitForCancelledDeliveryCount(_ count: Int) async {
        guard cancelledNotifications.count < count else {
            return
        }

        await withCheckedContinuation { continuation in
            cancelContinuations.append((count, continuation))
        }
    }

    func resumeAll() {
        let continuations = deliveryContinuations
        deliveryContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func resumeSatisfiedStartContinuations() {
        let readyContinuations = startContinuations.filter { startedNotifications.count >= $0.0 }
        startContinuations.removeAll { startedNotifications.count >= $0.0 }
        readyContinuations.forEach { $0.1.resume() }
    }

    private func resumeSatisfiedCancelContinuations() {
        let readyContinuations = cancelContinuations.filter { cancelledNotifications.count >= $0.0 }
        cancelContinuations.removeAll { cancelledNotifications.count >= $0.0 }
        readyContinuations.forEach { $0.1.resume() }
    }
}

@MainActor
private final class FakeBatteryAlertNotificationCenter: BatteryAlertNotificationCentering {
    let authorizationStatus: UNAuthorizationStatus
    let addError: Error?
    private(set) var authorizationStatusRequestCount = 0
    private(set) var addedRequests: [UNNotificationRequest] = []

    init(
        authorizationStatus: UNAuthorizationStatus,
        addError: Error? = nil
    ) {
        self.authorizationStatus = authorizationStatus
        self.addError = addError
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusRequestCount += 1
        return authorizationStatus
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
        if let addError {
            throw addError
        }
    }
}

private enum TestNotificationCenterError: Error {
    case addFailed
}
