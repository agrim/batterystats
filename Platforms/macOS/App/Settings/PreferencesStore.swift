@preconcurrency import Foundation
import Observation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case iconAndPercentage
    case iconAndTimeRemaining
    case iconAndHealth
    case iconAndFullCharge
    case iconAndTemperature
    case iconAndPower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly:
            return "Icon Only"
        case .iconAndPercentage:
            return "Icon + Percentage"
        case .iconAndTimeRemaining:
            return "Icon + Time"
        case .iconAndHealth:
            return "Icon + Health"
        case .iconAndFullCharge:
            return "Icon + Capacity"
        case .iconAndTemperature:
            return "Icon + Temperature"
        case .iconAndPower:
            return "Icon + Power"
        }
    }
}

@MainActor
@Observable
final class PreferencesStore {
    private enum Key {
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let temperatureUnitPreference = "temperatureUnitPreference"
        static let showAdvancedValues = "showAdvancedValues"
        static let isICloudSyncEnabled = "isICloudSyncEnabled"
        static let refreshCadencePreference = "refreshCadencePreference"
        static let energyChangeSensitivity = "energyChangeSensitivity"
        static let isLowBatteryAlertEnabled = "isLowBatteryAlertEnabled"
        static let isChargeCompleteAlertEnabled = "isChargeCompleteAlertEnabled"
        static let isHighTemperatureAlertEnabled = "isHighTemperatureAlertEnabled"
        static let isHistoryEnabled = "isHistoryEnabled"
        static let isHistoryICloudSyncEnabled = "isHistoryICloudSyncEnabled"
    }

    var launchAtLoginEnabled: Bool {
        didSet { persist(launchAtLoginEnabled, forKey: Key.launchAtLoginEnabled, syncToCloud: false) }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { persist(menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode, syncToCloud: true) }
    }

    var temperatureUnitPreference: TemperatureUnitPreference {
        didSet { persist(temperatureUnitPreference.rawValue, forKey: Key.temperatureUnitPreference, syncToCloud: true) }
    }

    var showAdvancedValues: Bool {
        didSet { persist(showAdvancedValues, forKey: Key.showAdvancedValues, syncToCloud: true) }
    }

    var refreshCadencePreference: RefreshCadencePreference {
        didSet { persist(refreshCadencePreference.rawValue, forKey: Key.refreshCadencePreference, syncToCloud: true) }
    }

    var energyChangeSensitivity: EnergyChangeSensitivity {
        didSet { persist(energyChangeSensitivity.rawValue, forKey: Key.energyChangeSensitivity, syncToCloud: true) }
    }

    var isLowBatteryAlertEnabled: Bool {
        didSet { persist(isLowBatteryAlertEnabled, forKey: Key.isLowBatteryAlertEnabled, syncToCloud: true) }
    }

    var isChargeCompleteAlertEnabled: Bool {
        didSet { persist(isChargeCompleteAlertEnabled, forKey: Key.isChargeCompleteAlertEnabled, syncToCloud: true) }
    }

    var isHighTemperatureAlertEnabled: Bool {
        didSet { persist(isHighTemperatureAlertEnabled, forKey: Key.isHighTemperatureAlertEnabled, syncToCloud: true) }
    }

    var isHistoryEnabled: Bool {
        didSet { persist(isHistoryEnabled, forKey: Key.isHistoryEnabled, syncToCloud: true) }
    }

    var isHistoryICloudSyncEnabled: Bool {
        didSet { persist(isHistoryICloudSyncEnabled, forKey: Key.isHistoryICloudSyncEnabled, syncToCloud: true) }
    }

    var isICloudSyncEnabled: Bool {
        didSet {
            defaults.set(isICloudSyncEnabled, forKey: Key.isICloudSyncEnabled)
            sync.setEnabled(isICloudSyncEnabled)

            if isICloudSyncEnabled {
                pullRemoteValues()
                pushLocalValues()
            }
        }
    }

    var syncStatusMessage: String

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sync: ICloudPreferencesSync
    @ObservationIgnored private var observerToken: NSObjectProtocol?
    @ObservationIgnored private var isApplyingRemoteChanges = false

    init(defaults: UserDefaults = .standard, sync: ICloudPreferencesSync = ICloudPreferencesSync()) {
        self.defaults = defaults
        self.sync = sync

        launchAtLoginEnabled = defaults.object(forKey: Key.launchAtLoginEnabled) as? Bool ?? false
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: defaults.string(forKey: Key.menuBarDisplayMode) ?? "") ?? .iconAndPercentage
        temperatureUnitPreference = TemperatureUnitPreference(rawValue: defaults.string(forKey: Key.temperatureUnitPreference) ?? "") ?? .system
        showAdvancedValues = defaults.object(forKey: Key.showAdvancedValues) as? Bool ?? false
        refreshCadencePreference = RefreshCadencePreference(rawValue: defaults.string(forKey: Key.refreshCadencePreference) ?? "") ?? .dynamic
        energyChangeSensitivity = EnergyChangeSensitivity(rawValue: defaults.string(forKey: Key.energyChangeSensitivity) ?? "") ?? .balanced
        isLowBatteryAlertEnabled = defaults.object(forKey: Key.isLowBatteryAlertEnabled) as? Bool ?? false
        isChargeCompleteAlertEnabled = defaults.object(forKey: Key.isChargeCompleteAlertEnabled) as? Bool ?? false
        isHighTemperatureAlertEnabled = defaults.object(forKey: Key.isHighTemperatureAlertEnabled) as? Bool ?? false
        isHistoryEnabled = defaults.object(forKey: Key.isHistoryEnabled) as? Bool ?? false
        isHistoryICloudSyncEnabled = defaults.object(forKey: Key.isHistoryICloudSyncEnabled) as? Bool ?? false
        isICloudSyncEnabled = defaults.object(forKey: Key.isICloudSyncEnabled) as? Bool ?? false
        syncStatusMessage = sync.availabilityDescription

        sync.setEnabled(isICloudSyncEnabled)

        observerToken = sync.observeChanges { [weak self] changedKeys in
            Task { @MainActor in
                self?.applyRemoteChanges(for: changedKeys)
            }
        }

        if isICloudSyncEnabled {
            pullRemoteValues()
            pushLocalValues()
        }
    }

    func reset() {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        launchAtLoginEnabled = false
        menuBarDisplayMode = .iconAndPercentage
        temperatureUnitPreference = .system
        showAdvancedValues = false
        refreshCadencePreference = .dynamic
        energyChangeSensitivity = .balanced
        isLowBatteryAlertEnabled = false
        isChargeCompleteAlertEnabled = false
        isHighTemperatureAlertEnabled = false
        isHistoryEnabled = false
        isHistoryICloudSyncEnabled = false
        isICloudSyncEnabled = false

        defaults.removeObject(forKey: Key.launchAtLoginEnabled)
        defaults.removeObject(forKey: Key.menuBarDisplayMode)
        defaults.removeObject(forKey: Key.temperatureUnitPreference)
        defaults.removeObject(forKey: Key.showAdvancedValues)
        defaults.removeObject(forKey: Key.refreshCadencePreference)
        defaults.removeObject(forKey: Key.energyChangeSensitivity)
        defaults.removeObject(forKey: Key.isLowBatteryAlertEnabled)
        defaults.removeObject(forKey: Key.isChargeCompleteAlertEnabled)
        defaults.removeObject(forKey: Key.isHighTemperatureAlertEnabled)
        defaults.removeObject(forKey: Key.isHistoryEnabled)
        defaults.removeObject(forKey: Key.isHistoryICloudSyncEnabled)
        defaults.removeObject(forKey: Key.isICloudSyncEnabled)
        syncStatusMessage = sync.availabilityDescription
    }

    var refreshPolicy: BatteryRefreshPolicy {
        BatteryRefreshPolicy(
            cadence: refreshCadencePreference,
            energyChangeSensitivity: energyChangeSensitivity
        )
    }

    var alertPolicy: BatteryAlertPolicy {
        BatteryAlertPolicy(
            isLowBatteryAlertEnabled: isLowBatteryAlertEnabled,
            isChargeCompleteAlertEnabled: isChargeCompleteAlertEnabled,
            isHighTemperatureAlertEnabled: isHighTemperatureAlertEnabled
        )
    }

    var historyPolicy: BatteryHistoryPolicy {
        BatteryHistoryPolicy(
            isEnabled: isHistoryEnabled,
            syncsToICloud: isHistoryEnabled && isHistoryICloudSyncEnabled
        )
    }

    private func pullRemoteValues() {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        if let remoteMode = sync.string(forKey: Key.menuBarDisplayMode),
           let mode = MenuBarDisplayMode(rawValue: remoteMode) {
            menuBarDisplayMode = mode
        }

        if let remoteTemperature = sync.string(forKey: Key.temperatureUnitPreference),
           let temperature = TemperatureUnitPreference(rawValue: remoteTemperature) {
            temperatureUnitPreference = temperature
        }

        if let remoteShowAdvanced = sync.bool(forKey: Key.showAdvancedValues) {
            showAdvancedValues = remoteShowAdvanced
        }

        if let remoteRefreshCadence = sync.string(forKey: Key.refreshCadencePreference),
           let refreshCadence = RefreshCadencePreference(rawValue: remoteRefreshCadence) {
            refreshCadencePreference = refreshCadence
        }

        if let remoteSensitivity = sync.string(forKey: Key.energyChangeSensitivity),
           let sensitivity = EnergyChangeSensitivity(rawValue: remoteSensitivity) {
            energyChangeSensitivity = sensitivity
        }

        if let remoteLowBatteryAlert = sync.bool(forKey: Key.isLowBatteryAlertEnabled) {
            isLowBatteryAlertEnabled = remoteLowBatteryAlert
        }

        if let remoteChargeCompleteAlert = sync.bool(forKey: Key.isChargeCompleteAlertEnabled) {
            isChargeCompleteAlertEnabled = remoteChargeCompleteAlert
        }

        if let remoteHighTemperatureAlert = sync.bool(forKey: Key.isHighTemperatureAlertEnabled) {
            isHighTemperatureAlertEnabled = remoteHighTemperatureAlert
        }

        if let remoteHistoryEnabled = sync.bool(forKey: Key.isHistoryEnabled) {
            isHistoryEnabled = remoteHistoryEnabled
        }

        if let remoteHistorySync = sync.bool(forKey: Key.isHistoryICloudSyncEnabled) {
            isHistoryICloudSyncEnabled = remoteHistorySync
        }
    }

    private func pushLocalValues() {
        sync.set(menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode)
        sync.set(temperatureUnitPreference.rawValue, forKey: Key.temperatureUnitPreference)
        sync.set(showAdvancedValues, forKey: Key.showAdvancedValues)
        sync.set(refreshCadencePreference.rawValue, forKey: Key.refreshCadencePreference)
        sync.set(energyChangeSensitivity.rawValue, forKey: Key.energyChangeSensitivity)
        sync.set(isLowBatteryAlertEnabled, forKey: Key.isLowBatteryAlertEnabled)
        sync.set(isChargeCompleteAlertEnabled, forKey: Key.isChargeCompleteAlertEnabled)
        sync.set(isHighTemperatureAlertEnabled, forKey: Key.isHighTemperatureAlertEnabled)
        sync.set(isHistoryEnabled, forKey: Key.isHistoryEnabled)
        sync.set(isHistoryICloudSyncEnabled, forKey: Key.isHistoryICloudSyncEnabled)
    }

    private func applyRemoteChanges(for changedKeys: [String]) {
        guard isICloudSyncEnabled else {
            return
        }

        syncStatusMessage = sync.availabilityDescription

        guard changedKeys.isEmpty == false else {
            pullRemoteValues()
            return
        }

        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        if changedKeys.contains(Key.menuBarDisplayMode),
           let rawValue = sync.string(forKey: Key.menuBarDisplayMode),
           let remoteValue = MenuBarDisplayMode(rawValue: rawValue) {
            menuBarDisplayMode = remoteValue
        }

        if changedKeys.contains(Key.temperatureUnitPreference),
           let rawValue = sync.string(forKey: Key.temperatureUnitPreference),
           let remoteValue = TemperatureUnitPreference(rawValue: rawValue) {
            temperatureUnitPreference = remoteValue
        }

        if changedKeys.contains(Key.showAdvancedValues),
           let remoteValue = sync.bool(forKey: Key.showAdvancedValues) {
            showAdvancedValues = remoteValue
        }

        if changedKeys.contains(Key.refreshCadencePreference),
           let rawValue = sync.string(forKey: Key.refreshCadencePreference),
           let remoteValue = RefreshCadencePreference(rawValue: rawValue) {
            refreshCadencePreference = remoteValue
        }

        if changedKeys.contains(Key.energyChangeSensitivity),
           let rawValue = sync.string(forKey: Key.energyChangeSensitivity),
           let remoteValue = EnergyChangeSensitivity(rawValue: rawValue) {
            energyChangeSensitivity = remoteValue
        }

        if changedKeys.contains(Key.isLowBatteryAlertEnabled),
           let remoteValue = sync.bool(forKey: Key.isLowBatteryAlertEnabled) {
            isLowBatteryAlertEnabled = remoteValue
        }

        if changedKeys.contains(Key.isChargeCompleteAlertEnabled),
           let remoteValue = sync.bool(forKey: Key.isChargeCompleteAlertEnabled) {
            isChargeCompleteAlertEnabled = remoteValue
        }

        if changedKeys.contains(Key.isHighTemperatureAlertEnabled),
           let remoteValue = sync.bool(forKey: Key.isHighTemperatureAlertEnabled) {
            isHighTemperatureAlertEnabled = remoteValue
        }

        if changedKeys.contains(Key.isHistoryEnabled),
           let remoteValue = sync.bool(forKey: Key.isHistoryEnabled) {
            isHistoryEnabled = remoteValue
        }

        if changedKeys.contains(Key.isHistoryICloudSyncEnabled),
           let remoteValue = sync.bool(forKey: Key.isHistoryICloudSyncEnabled) {
            isHistoryICloudSyncEnabled = remoteValue
        }
    }

    private func persist(_ value: Bool, forKey key: String, syncToCloud: Bool) {
        defaults.set(value, forKey: key)

        guard syncToCloud, isApplyingRemoteChanges == false else {
            return
        }

        sync.set(value, forKey: key)
    }

    private func persist(_ value: String, forKey key: String, syncToCloud: Bool) {
        defaults.set(value, forKey: key)

        guard syncToCloud, isApplyingRemoteChanges == false else {
            return
        }

        sync.set(value, forKey: key)
    }
}
