@preconcurrency import Foundation
import Observation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly
    case iconAndPercentage
    case iconAndHealth
    case iconAndFullCharge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly:
            return "Icon Only"
        case .iconAndPercentage:
            return "Icon + Percentage"
        case .iconAndHealth:
            return "Icon + Health"
        case .iconAndFullCharge:
            return "Icon + Capacity"
        }
    }
}

enum ResolvedTemperatureUnit {
    case celsius
    case fahrenheit
}

enum TemperatureUnitPreference: String, CaseIterable, Identifiable {
    case system
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .celsius:
            return "Celsius"
        case .fahrenheit:
            return "Fahrenheit"
        }
    }

    var resolvedUnit: ResolvedTemperatureUnit {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.measurementSystem == .us ? .fahrenheit : .celsius
        case .celsius:
            return .celsius
        case .fahrenheit:
            return .fahrenheit
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
        isICloudSyncEnabled = false

        defaults.removeObject(forKey: Key.launchAtLoginEnabled)
        defaults.removeObject(forKey: Key.menuBarDisplayMode)
        defaults.removeObject(forKey: Key.temperatureUnitPreference)
        defaults.removeObject(forKey: Key.showAdvancedValues)
        defaults.removeObject(forKey: Key.isICloudSyncEnabled)
        syncStatusMessage = sync.availabilityDescription
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
    }

    private func pushLocalValues() {
        sync.set(menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode)
        sync.set(temperatureUnitPreference.rawValue, forKey: Key.temperatureUnitPreference)
        sync.set(showAdvancedValues, forKey: Key.showAdvancedValues)
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
