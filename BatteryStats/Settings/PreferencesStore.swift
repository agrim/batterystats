@preconcurrency import Foundation
import Observation

extension Notification.Name {
    static let menuBarDisplayPreferencesDidChange = Notification.Name("PreferencesStore.menuBarDisplayPreferencesDidChange")
}

struct MenuBarDisplayPreferences: Equatable, Sendable {
    let displayMode: MenuBarDisplayMode
    let temperatureUnitPreference: TemperatureUnitPreference

    fileprivate enum UserInfoKey {
        static let displayMode = "menuBarDisplayMode"
        static let temperatureUnitPreference = "temperatureUnitPreference"
        static let sourceStoreIdentifier = "sourceStoreIdentifier"
        static let sourceDefaultsIdentifier = "sourceDefaultsIdentifier"
    }

    var userInfo: [AnyHashable: Any] {
        [
            UserInfoKey.displayMode: displayMode.rawValue,
            UserInfoKey.temperatureUnitPreference: temperatureUnitPreference.rawValue
        ]
    }

    init(
        displayMode: MenuBarDisplayMode,
        temperatureUnitPreference: TemperatureUnitPreference
    ) {
        self.displayMode = displayMode
        self.temperatureUnitPreference = temperatureUnitPreference
    }

    init?(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let displayModeRawValue = userInfo[UserInfoKey.displayMode] as? String,
              let temperatureUnitRawValue = userInfo[UserInfoKey.temperatureUnitPreference] as? String,
              let displayMode = MenuBarDisplayMode(rawValue: displayModeRawValue),
              let temperatureUnitPreference = TemperatureUnitPreference(rawValue: temperatureUnitRawValue) else {
            return nil
        }

        self.displayMode = displayMode
        self.temperatureUnitPreference = temperatureUnitPreference
    }
}

struct MenuBarDisplayPreferencesInvalidation: Sendable {
    let displayPreferences: MenuBarDisplayPreferences?
    let sourceStoreIdentifier: String?
    let sourceDefaultsIdentifier: String?

    init(notification: Notification) {
        let userInfo = notification.userInfo
        displayPreferences = MenuBarDisplayPreferences(notification: notification)
        sourceStoreIdentifier = userInfo?[MenuBarDisplayPreferences.UserInfoKey.sourceStoreIdentifier] as? String
        sourceDefaultsIdentifier = userInfo?[MenuBarDisplayPreferences.UserInfoKey.sourceDefaultsIdentifier] as? String
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
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

    var needsBackgroundEnergyChangeAwareness: Bool {
        switch self {
        case .iconAndTimeRemaining, .iconAndTemperature, .iconAndPower:
            return true
        case .iconOnly, .iconAndPercentage, .iconAndHealth, .iconAndFullCharge:
            return false
        }
    }
}

@MainActor
@Observable
final class PreferencesStore {
    static let menuBarDisplayModeDefaultsKey = Key.menuBarDisplayMode
    static let temperatureUnitPreferenceDefaultsKey = Key.temperatureUnitPreference

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
        static let defaultsNotificationIdentifier = "defaultsNotificationIdentifier"
    }

    private static let syncedPreferenceKeys = [
        Key.menuBarDisplayMode,
        Key.temperatureUnitPreference,
        Key.showAdvancedValues,
        Key.refreshCadencePreference,
        Key.energyChangeSensitivity,
        Key.isLowBatteryAlertEnabled,
        Key.isChargeCompleteAlertEnabled,
        Key.isHighTemperatureAlertEnabled,
        Key.isHistoryEnabled,
        Key.isHistoryICloudSyncEnabled
    ]

    var launchAtLoginEnabled: Bool {
        didSet { persist(launchAtLoginEnabled, forKey: Key.launchAtLoginEnabled, syncToCloud: false) }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            persist(menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode, syncToCloud: true)
            notifyMenuBarDisplayPreferencesDidChange(if: menuBarDisplayMode != oldValue)
        }
    }

    var temperatureUnitPreference: TemperatureUnitPreference {
        didSet {
            persist(temperatureUnitPreference.rawValue, forKey: Key.temperatureUnitPreference, syncToCloud: true)
            notifyMenuBarDisplayPreferencesDidChange(if: temperatureUnitPreference != oldValue)
        }
    }

    private(set) var temperatureUnitResolutionToken = 0

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
        didSet {
            persist(isHistoryEnabled, forKey: Key.isHistoryEnabled, syncToCloud: true)

            if isHistoryEnabled == false, isHistoryICloudSyncEnabled {
                clearHistoryICloudSyncEnabled(syncToCloud: true)
            }
        }
    }

    var isHistoryICloudSyncEnabled: Bool {
        didSet { persistHistoryICloudSyncEnabled() }
    }

    var isICloudSyncEnabled: Bool {
        didSet {
            applyICloudSyncPreference(isICloudSyncEnabled)
        }
    }

    var syncStatusMessage: String

    var isICloudSyncAvailable: Bool {
        sync.isAvailable
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sync: any PreferencesSyncing
    @ObservationIgnored private let defaultsNotificationIdentifier: String
    @ObservationIgnored private var observerToken: NSObjectProtocol?
    @ObservationIgnored private var defaultsObserverToken: NSObjectProtocol?
    @ObservationIgnored private var localeObserverToken: NSObjectProtocol?
    @ObservationIgnored private var isApplyingRemoteChanges = false
    @ObservationIgnored private var isApplyingMenuBarDisplayPreferenceNotification = false
    @ObservationIgnored private var isResolvingICloudSyncPreference = false
    @ObservationIgnored private var isResolvingHistoryICloudSyncPreference = false

    init(defaults: UserDefaults = .standard, sync: any PreferencesSyncing = ICloudPreferencesSync()) {
        self.defaults = defaults
        self.sync = sync
        defaultsNotificationIdentifier = Self.defaultsNotificationIdentifier(defaults)

        launchAtLoginEnabled = Self.boolPreference(defaults: defaults, key: Key.launchAtLoginEnabled, defaultValue: false)
        let initialMenuBarDisplayMode = Self.enumPreference(
            defaults: defaults,
            key: Key.menuBarDisplayMode,
            defaultValue: MenuBarDisplayMode.iconAndPercentage
        )
        menuBarDisplayMode = initialMenuBarDisplayMode
        temperatureUnitPreference = Self.enumPreference(
            defaults: defaults,
            key: Key.temperatureUnitPreference,
            defaultValue: TemperatureUnitPreference.system
        )
        showAdvancedValues = Self.boolPreference(defaults: defaults, key: Key.showAdvancedValues, defaultValue: false)
        refreshCadencePreference = Self.enumPreference(
            defaults: defaults,
            key: Key.refreshCadencePreference,
            defaultValue: RefreshCadencePreference.dynamic
        )
        energyChangeSensitivity = Self.enumPreference(
            defaults: defaults,
            key: Key.energyChangeSensitivity,
            defaultValue: EnergyChangeSensitivity.balanced
        )
        isLowBatteryAlertEnabled = Self.boolPreference(defaults: defaults, key: Key.isLowBatteryAlertEnabled, defaultValue: false)
        isChargeCompleteAlertEnabled = Self.boolPreference(defaults: defaults, key: Key.isChargeCompleteAlertEnabled, defaultValue: false)
        isHighTemperatureAlertEnabled = Self.boolPreference(defaults: defaults, key: Key.isHighTemperatureAlertEnabled, defaultValue: false)
        isHistoryEnabled = Self.boolPreference(defaults: defaults, key: Key.isHistoryEnabled, defaultValue: false)
        isHistoryICloudSyncEnabled = Self.boolPreference(defaults: defaults, key: Key.isHistoryICloudSyncEnabled, defaultValue: false)
        isICloudSyncEnabled = Self.boolPreference(defaults: defaults, key: Key.isICloudSyncEnabled, defaultValue: false)
        syncStatusMessage = sync.availabilityDescription

        applyICloudSyncPreference(isICloudSyncEnabled)
        resolveHistoryICloudSyncState()

        observerToken = sync.observeChanges { [weak self] changedKeys in
            Task { @MainActor in
                self?.applyRemoteChanges(for: changedKeys)
            }
        }

        defaultsObserverToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyDefaultsChanges()
            }
        }

        localeObserverToken = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleLocaleChange()
            }
        }
    }

    private static func enumPreference<Value>(
        defaults: UserDefaults,
        key: String,
        defaultValue: Value
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key) else {
            return defaultValue
        }

        guard let value = Value(rawValue: rawValue) else {
            defaults.set(defaultValue.rawValue, forKey: key)
            return defaultValue
        }

        return value
    }

    private static func boolPreference(defaults: UserDefaults, key: String, defaultValue: Bool) -> Bool {
        guard let rawValue = defaults.object(forKey: key) else {
            return defaultValue
        }

        guard let value = ICloudPreferencesSync.strictBool(rawValue) else {
            defaults.set(defaultValue, forKey: key)
            return defaultValue
        }

        return value
    }

    private static func defaultsNotificationIdentifier(_ defaults: UserDefaults) -> String {
        if let identifier = defaults.string(forKey: Key.defaultsNotificationIdentifier),
           identifier.isEmpty == false {
            return identifier
        }

        let identifier = UUID().uuidString
        defaults.set(identifier, forKey: Key.defaultsNotificationIdentifier)
        return identifier
    }

    isolated deinit {
        if let observerToken {
            sync.removeObserver(observerToken)
        }

        if let defaultsObserverToken {
            NotificationCenter.default.removeObserver(defaultsObserverToken)
        }

        if let localeObserverToken {
            NotificationCenter.default.removeObserver(localeObserverToken)
        }
    }

    func invalidateMenuBarDisplayPreferences() {
        var userInfo = menuBarDisplayPreferences.userInfo
        userInfo[MenuBarDisplayPreferences.UserInfoKey.sourceStoreIdentifier] = notificationIdentifier(for: self)
        userInfo[MenuBarDisplayPreferences.UserInfoKey.sourceDefaultsIdentifier] = defaultsNotificationIdentifier

        NotificationCenter.default.post(
            name: .menuBarDisplayPreferencesDidChange,
            object: self,
            userInfo: userInfo
        )
    }

    func shouldAcceptMenuBarDisplayPreferencesInvalidation(_ invalidation: MenuBarDisplayPreferencesInvalidation) -> Bool {
        guard invalidation.sourceStoreIdentifier != nil || invalidation.sourceDefaultsIdentifier != nil else {
            return true
        }

        if invalidation.sourceStoreIdentifier == notificationIdentifier(for: self) {
            return true
        }

        return invalidation.sourceDefaultsIdentifier == defaultsNotificationIdentifier
    }

    @discardableResult
    func refreshMenuBarDisplayPreferences(from nextPreferences: MenuBarDisplayPreferences?) -> Bool {
        guard let nextPreferences else {
            return applyMenuBarDisplayDefaultsChanges()
        }

        isApplyingMenuBarDisplayPreferenceNotification = true
        defer { isApplyingMenuBarDisplayPreferenceNotification = false }
        return applyMenuBarDisplayPreferences(nextPreferences)
    }

    func reset() {
        let shouldClearSyncedValues = sync.isEnabled

        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        if shouldClearSyncedValues {
            clearSyncedValues()
        }

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

        syncStatusMessage = sync.availabilityDescription
        invalidateMenuBarDisplayPreferences()
    }

    func refreshICloudSyncAvailability() {
        syncStatusMessage = sync.availabilityDescription

        guard isICloudSyncEnabled else {
            resolveHistoryICloudSyncState()
            return
        }

        let shouldMergeRemoteValues = sync.isEnabled == false

        if sync.isEnabled == false || sync.isAvailable == false {
            sync.setEnabled(true)
        }

        let resolvedValue = sync.isEnabled
        setResolvedICloudSyncEnabled(resolvedValue)

        if resolvedValue, shouldMergeRemoteValues {
            pullRemoteValues(defaultMissingValues: false)
            pushLocalValues()
            sync.flush()
        }

        resolveHistoryICloudSyncState()
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
            isHighTemperatureAlertEnabled: isHighTemperatureAlertEnabled,
            temperatureUnitPreference: temperatureUnitPreference
        )
    }

    var hasEnabledAlerts: Bool {
        alertPolicy.hasEnabledAlerts
    }

    func disableAllAlerts() {
        isLowBatteryAlertEnabled = false
        isChargeCompleteAlertEnabled = false
        isHighTemperatureAlertEnabled = false
    }

    var historyPolicy: BatteryHistoryPolicy {
        BatteryHistoryPolicy(
            isEnabled: isHistoryEnabled,
            syncsToICloud: isHistoryICloudSyncEnabled && canEnableHistoryICloudSync
        )
    }

    var canEnableHistoryICloudSync: Bool {
        isHistoryEnabled && isICloudSyncEnabled && sync.isEnabled && sync.isAvailable
    }

    var monitoringDemand: BatteryMonitoringDemand {
        BatteryMonitoringDemand(
            needsEnergyChangeAwareness: menuBarDisplayMode.needsBackgroundEnergyChangeAwareness
                || hasEnabledAlerts
                || isHistoryEnabled
        )
    }

    private var menuBarDisplayPreferences: MenuBarDisplayPreferences {
        MenuBarDisplayPreferences(
            displayMode: menuBarDisplayMode,
            temperatureUnitPreference: temperatureUnitPreference
        )
    }

    private func pullRemoteValues(defaultMissingValues: Bool) {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        applyRemotePreferences(defaultMissingValues: defaultMissingValues)
    }

    private func applyRemotePreferences(
        changedKeySet: Set<String>? = nil,
        defaultMissingValues: Bool
    ) {
        func shouldApply(_ key: String) -> Bool {
            changedKeySet?.contains(key) ?? true
        }

        if shouldApply(Key.menuBarDisplayMode) {
            applyRemoteEnumPreference(
                \.menuBarDisplayMode,
                forKey: Key.menuBarDisplayMode,
                defaultValue: MenuBarDisplayMode.iconAndPercentage,
                defaultMissing: defaultMissingValues
            )
        }

        if shouldApply(Key.temperatureUnitPreference) {
            applyRemoteEnumPreference(
                \.temperatureUnitPreference,
                forKey: Key.temperatureUnitPreference,
                defaultValue: TemperatureUnitPreference.system,
                defaultMissing: defaultMissingValues
            )
        }

        if shouldApply(Key.showAdvancedValues) {
            applyRemoteBoolPreference(\.showAdvancedValues, forKey: Key.showAdvancedValues, defaultMissing: defaultMissingValues)
        }

        if shouldApply(Key.refreshCadencePreference) {
            applyRemoteEnumPreference(
                \.refreshCadencePreference,
                forKey: Key.refreshCadencePreference,
                defaultValue: RefreshCadencePreference.dynamic,
                defaultMissing: defaultMissingValues
            )
        }

        if shouldApply(Key.energyChangeSensitivity) {
            applyRemoteEnumPreference(
                \.energyChangeSensitivity,
                forKey: Key.energyChangeSensitivity,
                defaultValue: EnergyChangeSensitivity.balanced,
                defaultMissing: defaultMissingValues
            )
        }

        if shouldApply(Key.isLowBatteryAlertEnabled) {
            applyRemoteBoolPreference(\.isLowBatteryAlertEnabled, forKey: Key.isLowBatteryAlertEnabled, defaultMissing: defaultMissingValues)
        }

        if shouldApply(Key.isChargeCompleteAlertEnabled) {
            applyRemoteBoolPreference(
                \.isChargeCompleteAlertEnabled,
                forKey: Key.isChargeCompleteAlertEnabled,
                defaultMissing: defaultMissingValues
            )
        }

        if shouldApply(Key.isHighTemperatureAlertEnabled) {
            applyRemoteBoolPreference(
                \.isHighTemperatureAlertEnabled,
                forKey: Key.isHighTemperatureAlertEnabled,
                defaultMissing: defaultMissingValues
            )
        }

        if shouldApply(Key.isHistoryEnabled) {
            applyRemoteBoolPreference(\.isHistoryEnabled, forKey: Key.isHistoryEnabled, defaultMissing: defaultMissingValues)
            if changedKeySet != nil, isHistoryEnabled {
                applyRemoteHistoryICloudSyncIfAvailable()
            }
        }

        if shouldApply(Key.isHistoryICloudSyncEnabled) {
            applyRemoteBoolPreference(
                \.isHistoryICloudSyncEnabled,
                forKey: Key.isHistoryICloudSyncEnabled,
                defaultMissing: defaultMissingValues
            )
        }
    }

    private func remoteEnumPreference<Value>(
        forKey key: String,
        defaultValue: Value,
        defaultMissing: Bool
    ) -> Value? where Value: RawRepresentable, Value.RawValue == String {
        let hasRemoteValue = sync.hasValue(forKey: key)
        guard let rawValue = sync.string(forKey: key) else {
            if hasRemoteValue {
                sync.set(defaultValue.rawValue, forKey: key)
                return defaultValue
            }

            return defaultMissing ? defaultValue : nil
        }

        guard let value = Value(rawValue: rawValue) else {
            sync.set(defaultValue.rawValue, forKey: key)
            return defaultValue
        }

        return value
    }

    private func remoteBoolPreference(
        forKey key: String,
        defaultValue: Bool,
        defaultMissing: Bool
    ) -> Bool? {
        let hasRemoteValue = sync.hasValue(forKey: key)
        if let value = sync.bool(forKey: key) {
            return value
        }

        if hasRemoteValue {
            sync.set(defaultValue, forKey: key)
            return defaultValue
        }

        return defaultMissing ? defaultValue : nil
    }

    private func applyRemoteEnumPreference<Value>(
        _ keyPath: ReferenceWritableKeyPath<PreferencesStore, Value>,
        forKey key: String,
        defaultValue: Value,
        defaultMissing: Bool
    ) where Value: RawRepresentable, Value.RawValue == String {
        guard let value = remoteEnumPreference(
            forKey: key,
            defaultValue: defaultValue,
            defaultMissing: defaultMissing
        ) else {
            return
        }

        self[keyPath: keyPath] = value
    }

    private func applyRemoteBoolPreference(
        _ keyPath: ReferenceWritableKeyPath<PreferencesStore, Bool>,
        forKey key: String,
        defaultMissing: Bool
    ) {
        guard let value = remoteBoolPreference(
            forKey: key,
            defaultValue: false,
            defaultMissing: defaultMissing
        ) else {
            return
        }

        self[keyPath: keyPath] = value
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
        sync.flush()
    }

    private func applyRemoteChanges(for changedKeys: [String]) {
        guard sync.isEnabled else {
            return
        }

        syncStatusMessage = sync.availabilityDescription

        guard changedKeys.isEmpty == false else {
            pullRemoteValues(defaultMissingValues: false)
            resolveHistoryICloudSyncState(syncToCloud: false)
            repairRemoteHistoryICloudSyncIfNeeded(afterApplyingRemoteKeys: changedKeys)
            return
        }

        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }
        let changedKeySet = Set(changedKeys)

        applyRemotePreferences(changedKeySet: changedKeySet, defaultMissingValues: true)

        resolveHistoryICloudSyncState()
        repairRemoteHistoryICloudSyncIfNeeded(afterApplyingRemoteKeys: changedKeys)
    }

    private func applyDefaultsChanges() {
        _ = applyMenuBarDisplayDefaultsChanges()

        applyDefaultBoolPreference(\.showAdvancedValues, forKey: Key.showAdvancedValues, defaultValue: false)
        applyDefaultEnumPreference(
            \.refreshCadencePreference,
            forKey: Key.refreshCadencePreference,
            defaultValue: RefreshCadencePreference.dynamic
        )
        applyDefaultEnumPreference(
            \.energyChangeSensitivity,
            forKey: Key.energyChangeSensitivity,
            defaultValue: EnergyChangeSensitivity.balanced
        )
        applyDefaultBoolPreference(\.isLowBatteryAlertEnabled, forKey: Key.isLowBatteryAlertEnabled, defaultValue: false)
        applyDefaultBoolPreference(
            \.isChargeCompleteAlertEnabled,
            forKey: Key.isChargeCompleteAlertEnabled,
            defaultValue: false
        )
        applyDefaultBoolPreference(
            \.isHighTemperatureAlertEnabled,
            forKey: Key.isHighTemperatureAlertEnabled,
            defaultValue: false
        )
        applyDefaultBoolPreference(\.isICloudSyncEnabled, forKey: Key.isICloudSyncEnabled, defaultValue: false)
        applyDefaultBoolPreference(\.isHistoryEnabled, forKey: Key.isHistoryEnabled, defaultValue: false)

        if applyDefaultBoolPreference(
            \.isHistoryICloudSyncEnabled,
            forKey: Key.isHistoryICloudSyncEnabled,
            defaultValue: false
        ) == false {
            resolveHistoryICloudSyncState()
        }
    }

    @discardableResult
    private func applyDefaultEnumPreference<Value>(
        _ keyPath: ReferenceWritableKeyPath<PreferencesStore, Value>,
        forKey key: String,
        defaultValue: Value
    ) -> Bool where Value: RawRepresentable & Equatable, Value.RawValue == String {
        setPreference(
            keyPath,
            to: Self.enumPreference(defaults: defaults, key: key, defaultValue: defaultValue)
        )
    }

    @discardableResult
    private func applyDefaultBoolPreference(
        _ keyPath: ReferenceWritableKeyPath<PreferencesStore, Bool>,
        forKey key: String,
        defaultValue: Bool
    ) -> Bool {
        setPreference(
            keyPath,
            to: Self.boolPreference(defaults: defaults, key: key, defaultValue: defaultValue)
        )
    }

    private func handleLocaleChange() {
        guard temperatureUnitPreference == .system else {
            return
        }

        temperatureUnitResolutionToken &+= 1
        invalidateMenuBarDisplayPreferences()
    }

    private func applyMenuBarDisplayDefaultsChanges() -> Bool {
        applyMenuBarDisplayPreferences(
            MenuBarDisplayPreferences(
                displayMode: Self.enumPreference(
                    defaults: defaults,
                    key: Key.menuBarDisplayMode,
                    defaultValue: MenuBarDisplayMode.iconAndPercentage
                ),
                temperatureUnitPreference: Self.enumPreference(
                    defaults: defaults,
                    key: Key.temperatureUnitPreference,
                    defaultValue: TemperatureUnitPreference.system
                )
            )
        )
    }

    private func applyMenuBarDisplayPreferences(_ nextPreferences: MenuBarDisplayPreferences) -> Bool {
        let didChangeDisplayMode = setPreference(\.menuBarDisplayMode, to: nextPreferences.displayMode)
        let didChangeTemperatureUnit = setPreference(
            \.temperatureUnitPreference,
            to: nextPreferences.temperatureUnitPreference
        )
        return didChangeDisplayMode || didChangeTemperatureUnit
    }

    @discardableResult
    private func setPreference<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<PreferencesStore, Value>,
        to nextValue: Value
    ) -> Bool {
        guard self[keyPath: keyPath] != nextValue else {
            return false
        }

        self[keyPath: keyPath] = nextValue
        return true
    }

    private func clearSyncedValues() {
        for key in Self.syncedPreferenceKeys {
            sync.removeValue(forKey: key)
        }

        sync.flush()
    }

    private func applyRemoteHistoryICloudSyncIfAvailable() {
        guard let remoteHistorySync = remoteBoolPreference(
            forKey: Key.isHistoryICloudSyncEnabled,
            defaultValue: false,
            defaultMissing: false
        ) else {
            return
        }

        isHistoryICloudSyncEnabled = remoteHistorySync
    }

    private func applyICloudSyncPreference(_ requestedValue: Bool) {
        guard isResolvingICloudSyncPreference == false else {
            defaults.set(isICloudSyncEnabled, forKey: Key.isICloudSyncEnabled)
            syncStatusMessage = sync.availabilityDescription
            return
        }

        sync.setEnabled(requestedValue)

        let resolvedValue = requestedValue && sync.isEnabled
        setResolvedICloudSyncEnabled(resolvedValue)

        if resolvedValue {
            pullRemoteValues(defaultMissingValues: false)
            pushLocalValues()
        } else {
            resolveHistoryICloudSyncState()
        }
    }

    private func setResolvedICloudSyncEnabled(_ resolvedValue: Bool) {
        if isICloudSyncEnabled != resolvedValue {
            isResolvingICloudSyncPreference = true
            isICloudSyncEnabled = resolvedValue
            isResolvingICloudSyncPreference = false
        }

        defaults.set(resolvedValue, forKey: Key.isICloudSyncEnabled)
        syncStatusMessage = sync.availabilityDescription
    }

    private func persistHistoryICloudSyncEnabled() {
        guard isResolvingHistoryICloudSyncPreference == false else {
            defaults.set(isHistoryICloudSyncEnabled, forKey: Key.isHistoryICloudSyncEnabled)
            return
        }

        if isHistoryICloudSyncEnabled,
           canEnableHistoryICloudSync == false {
            clearHistoryICloudSyncEnabled(syncToCloud: true)
            return
        }

        persist(isHistoryICloudSyncEnabled, forKey: Key.isHistoryICloudSyncEnabled, syncToCloud: true)
    }

    private func resolveHistoryICloudSyncState(syncToCloud: Bool = true) {
        guard isHistoryICloudSyncEnabled,
              canEnableHistoryICloudSync == false else {
            return
        }

        clearHistoryICloudSyncEnabled(syncToCloud: syncToCloud)
    }

    private func repairRemoteHistoryICloudSyncIfNeeded(afterApplyingRemoteKeys changedKeys: [String]) {
        guard sync.bool(forKey: Key.isHistoryICloudSyncEnabled) == true else {
            return
        }

        if changedKeys.contains(Key.isHistoryEnabled), isHistoryEnabled == false {
            sync.set(false, forKey: Key.isHistoryICloudSyncEnabled)
            return
        }

        if changedKeys.isEmpty,
           sync.bool(forKey: Key.isHistoryEnabled) == false {
            sync.set(false, forKey: Key.isHistoryICloudSyncEnabled)
        }
    }

    private func clearHistoryICloudSyncEnabled(syncToCloud: Bool) {
        isResolvingHistoryICloudSyncPreference = true
        isHistoryICloudSyncEnabled = false
        isResolvingHistoryICloudSyncPreference = false
        defaults.set(false, forKey: Key.isHistoryICloudSyncEnabled)

        guard syncToCloud, isApplyingRemoteChanges == false else {
            return
        }

        sync.set(false, forKey: Key.isHistoryICloudSyncEnabled)
        sync.flush()
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

    private func notifyMenuBarDisplayPreferencesDidChange(if shouldNotify: Bool) {
        guard shouldNotify,
              isApplyingMenuBarDisplayPreferenceNotification == false else {
            return
        }

        invalidateMenuBarDisplayPreferences()
    }

    private func notificationIdentifier(for object: AnyObject) -> String {
        String(describing: ObjectIdentifier(object))
    }
}
