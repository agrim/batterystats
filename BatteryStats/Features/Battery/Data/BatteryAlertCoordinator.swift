import Foundation
import UserNotifications

@MainActor
final class BatteryAlertCoordinator {
    private enum AlertKind: Hashable, Sendable {
        case lowBattery
        case chargeComplete
        case highTemperature
    }

    private struct AlertEvent: Sendable {
        let identifier: String
        let title: String
        let body: String
    }

    private var activeAlerts: Set<AlertKind> = []

    func evaluate(snapshot: BatterySnapshot, policy: BatteryAlertPolicy) {
        evaluate(
            kind: .lowBattery,
            isActive: policy.isLowBatteryAlertEnabled
                && snapshot.powerState == .onBattery
                && (snapshot.stateOfChargePercent ?? 100) <= policy.lowBatteryThresholdPercent,
            event: AlertEvent(
                identifier: "BatteryStats.LowBattery",
                title: "Battery Low",
                body: "Battery charge is \(BatteryFormatting.percent(snapshot.stateOfChargePercent))."
            )
        )

        evaluate(
            kind: .chargeComplete,
            isActive: policy.isChargeCompleteAlertEnabled
                && (snapshot.powerState == .fullOnAC || (snapshot.stateOfChargePercent ?? 0) >= 99),
            event: AlertEvent(
                identifier: "BatteryStats.ChargeComplete",
                title: "Battery Charged",
                body: "Battery charge is \(BatteryFormatting.percent(snapshot.stateOfChargePercent))."
            )
        )

        evaluate(
            kind: .highTemperature,
            isActive: policy.isHighTemperatureAlertEnabled
                && (snapshot.temperatureCelsius ?? 0) >= policy.highTemperatureThresholdCelsius,
            event: AlertEvent(
                identifier: "BatteryStats.HighTemperature",
                title: "Battery Temperature High",
                body: "Battery temperature is \(BatteryFormatting.temperature(snapshot.temperatureCelsius, unitPreference: .celsius))."
            )
        )
    }

    private func evaluate(kind: AlertKind, isActive: Bool, event: AlertEvent) {
        if isActive {
            guard activeAlerts.contains(kind) == false else {
                return
            }

            activeAlerts.insert(kind)
            deliver(event)
        } else {
            activeAlerts.remove(kind)
        }
    }

    private func deliver(_ event: AlertEvent) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let isAuthorized: Bool

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            case .notDetermined:
                isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            case .denied:
                isAuthorized = false
            @unknown default:
                isAuthorized = false
            }

            guard isAuthorized else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default

            let request = UNNotificationRequest(identifier: event.identifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
