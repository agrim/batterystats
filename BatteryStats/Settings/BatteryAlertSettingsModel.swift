import Foundation
import Observation
import UserNotifications

enum BatteryAlertAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied

    var canDeliverAlerts: Bool {
        self == .authorized
    }

    var statusDescription: String {
        switch self {
        case .notDetermined:
            return "macOS will ask for notification permission when you enable an alert."
        case .authorized:
            return "Battery alerts can deliver notifications."
        case .denied:
            return "Notifications are off for BatteryStats in System Settings."
        }
    }
}

@MainActor
protocol BatteryAlertAuthorizing {
    func authorizationStatus() async -> BatteryAlertAuthorizationStatus
    func requestAuthorization() async -> BatteryAlertAuthorizationStatus
}

@MainActor
@Observable
final class BatteryAlertSettingsModel {
    private(set) var authorizationStatus: BatteryAlertAuthorizationStatus = .notDetermined
    private(set) var isResolvingAuthorization = false

    @ObservationIgnored private let authorizer: any BatteryAlertAuthorizing
    @ObservationIgnored private var authorizationGeneration = 0
    @ObservationIgnored private var alertPreferenceGenerations: [PartialKeyPath<PreferencesStore>: Int] = [:]
    @ObservationIgnored private var activeAuthorizationRequestCount = 0
    @ObservationIgnored private var activeAuthorizationStatusRefreshCount = 0

    init(authorizer: any BatteryAlertAuthorizing = UserNotificationBatteryAlertAuthorizer()) {
        self.authorizer = authorizer
    }

    var statusDescription: String {
        authorizationStatus.statusDescription
    }

    func cancelPendingAlertEnables() {
        invalidatePendingAlertEnables()
    }

    func refreshAuthorizationStatus(preferences: PreferencesStore? = nil) {
        guard isResolvingAuthorization == false else {
            return
        }

        authorizationGeneration &+= 1
        let generation = authorizationGeneration
        activeAuthorizationStatusRefreshCount += 1
        updateResolvingAuthorizationState()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let status = await authorizer.authorizationStatus()
            activeAuthorizationStatusRefreshCount = max(0, activeAuthorizationStatusRefreshCount - 1)
            updateResolvingAuthorizationState()

            guard authorizationGeneration == generation else {
                return
            }

            apply(status, to: preferences)
        }
    }

    func setAlertEnabled(
        _ enabled: Bool,
        preferences: PreferencesStore,
        keyPath: ReferenceWritableKeyPath<PreferencesStore, Bool>
    ) async {
        let preferenceKey: PartialKeyPath<PreferencesStore> = keyPath
        alertPreferenceGenerations[preferenceKey, default: 0] &+= 1
        let generation = alertPreferenceGenerations[preferenceKey] ?? 0

        guard enabled else {
            preferences[keyPath: keyPath] = false
            return
        }

        authorizationGeneration &+= 1
        activeAuthorizationRequestCount += 1
        updateResolvingAuthorizationState()
        let status = await authorizer.requestAuthorization()
        activeAuthorizationRequestCount = max(0, activeAuthorizationRequestCount - 1)
        updateResolvingAuthorizationState()

        let isCurrentPreferenceRequest = alertPreferenceGenerations[preferenceKey] == generation
        apply(status, to: status.canDeliverAlerts ? nil : preferences)

        if status.canDeliverAlerts == false {
            invalidatePendingAlertEnables()
            return
        }

        guard isCurrentPreferenceRequest else {
            return
        }

        preferences[keyPath: keyPath] = true
    }

    private func updateResolvingAuthorizationState() {
        isResolvingAuthorization = activeAuthorizationRequestCount + activeAuthorizationStatusRefreshCount > 0
    }

    private func invalidatePendingAlertEnables() {
        alertPreferenceGenerations = alertPreferenceGenerations.mapValues { $0 &+ 1 }
    }

    private func apply(_ status: BatteryAlertAuthorizationStatus, to preferences: PreferencesStore?) {
        authorizationStatus = status

        guard status == .denied else {
            return
        }

        preferences?.disableAllAlerts()
    }
}

@MainActor
final class BatteryAlertAuthorizationObserver {
    private let preferences: PreferencesStore
    private let authorizer: any BatteryAlertAuthorizing
    private var isStarted = false
    private var observationGeneration = 0
    private var reconciliationGeneration = 0

    init(
        preferences: PreferencesStore,
        authorizer: any BatteryAlertAuthorizing = UserNotificationBatteryAlertAuthorizer()
    ) {
        self.preferences = preferences
        self.authorizer = authorizer
    }

    func start() {
        guard isStarted == false else {
            return
        }

        isStarted = true
        reconcileIfNeeded()
        observeAlertPreferences()
    }

    func refreshAuthorizationStatus() {
        guard isStarted else {
            return
        }

        reconcileIfNeeded()
    }

    private func observeAlertPreferences() {
        observationGeneration &+= 1
        let generation = observationGeneration

        withObservationTracking {
            _ = preferences.isLowBatteryAlertEnabled
            _ = preferences.isChargeCompleteAlertEnabled
            _ = preferences.isHighTemperatureAlertEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      isStarted,
                      observationGeneration == generation else {
                    return
                }

                reconcileIfNeeded()
                observeAlertPreferences()
            }
        }
    }

    private func reconcileIfNeeded() {
        guard preferences.hasEnabledAlerts else {
            return
        }

        reconciliationGeneration &+= 1
        let generation = reconciliationGeneration

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let status = await authorizer.authorizationStatus()
            guard isStarted,
                  reconciliationGeneration == generation,
                  status == .denied else {
                return
            }

            preferences.disableAllAlerts()
        }
    }
}

@MainActor
private struct UserNotificationBatteryAlertAuthorizer: BatteryAlertAuthorizing {
    func authorizationStatus() async -> BatteryAlertAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.status(from: settings.authorizationStatus)
    }

    func requestAuthorization() async -> BatteryAlertAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            let isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            return isAuthorized ? .authorized : .denied
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private static func status(from status: UNAuthorizationStatus) -> BatteryAlertAuthorizationStatus {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
