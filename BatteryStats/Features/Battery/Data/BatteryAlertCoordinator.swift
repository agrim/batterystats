import Foundation
import UserNotifications

enum BatteryAlertType: Hashable, Sendable {
    case lowBattery
    case chargeComplete
    case highTemperature
}

enum BatteryAlertEvaluator {
    static func activeAlertTypes(snapshot: BatterySnapshot, policy: BatteryAlertPolicy) -> Set<BatteryAlertType> {
        var activeTypes: Set<BatteryAlertType> = []

        if policy.isLowBatteryAlertEnabled,
           snapshot.powerState.isBatteryDischarging,
           let stateOfChargePercent = snapshot.presentationStateOfChargePercent,
           stateOfChargePercent <= policy.lowBatteryThresholdPercent {
            activeTypes.insert(.lowBattery)
        }

        if policy.isChargeCompleteAlertEnabled,
           isChargeCompleteCandidate(snapshot) {
            activeTypes.insert(.chargeComplete)
        }

        if policy.isHighTemperatureAlertEnabled,
           let temperatureCelsius = snapshot.presentationTemperatureCelsius,
           temperatureCelsius >= policy.highTemperatureThresholdCelsius {
            activeTypes.insert(.highTemperature)
        }

        return activeTypes
    }

    private static func isChargeCompleteCandidate(_ snapshot: BatterySnapshot) -> Bool {
        switch snapshot.powerState {
        case .charging, .connectedNotCharging:
            return (snapshot.presentationStateOfChargePercent ?? 0) >= 99
        case .fullOnAC:
            return true
        case .connectedDischarging, .onBattery, .unknown:
            return false
        }
    }
}

struct BatteryAlertNotification: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

@MainActor
protocol BatteryAlertNotificationDelivering: AnyObject {
    func deliver(_ notification: BatteryAlertNotification) async -> Bool
}

@MainActor
protocol BatteryAlertNotificationCentering: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
final class BatteryAlertCoordinator {
    private var activeAlerts: Set<BatteryAlertType> = []
    private var pendingDeliveries: [BatteryAlertType: Int] = [:]
    private var pendingDeliveryTasks: [BatteryAlertType: Task<Void, Never>] = [:]
    private var deliveryGeneration = 0
    private let notificationDeliverer: any BatteryAlertNotificationDelivering

    init(notificationDeliverer: any BatteryAlertNotificationDelivering = UserNotificationBatteryAlertDeliverer()) {
        self.notificationDeliverer = notificationDeliverer
    }

    func updatePolicy(_ policy: BatteryAlertPolicy, currentSnapshot: BatterySnapshot?) {
        clearDisabledAlerts(for: policy)

        guard let currentSnapshot else {
            return
        }

        evaluate(snapshot: currentSnapshot, policy: policy)
    }

    func clearActiveAlerts() {
        activeAlerts.removeAll()
        pendingDeliveries.removeAll()
        cancelPendingDeliveryTasks()
    }

    func evaluate(snapshot: BatterySnapshot, policy: BatteryAlertPolicy) {
        let activeAlertTypes = BatteryAlertEvaluator.activeAlertTypes(snapshot: snapshot, policy: policy)

        evaluate(
            kind: .lowBattery,
            isActive: activeAlertTypes.contains(.lowBattery),
            notification: BatteryAlertNotification(
                identifier: "BatteryStats.LowBattery",
                title: "Battery Low",
                body: chargeBody(for: snapshot, fallback: "Battery charge is low.")
            )
        )

        evaluate(
            kind: .chargeComplete,
            isActive: activeAlertTypes.contains(.chargeComplete),
            notification: BatteryAlertNotification(
                identifier: "BatteryStats.ChargeComplete",
                title: "Battery Charged",
                body: chargeBody(for: snapshot, fallback: "Battery is fully charged.")
            )
        )

        evaluate(
            kind: .highTemperature,
            isActive: activeAlertTypes.contains(.highTemperature),
            notification: BatteryAlertNotification(
                identifier: "BatteryStats.HighTemperature",
                title: "Battery Temperature High",
                body: "Battery temperature is \(BatteryFormatting.temperature(snapshot.presentationTemperatureCelsius, unitPreference: policy.temperatureUnitPreference))."
            )
        )
    }

    private func clearDisabledAlerts(for policy: BatteryAlertPolicy) {
        if policy.isLowBatteryAlertEnabled == false {
            clearAlertState(for: .lowBattery)
        }

        if policy.isChargeCompleteAlertEnabled == false {
            clearAlertState(for: .chargeComplete)
        }

        if policy.isHighTemperatureAlertEnabled == false {
            clearAlertState(for: .highTemperature)
        }
    }

    private func chargeBody(for snapshot: BatterySnapshot, fallback: String) -> String {
        guard let stateOfChargePercent = snapshot.presentationStateOfChargePercent else {
            return fallback
        }

        return "Battery charge is \(BatteryFormatting.percent(stateOfChargePercent))."
    }

    private func evaluate(kind: BatteryAlertType, isActive: Bool, notification: BatteryAlertNotification) {
        if isActive {
            guard activeAlerts.contains(kind) == false,
                  pendingDeliveries[kind] == nil else {
                return
            }

            deliveryGeneration &+= 1
            let generation = deliveryGeneration
            pendingDeliveries[kind] = generation

            let deliveryTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard pendingDeliveries[kind] == generation,
                      Task.isCancelled == false else {
                    return
                }

                let didDeliver = await notificationDeliverer.deliver(notification)
                guard pendingDeliveries[kind] == generation,
                      Task.isCancelled == false else {
                    return
                }

                pendingDeliveries.removeValue(forKey: kind)
                pendingDeliveryTasks.removeValue(forKey: kind)
                if didDeliver {
                    activeAlerts.insert(kind)
                }
            }
            pendingDeliveryTasks[kind] = deliveryTask
        } else {
            clearAlertState(for: kind)
        }
    }

    private func clearAlertState(for kind: BatteryAlertType) {
        activeAlerts.remove(kind)
        pendingDeliveries.removeValue(forKey: kind)
        pendingDeliveryTasks.removeValue(forKey: kind)?.cancel()
    }

    private func cancelPendingDeliveryTasks() {
        for task in pendingDeliveryTasks.values {
            task.cancel()
        }

        pendingDeliveryTasks.removeAll()
    }
}

#if DEBUG
extension BatteryAlertCoordinator {
    func waitForIdleForTesting() async {
        while pendingDeliveries.isEmpty == false {
            await Task.yield()
        }
    }
}
#endif

@MainActor
final class UserNotificationBatteryAlertDeliverer: BatteryAlertNotificationDelivering {
    private let notificationCenter: any BatteryAlertNotificationCentering

    init(notificationCenter: any BatteryAlertNotificationCentering = UserNotificationCenterAdapter()) {
        self.notificationCenter = notificationCenter
    }

    func deliver(_ notification: BatteryAlertNotification) async -> Bool {
        guard Task.isCancelled == false else {
            return false
        }

        let authorizationStatus = await notificationCenter.authorizationStatus()
        guard Task.isCancelled == false else {
            return false
        }

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        do {
            guard Task.isCancelled == false else {
                return false
            }

            try await notificationCenter.add(request)
            return true
        } catch {
            return false
        }
    }
}

@MainActor
private final class UserNotificationCenterAdapter: BatteryAlertNotificationCentering {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }
}
