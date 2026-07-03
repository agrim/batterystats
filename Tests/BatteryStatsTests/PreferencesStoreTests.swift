import XCTest
@testable import BatteryStats

@MainActor
final class PreferencesStoreTests: XCTestCase {
    func testRemotePreferenceRemovalFallsBackToDefaultMenuBarDisplayMode() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.menuBarDisplayMode = .iconAndPower

        sync.removeRemoteValue(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.sendChange(keys: [PreferencesStore.menuBarDisplayModeDefaultsKey])
        await Task.yield()

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey),
            MenuBarDisplayMode.iconAndPercentage.rawValue
        )
        XCTAssertNil(sync.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey))
    }

    func testUnknownRemoteChangeAppliesPresentRemoteValuesWithoutResettingMissingPreferences() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.menuBarDisplayMode = .iconAndPower
        store.temperatureUnitPreference = .fahrenheit

        sync.set(TemperatureUnitPreference.celsius.rawValue, forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey)
        sync.removeRemoteValue(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.sendChange(keys: [])
        await Task.yield()

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPower)
        XCTAssertEqual(store.temperatureUnitPreference, .celsius)
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey),
            MenuBarDisplayMode.iconAndPower.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey),
            TemperatureUnitPreference.celsius.rawValue
        )
    }

    func testUnknownRemoteChangeDefaultsMalformedPresentPreferencesWithoutResettingMissingPreferences() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.menuBarDisplayMode = .iconAndPower
        store.temperatureUnitPreference = .fahrenheit
        store.showAdvancedValues = true
        store.refreshCadencePreference = .fiveMinutes

        let invalidation = expectation(description: "malformed display preferences invalidate the menu bar")
        invalidation.expectedFulfillmentCount = 2
        invalidation.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .menuBarDisplayPreferencesDidChange,
            object: store,
            queue: nil
        ) { _ in
            invalidation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        sync.setRawValue("not-a-mode", forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.setRawValue("kelvin", forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey)
        sync.setRawValue(NSNumber(value: 1), forKey: "showAdvancedValues")
        sync.removeRemoteValue(forKey: "refreshCadencePreference")

        sync.sendChange(keys: [])
        await Task.yield()

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(store.temperatureUnitPreference, .system)
        XCTAssertFalse(store.showAdvancedValues)
        XCTAssertEqual(store.refreshCadencePreference, .fiveMinutes)
        await fulfillment(of: [invalidation], timeout: 1)
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey),
            MenuBarDisplayMode.iconAndPercentage.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey),
            TemperatureUnitPreference.system.rawValue
        )
        XCTAssertFalse(defaults.bool(forKey: "showAdvancedValues"))
        XCTAssertEqual(defaults.string(forKey: "refreshCadencePreference"), RefreshCadencePreference.fiveMinutes.rawValue)
        XCTAssertEqual(sync.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey), MenuBarDisplayMode.iconAndPercentage.rawValue)
        XCTAssertEqual(sync.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey), TemperatureUnitPreference.system.rawValue)
        XCTAssertEqual(sync.bool(forKey: "showAdvancedValues"), false)
        XCTAssertNil(sync.string(forKey: "refreshCadencePreference"))
    }

    func testEnablingICloudSyncPreservesLocalPreferencesWhenRemoteStoreIsEmpty() {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.menuBarDisplayMode = .iconAndPower
        store.temperatureUnitPreference = .fahrenheit

        store.isICloudSyncEnabled = true

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPower)
        XCTAssertEqual(store.temperatureUnitPreference, .fahrenheit)
        XCTAssertEqual(sync.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey), MenuBarDisplayMode.iconAndPower.rawValue)
        XCTAssertEqual(sync.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey), TemperatureUnitPreference.fahrenheit.rawValue)
        XCTAssertEqual(sync.flushCallCount, 1)
    }

    func testResetClearsSyncedPreferenceValuesBeforeDisablingICloudSync() {
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: makeDefaults(), sync: sync)
        store.isICloudSyncEnabled = true
        store.menuBarDisplayMode = .iconAndPower
        store.temperatureUnitPreference = .fahrenheit

        store.reset()

        XCTAssertFalse(store.isICloudSyncEnabled)
        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(store.temperatureUnitPreference, .system)
        XCTAssertTrue(sync.removedKeys.contains(PreferencesStore.menuBarDisplayModeDefaultsKey))
        XCTAssertTrue(sync.removedKeys.contains(PreferencesStore.temperatureUnitPreferenceDefaultsKey))
        XCTAssertNil(sync.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey))
        XCTAssertNil(sync.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey))
    }

    func testResetLeavesDefaultValuesAvailableForLiveDefaultsObservers() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults, sync: FakePreferencesSync())
        store.menuBarDisplayMode = .iconAndPower
        store.temperatureUnitPreference = .fahrenheit
        store.refreshCadencePreference = .fiveMinutes
        store.energyChangeSensitivity = .subtle
        store.showAdvancedValues = true

        store.reset()

        XCTAssertEqual(defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey), MenuBarDisplayMode.iconAndPercentage.rawValue)
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey), TemperatureUnitPreference.system.rawValue)
        XCTAssertEqual(defaults.string(forKey: "refreshCadencePreference"), RefreshCadencePreference.dynamic.rawValue)
        XCTAssertEqual(defaults.string(forKey: "energyChangeSensitivity"), EnergyChangeSensitivity.balanced.rawValue)
        XCTAssertFalse(defaults.bool(forKey: "showAdvancedValues"))
    }

    func testDisplayPreferenceChangesPostMenuBarInvalidation() {
        let store = PreferencesStore(defaults: makeDefaults(), sync: FakePreferencesSync())
        let invalidation = expectation(description: "display preferences invalidate the menu bar")
        invalidation.expectedFulfillmentCount = 2
        invalidation.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .menuBarDisplayPreferencesDidChange,
            object: store,
            queue: nil
        ) { _ in
            invalidation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.showAdvancedValues = true
        store.menuBarDisplayMode = .iconOnly
        store.menuBarDisplayMode = .iconOnly
        store.temperatureUnitPreference = .fahrenheit

        wait(for: [invalidation], timeout: 1)
    }

    func testSystemLocaleChangeInvalidatesResolvedSystemTemperatureDisplays() async {
        let store = PreferencesStore(defaults: makeDefaults(), sync: FakePreferencesSync())
        let payloads = MenuBarDisplayPreferencesRecorder()
        let invalidation = expectation(description: "system unit locale change invalidates resolved temperature displays")
        invalidation.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .menuBarDisplayPreferencesDidChange,
            object: store,
            queue: nil
        ) { notification in
            if let preferences = MenuBarDisplayPreferences(notification: notification) {
                payloads.append(preferences)
            }
            invalidation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        XCTAssertEqual(store.temperatureUnitPreference, .system)
        XCTAssertEqual(store.temperatureUnitResolutionToken, 0)

        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        await fulfillment(of: [invalidation], timeout: 1)
        XCTAssertEqual(store.temperatureUnitResolutionToken, 1)
        XCTAssertEqual(payloads.values, [
            MenuBarDisplayPreferences(displayMode: .iconAndPercentage, temperatureUnitPreference: .system)
        ])
    }

    func testExplicitTemperatureUnitIgnoresSystemLocaleChange() async {
        let store = PreferencesStore(defaults: makeDefaults(), sync: FakePreferencesSync())
        store.temperatureUnitPreference = .fahrenheit
        let initialResolutionToken = store.temperatureUnitResolutionToken
        let invalidation = expectation(description: "explicit temperature units do not invalidate on locale changes")
        invalidation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .menuBarDisplayPreferencesDidChange,
            object: store,
            queue: nil
        ) { _ in
            invalidation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        await fulfillment(of: [invalidation], timeout: 0.1)
        XCTAssertEqual(store.temperatureUnitResolutionToken, initialResolutionToken)
    }

    func testDisplayPreferenceInvalidationIncludesCurrentDisplayPayload() {
        let store = PreferencesStore(defaults: makeDefaults(), sync: FakePreferencesSync())
        let payloads = MenuBarDisplayPreferencesRecorder()
        let invalidation = expectation(description: "display preferences include current payload")
        invalidation.expectedFulfillmentCount = 2
        invalidation.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .menuBarDisplayPreferencesDidChange,
            object: store,
            queue: nil
        ) { notification in
            if let preferences = MenuBarDisplayPreferences(notification: notification) {
                payloads.append(preferences)
            }
            invalidation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.menuBarDisplayMode = .iconOnly
        store.temperatureUnitPreference = .fahrenheit

        wait(for: [invalidation], timeout: 1)
        XCTAssertEqual(payloads.values, [
            MenuBarDisplayPreferences(displayMode: .iconOnly, temperatureUnitPreference: .system),
            MenuBarDisplayPreferences(displayMode: .iconOnly, temperatureUnitPreference: .fahrenheit)
        ])
    }

    func testMonitoringDemandOnlyKeepsBackgroundEnergyAwarenessForFastChangingSurfaces() {
        let store = PreferencesStore(defaults: makeDefaults(), sync: FakePreferencesSync())

        store.menuBarDisplayMode = .iconOnly
        store.showAdvancedValues = false
        store.isHistoryEnabled = false
        store.isHighTemperatureAlertEnabled = false

        XCTAssertFalse(store.monitoringDemand.needsEnergyChangeAwareness)

        store.menuBarDisplayMode = .iconAndPercentage
        XCTAssertFalse(store.monitoringDemand.needsEnergyChangeAwareness)

        store.menuBarDisplayMode = .iconAndTimeRemaining
        XCTAssertTrue(store.monitoringDemand.needsEnergyChangeAwareness)

        store.menuBarDisplayMode = .iconAndTemperature
        XCTAssertTrue(store.monitoringDemand.needsEnergyChangeAwareness)

        store.menuBarDisplayMode = .iconAndPower
        XCTAssertTrue(store.monitoringDemand.needsEnergyChangeAwareness)

        store.menuBarDisplayMode = .iconOnly
        store.isHighTemperatureAlertEnabled = true
        XCTAssertTrue(store.monitoringDemand.needsEnergyChangeAwareness)

        store.isHighTemperatureAlertEnabled = false
        store.isHistoryEnabled = true
        XCTAssertTrue(store.monitoringDemand.needsEnergyChangeAwareness)
    }

    func testDisplayPreferencePayloadRefreshWinsOverStaleDefaults() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults, sync: FakePreferencesSync())
        defaults.set(MenuBarDisplayMode.iconAndPercentage.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        defaults.set(TemperatureUnitPreference.system.rawValue, forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey)

        let didChange = store.refreshMenuBarDisplayPreferences(from: MenuBarDisplayPreferences(
            displayMode: .iconAndPower,
            temperatureUnitPreference: .fahrenheit
        ))

        XCTAssertTrue(didChange)
        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPower)
        XCTAssertEqual(store.temperatureUnitPreference, .fahrenheit)
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey), MenuBarDisplayMode.iconAndPower.rawValue)
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey), TemperatureUnitPreference.fahrenheit.rawValue)
    }

    func testDisplayPreferencePayloadRefreshDoesNotEchoInvalidation() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults, sync: FakePreferencesSync())
        let invalidation = expectation(description: "payload refresh should not repost menu bar invalidation")
        invalidation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .menuBarDisplayPreferencesDidChange,
            object: store,
            queue: nil
        ) { _ in
            invalidation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let didChange = store.refreshMenuBarDisplayPreferences(from: MenuBarDisplayPreferences(
            displayMode: .iconOnly,
            temperatureUnitPreference: .fahrenheit
        ))

        wait(for: [invalidation], timeout: 0.1)
        XCTAssertTrue(didChange)
        XCTAssertEqual(store.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(store.temperatureUnitPreference, .fahrenheit)
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey), MenuBarDisplayMode.iconOnly.rawValue)
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey), TemperatureUnitPreference.fahrenheit.rawValue)
    }

    func testDisplayDefaultsChangeNotificationUpdatesLiveDisplayPreferences() async {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults, sync: FakePreferencesSync())

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(store.temperatureUnitPreference, .system)

        defaults.set(MenuBarDisplayMode.iconAndPower.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        defaults.set(TemperatureUnitPreference.fahrenheit.rawValue, forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPower)
        XCTAssertEqual(store.temperatureUnitPreference, .fahrenheit)
    }

    func testDefaultsChangeNotificationIgnoresUnrelatedDefaultsObject() async {
        let defaults = makeDefaults()
        let unrelatedDefaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults, sync: FakePreferencesSync())

        unrelatedDefaults.set(MenuBarDisplayMode.iconOnly.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: unrelatedDefaults)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPercentage)

        defaults.set(MenuBarDisplayMode.iconAndPower.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPower)
    }

    func testDefaultsChangeNotificationUpdatesLiveOperationalPreferences() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        sync.isAvailable = true

        XCTAssertFalse(store.showAdvancedValues)
        XCTAssertEqual(store.refreshCadencePreference, .dynamic)
        XCTAssertEqual(store.energyChangeSensitivity, .balanced)
        XCTAssertFalse(store.hasEnabledAlerts)
        XCTAssertFalse(store.historyPolicy.isEnabled)

        defaults.set(true, forKey: "showAdvancedValues")
        defaults.set(RefreshCadencePreference.fiveMinutes.rawValue, forKey: "refreshCadencePreference")
        defaults.set(EnergyChangeSensitivity.subtle.rawValue, forKey: "energyChangeSensitivity")
        defaults.set(true, forKey: "isLowBatteryAlertEnabled")
        defaults.set(true, forKey: "isHighTemperatureAlertEnabled")
        defaults.set(true, forKey: "isICloudSyncEnabled")
        defaults.set(true, forKey: "isHistoryEnabled")
        defaults.set(true, forKey: "isHistoryICloudSyncEnabled")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(store.showAdvancedValues)
        XCTAssertEqual(store.refreshCadencePreference, .fiveMinutes)
        XCTAssertEqual(store.energyChangeSensitivity, .subtle)
        XCTAssertTrue(store.isLowBatteryAlertEnabled)
        XCTAssertFalse(store.isChargeCompleteAlertEnabled)
        XCTAssertTrue(store.isHighTemperatureAlertEnabled)
        XCTAssertTrue(store.isICloudSyncEnabled)
        XCTAssertTrue(store.isHistoryEnabled)
        XCTAssertTrue(store.isHistoryICloudSyncEnabled)
        XCTAssertTrue(store.historyPolicy.isEnabled)
        XCTAssertTrue(store.historyPolicy.syncsToICloud)
    }

    func testUnavailableICloudSyncDoesNotRemainEnabled() {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        sync.isAvailable = false
        let store = PreferencesStore(defaults: defaults, sync: sync)

        store.isICloudSyncEnabled = true

        XCTAssertFalse(store.isICloudSyncEnabled)
        XCTAssertFalse(defaults.bool(forKey: "isICloudSyncEnabled"))
    }

    func testUnavailableHistoryICloudSyncFallsBackToOffOnLaunch() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "isHistoryICloudSyncEnabled")
        let sync = FakePreferencesSync()
        sync.isAvailable = false

        let store = PreferencesStore(defaults: defaults, sync: sync)

        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
    }

    func testDisablingHistoryAlsoDisablesHistoryICloudSync() {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.isHistoryEnabled = true
        store.isHistoryICloudSyncEnabled = true

        store.isHistoryEnabled = false

        XCTAssertFalse(store.isHistoryEnabled)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
        XCTAssertEqual(sync.bool(forKey: "isHistoryEnabled"), false)
        XCTAssertEqual(sync.bool(forKey: "isHistoryICloudSyncEnabled"), false)
    }

    func testHistoryICloudSyncCannotEnableWhenHistoryIsOff() {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true

        store.isHistoryICloudSyncEnabled = true

        XCTAssertFalse(store.isHistoryEnabled)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
        XCTAssertEqual(sync.bool(forKey: "isHistoryICloudSyncEnabled"), false)
    }

    func testHistoryICloudSyncCannotEnableWhenGlobalICloudSyncIsOff() {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isHistoryEnabled = true

        store.isHistoryICloudSyncEnabled = true

        XCTAssertTrue(store.isHistoryEnabled)
        XCTAssertFalse(store.isICloudSyncEnabled)
        XCTAssertFalse(store.canEnableHistoryICloudSync)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(store.historyPolicy.syncsToICloud)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
    }

    func testDisablingGlobalICloudSyncAlsoDisablesHistoryICloudSync() {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.isHistoryEnabled = true
        store.isHistoryICloudSyncEnabled = true

        XCTAssertTrue(store.canEnableHistoryICloudSync)
        XCTAssertTrue(store.historyPolicy.syncsToICloud)

        store.isICloudSyncEnabled = false

        XCTAssertFalse(store.isICloudSyncEnabled)
        XCTAssertFalse(store.canEnableHistoryICloudSync)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(store.historyPolicy.syncsToICloud)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
    }

    func testRefreshingUnavailableICloudSyncClearsDependentHistorySyncState() {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.isHistoryEnabled = true
        store.isHistoryICloudSyncEnabled = true

        XCTAssertTrue(store.isICloudSyncEnabled)
        XCTAssertTrue(store.isHistoryICloudSyncEnabled)
        XCTAssertTrue(defaults.bool(forKey: "isICloudSyncEnabled"))
        XCTAssertTrue(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))

        sync.isAvailable = false
        sync.availabilityDescription = "iCloud is unavailable for tests."
        store.refreshICloudSyncAvailability()

        XCTAssertFalse(store.isICloudSyncEnabled)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(store.canEnableHistoryICloudSync)
        XCTAssertFalse(store.historyPolicy.syncsToICloud)
        XCTAssertFalse(defaults.bool(forKey: "isICloudSyncEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
        XCTAssertEqual(store.syncStatusMessage, "iCloud is unavailable for tests.")
    }

    func testRefreshingICloudStatusDoesNotEnableSyncWhenUserPreferenceIsOff() {
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: makeDefaults(), sync: sync)

        sync.availabilityDescription = "Fresh availability text."
        store.refreshICloudSyncAvailability()

        XCTAssertFalse(store.isICloudSyncEnabled)
        XCTAssertFalse(sync.isEnabled)
        XCTAssertEqual(store.syncStatusMessage, "Fresh availability text.")
    }

    func testRefreshingICloudAvailabilityDoesNotOverwriteLocalDisplayPreferencesWithStaleRemoteValues() {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.menuBarDisplayMode = .iconAndPower
        store.temperatureUnitPreference = .fahrenheit

        sync.setRawValue(MenuBarDisplayMode.iconOnly.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.setRawValue(TemperatureUnitPreference.celsius.rawValue, forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey)

        store.refreshICloudSyncAvailability()

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPower)
        XCTAssertEqual(store.temperatureUnitPreference, .fahrenheit)
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey),
            MenuBarDisplayMode.iconAndPower.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey),
            TemperatureUnitPreference.fahrenheit.rawValue
        )
    }

    func testRemoteHistoryDisableAlsoClearsHistoryICloudSyncLocally() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.isHistoryEnabled = true
        store.isHistoryICloudSyncEnabled = true

        sync.set(false, forKey: "isHistoryEnabled")
        sync.sendChange(keys: ["isHistoryEnabled"])
        await Task.yield()

        XCTAssertFalse(store.isHistoryEnabled)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
        XCTAssertEqual(sync.bool(forKey: "isHistoryICloudSyncEnabled"), false)
    }

    func testRemoteMixedHistoryStateDoesNotLeaveHistoryICloudSyncEnabled() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.isHistoryEnabled = true
        store.isHistoryICloudSyncEnabled = true

        sync.set(false, forKey: "isHistoryEnabled")
        sync.set(true, forKey: "isHistoryICloudSyncEnabled")
        sync.sendChange(keys: ["isHistoryEnabled", "isHistoryICloudSyncEnabled"])
        await Task.yield()

        XCTAssertFalse(store.isHistoryEnabled)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
        XCTAssertFalse(store.historyPolicy.isEnabled)
        XCTAssertFalse(store.historyPolicy.syncsToICloud)
        XCTAssertEqual(sync.bool(forKey: "isHistoryICloudSyncEnabled"), false)
    }

    func testUnknownRemoteMixedHistoryStateDoesNotLeaveHistoryICloudSyncEnabled() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.isHistoryEnabled = true
        store.isHistoryICloudSyncEnabled = true

        sync.set(false, forKey: "isHistoryEnabled")
        sync.set(true, forKey: "isHistoryICloudSyncEnabled")
        sync.sendChange(keys: [])
        await Task.yield()

        XCTAssertFalse(store.isHistoryEnabled)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
        XCTAssertFalse(store.historyPolicy.isEnabled)
        XCTAssertFalse(store.historyPolicy.syncsToICloud)
        XCTAssertEqual(sync.bool(forKey: "isHistoryICloudSyncEnabled"), false)
    }

    func testOutOfOrderRemoteHistorySyncEnablesAfterHistoryPreferenceArrives() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true

        sync.set(true, forKey: "isHistoryICloudSyncEnabled")
        sync.sendChange(keys: ["isHistoryICloudSyncEnabled"])
        await Task.yield()

        XCTAssertFalse(store.isHistoryEnabled)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(store.historyPolicy.syncsToICloud)

        sync.set(true, forKey: "isHistoryEnabled")
        sync.sendChange(keys: ["isHistoryEnabled"])
        await Task.yield()

        XCTAssertTrue(store.isHistoryEnabled)
        XCTAssertTrue(store.isHistoryICloudSyncEnabled)
        XCTAssertTrue(store.historyPolicy.syncsToICloud)
        XCTAssertTrue(defaults.bool(forKey: "isHistoryEnabled"))
        XCTAssertTrue(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
    }

    func testMalformedOutOfOrderRemoteHistorySyncIsRepairedWhenHistoryPreferenceArrives() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true

        sync.setRawValue(NSNumber(value: 1), forKey: "isHistoryICloudSyncEnabled")
        sync.set(true, forKey: "isHistoryEnabled")
        sync.sendChange(keys: ["isHistoryEnabled"])
        await Task.yield()

        XCTAssertTrue(store.isHistoryEnabled)
        XCTAssertFalse(store.isHistoryICloudSyncEnabled)
        XCTAssertFalse(store.historyPolicy.syncsToICloud)
        XCTAssertEqual(sync.bool(forKey: "isHistoryICloudSyncEnabled"), false)
        XCTAssertFalse(defaults.bool(forKey: "isHistoryICloudSyncEnabled"))
    }

    func testInvalidStoredEnumPreferencesAreNormalizedOnLaunch() {
        let defaults = makeDefaults()
        defaults.set("not-a-mode", forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        defaults.set("kelvin", forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey)
        defaults.set("whenever", forKey: "refreshCadencePreference")
        defaults.set("extreme", forKey: "energyChangeSensitivity")

        let store = PreferencesStore(defaults: defaults, sync: FakePreferencesSync())

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(store.temperatureUnitPreference, .system)
        XCTAssertEqual(store.refreshCadencePreference, .dynamic)
        XCTAssertEqual(store.energyChangeSensitivity, .balanced)
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey), MenuBarDisplayMode.iconAndPercentage.rawValue)
        XCTAssertEqual(defaults.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey), TemperatureUnitPreference.system.rawValue)
        XCTAssertEqual(defaults.string(forKey: "refreshCadencePreference"), RefreshCadencePreference.dynamic.rawValue)
        XCTAssertEqual(defaults.string(forKey: "energyChangeSensitivity"), EnergyChangeSensitivity.balanced.rawValue)
    }

    func testInvalidStoredBooleanPreferencesAreNormalizedOnLaunch() throws {
        let defaults = makeDefaults()
        defaults.set(1, forKey: "showAdvancedValues")
        defaults.set(1, forKey: "isLowBatteryAlertEnabled")
        defaults.set(1, forKey: "isHistoryEnabled")
        defaults.set(1, forKey: "isICloudSyncEnabled")

        let store = PreferencesStore(defaults: defaults, sync: FakePreferencesSync())

        XCTAssertFalse(store.showAdvancedValues)
        XCTAssertFalse(store.isLowBatteryAlertEnabled)
        XCTAssertFalse(store.isHistoryEnabled)
        XCTAssertFalse(store.isICloudSyncEnabled)

        for key in ["showAdvancedValues", "isLowBatteryAlertEnabled", "isHistoryEnabled", "isICloudSyncEnabled"] {
            let normalizedValue = try XCTUnwrap(defaults.object(forKey: key) as? NSNumber)
            XCTAssertEqual(CFGetTypeID(normalizedValue), CFBooleanGetTypeID())
            XCTAssertFalse(normalizedValue.boolValue)
        }
    }

    func testCloudBooleanParserRejectsPlainNumericNSNumberValues() {
        XCTAssertEqual(ICloudPreferencesSync.strictBool(NSNumber(value: true)), true)
        XCTAssertEqual(ICloudPreferencesSync.strictBool(NSNumber(value: false)), false)
        XCTAssertNil(ICloudPreferencesSync.strictBool(NSNumber(value: 1)))
        XCTAssertNil(ICloudPreferencesSync.strictBool(NSNumber(value: 0)))
    }

    func testMalformedRemoteBooleanChangeFallsBackToDefaultDisabled() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.showAdvancedValues = true

        sync.setRawValue(NSNumber(value: 1), forKey: "showAdvancedValues")
        sync.sendChange(keys: ["showAdvancedValues"])
        await Task.yield()

        XCTAssertFalse(store.showAdvancedValues)
        XCTAssertFalse(defaults.bool(forKey: "showAdvancedValues"))
        XCTAssertEqual(sync.bool(forKey: "showAdvancedValues"), false)
    }

    func testMalformedRemoteEnumChangeRepairsCloudValue() async {
        let defaults = makeDefaults()
        let sync = FakePreferencesSync()
        let store = PreferencesStore(defaults: defaults, sync: sync)
        store.isICloudSyncEnabled = true
        store.menuBarDisplayMode = .iconAndPower

        sync.setRawValue("not-a-mode", forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.sendChange(keys: [PreferencesStore.menuBarDisplayModeDefaultsKey])
        await Task.yield()

        XCTAssertEqual(store.menuBarDisplayMode, .iconAndPercentage)
        XCTAssertEqual(
            defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey),
            MenuBarDisplayMode.iconAndPercentage.rawValue
        )
        XCTAssertEqual(
            sync.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey),
            MenuBarDisplayMode.iconAndPercentage.rawValue
        )
    }

    func testMissingEnumPreferencesAreNotWrittenOnLaunch() {
        let defaults = makeDefaults()

        _ = PreferencesStore(defaults: defaults, sync: FakePreferencesSync())

        XCTAssertNil(defaults.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey))
        XCTAssertNil(defaults.string(forKey: PreferencesStore.temperatureUnitPreferenceDefaultsKey))
        XCTAssertNil(defaults.string(forKey: "refreshCadencePreference"))
        XCTAssertNil(defaults.string(forKey: "energyChangeSensitivity"))
    }

    func testICloudSyncDoesNotCreateStoreUntilEnabledAndAvailable() {
        let availability = FakeICloudKeyValueStoreAvailability()
        availability.hasAccount = false
        availability.hasEntitlement = false
        let notificationCenter = NotificationCenter()
        var storeCreationCount = 0
        let sync = ICloudPreferencesSync(
            availability: availability,
            storeProvider: {
                storeCreationCount += 1
                return FakeICloudKeyValueStore()
            },
            notificationCenter: notificationCenter
        )

        XCTAssertFalse(sync.isAvailable)
        XCTAssertFalse(sync.isICloudAccountAvailable)
        XCTAssertEqual(
            sync.availabilityDescription,
            "iCloud sync requires an iCloud Key-Value Storage entitlement in the signed app."
        )

        sync.setEnabled(true)
        XCTAssertFalse(sync.isEnabled)
        XCTAssertFalse(sync.hasValue(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey))
        XCTAssertNil(sync.string(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey))
        XCTAssertNil(sync.bool(forKey: "showAdvancedValues"))
        sync.set(MenuBarDisplayMode.iconOnly.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.set(true, forKey: "showAdvancedValues")
        sync.removeValue(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.flush()

        let ignoredChange = expectation(description: "unavailable sync ignores store notifications")
        ignoredChange.isInverted = true
        let token = sync.observeChanges { _ in
            ignoredChange.fulfill()
        }
        defer {
            sync.removeObserver(token)
        }

        notificationCenter.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: FakeICloudKeyValueStore(),
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: [PreferencesStore.menuBarDisplayModeDefaultsKey]
            ]
        )

        wait(for: [ignoredChange], timeout: 0.1)
        XCTAssertEqual(storeCreationCount, 0)
    }

    func testICloudPreferenceObserverReceivesActiveStoreNotifications() {
        let availability = FakeICloudKeyValueStoreAvailability()
        let notificationCenter = NotificationCenter()
        let store = FakeICloudKeyValueStore()
        let sync = ICloudPreferencesSync(
            availability: availability,
            storeProvider: { store },
            notificationCenter: notificationCenter
        )
        sync.setEnabled(true)
        let menuBarDisplayModeKey = PreferencesStore.menuBarDisplayModeDefaultsKey
        let receivedChange = expectation(description: "active store change is observed")
        let token = sync.observeChanges { keys in
            XCTAssertEqual(keys, [menuBarDisplayModeKey])
            receivedChange.fulfill()
        }
        defer {
            sync.removeObserver(token)
        }

        notificationCenter.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: [PreferencesStore.menuBarDisplayModeDefaultsKey]
            ]
        )

        wait(for: [receivedChange], timeout: 1)
    }

    func testICloudPreferenceObserverIgnoresOtherStoreNotifications() {
        let availability = FakeICloudKeyValueStoreAvailability()
        let notificationCenter = NotificationCenter()
        let store = FakeICloudKeyValueStore()
        let sync = ICloudPreferencesSync(
            availability: availability,
            storeProvider: { store },
            notificationCenter: notificationCenter
        )
        sync.setEnabled(true)
        let unrelatedChange = expectation(description: "unrelated store change is ignored")
        unrelatedChange.isInverted = true
        let token = sync.observeChanges { _ in
            unrelatedChange.fulfill()
        }
        defer {
            sync.removeObserver(token)
        }

        notificationCenter.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSObject(),
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: [PreferencesStore.menuBarDisplayModeDefaultsKey]
            ]
        )

        wait(for: [unrelatedChange], timeout: 0.1)
    }

    func testICloudPreferenceSyncSkipsSameValueWritesAndMissingRemoves() {
        let availability = FakeICloudKeyValueStoreAvailability()
        let store = FakeICloudKeyValueStore()
        let sync = ICloudPreferencesSync(
            availability: availability,
            storeProvider: { store },
            notificationCenter: NotificationCenter()
        )
        store.setRawValue(MenuBarDisplayMode.iconOnly.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        store.setRawValue(NSNumber(value: true), forKey: "showAdvancedValues")
        sync.setEnabled(true)

        let setCallCountAfterEnabling = store.setCallCount
        let removeObjectCallCountAfterEnabling = store.removeObjectCallCount

        sync.set(MenuBarDisplayMode.iconOnly.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.set(true, forKey: "showAdvancedValues")
        sync.removeValue(forKey: "missingPreference")

        XCTAssertEqual(store.setCallCount, setCallCountAfterEnabling)
        XCTAssertEqual(store.removeObjectCallCount, removeObjectCallCountAfterEnabling)
    }

    func testICloudPreferenceSyncStillWritesChangedValuesAndExistingRemoves() {
        let availability = FakeICloudKeyValueStoreAvailability()
        let store = FakeICloudKeyValueStore()
        let sync = ICloudPreferencesSync(
            availability: availability,
            storeProvider: { store },
            notificationCenter: NotificationCenter()
        )
        store.setRawValue(MenuBarDisplayMode.iconOnly.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.setEnabled(true)

        sync.set(MenuBarDisplayMode.iconAndPower.rawValue, forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)
        sync.removeValue(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey)

        XCTAssertEqual(store.setCallCount, 1)
        XCTAssertEqual(store.removeObjectCallCount, 1)
        XCTAssertNil(store.object(forKey: PreferencesStore.menuBarDisplayModeDefaultsKey))
    }

    func testRemovesRemotePreferenceObserverOnDeinit() {
        let sync = FakePreferencesSync()

        do {
            let store = PreferencesStore(defaults: makeDefaults(), sync: sync)
            withExtendedLifetime(store) {}
        }

        XCTAssertEqual(sync.removeObserverCallCount, 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class MenuBarDisplayPreferencesRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [MenuBarDisplayPreferences] = []

    var values: [MenuBarDisplayPreferences] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }

    func append(_ value: MenuBarDisplayPreferences) {
        lock.lock()
        defer { lock.unlock() }
        recordedValues.append(value)
    }
}

@MainActor
private final class FakePreferencesSync: PreferencesSyncing {
    var isEnabled = false
    var isAvailable = true
    var availabilityDescription = "iCloud is available for tests."
    private(set) var removedKeys: [String] = []
    private(set) var removeObserverCallCount = 0
    private(set) var flushCallCount = 0

    private var values: [String: Any] = [:]
    private var changeHandler: (@Sendable ([String]) -> Void)?

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled && isAvailable
    }

    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol {
        changeHandler = handler
        return NSObject()
    }

    func removeObserver(_ token: NSObjectProtocol) {
        removeObserverCallCount += 1
    }

    func bool(forKey key: String) -> Bool? {
        ICloudPreferencesSync.strictBool(values[key])
    }

    func hasValue(forKey key: String) -> Bool {
        values[key] != nil
    }

    func string(forKey key: String) -> String? {
        values[key] as? String
    }

    func set(_ value: Bool, forKey key: String) {
        guard isEnabled else {
            return
        }

        values[key] = value
    }

    func set(_ value: String, forKey key: String) {
        guard isEnabled else {
            return
        }

        values[key] = value
    }

    func removeValue(forKey key: String) {
        guard isEnabled else {
            return
        }

        removeRemoteValue(forKey: key)
        removedKeys.append(key)
    }

    func flush() {
        flushCallCount += 1
    }

    func removeRemoteValue(forKey key: String) {
        values.removeValue(forKey: key)
    }

    func setRawValue(_ value: Any, forKey key: String) {
        values[key] = value
    }

    func sendChange(keys: [String]) {
        changeHandler?(keys)
    }
}

private final class FakeICloudKeyValueStoreAvailability: ICloudKeyValueStoreAvailabilityChecking {
    var hasAccount = true
    var hasEntitlement = true

    var isAvailable: Bool {
        hasAccount && hasEntitlement
    }
}

private final class FakeICloudKeyValueStore: ICloudPreferencesKeyValueStoring {
    private var values: [String: Any] = [:]
    private(set) var synchronizeCallCount = 0
    private(set) var setCallCount = 0
    private(set) var removeObjectCallCount = 0

    func object(forKey aKey: String) -> Any? {
        values[aKey]
    }

    func string(forKey aKey: String) -> String? {
        values[aKey] as? String
    }

    func set(_ value: Any?, forKey aKey: String) {
        setCallCount += 1
        values[aKey] = value
    }

    func removeObject(forKey aKey: String) {
        removeObjectCallCount += 1
        values.removeValue(forKey: aKey)
    }

    func synchronize() -> Bool {
        synchronizeCallCount += 1
        return true
    }

    func setRawValue(_ value: Any, forKey key: String) {
        values[key] = value
    }
}
