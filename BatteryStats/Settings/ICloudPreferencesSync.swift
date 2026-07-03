import Foundation

@MainActor
protocol PreferencesSyncing: AnyObject {
    var isEnabled: Bool { get }
    var isAvailable: Bool { get }
    var availabilityDescription: String { get }

    func setEnabled(_ enabled: Bool)
    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol
    func removeObserver(_ token: NSObjectProtocol)
    func hasValue(forKey key: String) -> Bool
    func bool(forKey key: String) -> Bool?
    func string(forKey key: String) -> String?
    func set(_ value: Bool, forKey key: String)
    func set(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
    func flush()
}

@MainActor
protocol ICloudPreferencesKeyValueStoring: AnyObject {
    func object(forKey aKey: String) -> Any?
    func string(forKey aKey: String) -> String?
    func set(_ value: Any?, forKey aKey: String)
    func removeObject(forKey aKey: String)
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ICloudPreferencesKeyValueStoring {}

protocol ICloudKeyValueStoreAvailabilityChecking {
    var isAvailable: Bool { get }
    var hasAccount: Bool { get }
    var hasEntitlement: Bool { get }
}

struct SystemICloudKeyValueStoreAvailability: ICloudKeyValueStoreAvailabilityChecking {
    var isAvailable: Bool {
        ICloudKeyValueStoreAvailability.isAvailable
    }

    var hasAccount: Bool {
        ICloudKeyValueStoreAvailability.hasAccount
    }

    var hasEntitlement: Bool {
        ICloudKeyValueStoreAvailability.hasEntitlement
    }
}

@MainActor
final class ICloudPreferencesSync: PreferencesSyncing {
    private let availability: any ICloudKeyValueStoreAvailabilityChecking
    private let storeProvider: @MainActor () -> any ICloudPreferencesKeyValueStoring
    private let notificationCenter: NotificationCenter
    private var store: (any ICloudPreferencesKeyValueStoring)?
    private(set) var isEnabled = false
    private var synchronizeTask: Task<Void, Never>?

    init(
        availability: any ICloudKeyValueStoreAvailabilityChecking = SystemICloudKeyValueStoreAvailability(),
        storeProvider: @escaping @MainActor () -> any ICloudPreferencesKeyValueStoring = {
            NSUbiquitousKeyValueStore.default
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.availability = availability
        self.storeProvider = storeProvider
        self.notificationCenter = notificationCenter
    }

    var isAvailable: Bool {
        availability.isAvailable
    }

    var availabilityDescription: String {
        guard availability.hasEntitlement else {
            return "iCloud sync requires an iCloud Key-Value Storage entitlement in the signed app."
        }

        if availability.hasAccount {
            return "Uses your existing iCloud account when the app is signed with iCloud Key-Value Storage."
        }

        return "iCloud is not available on this Mac right now. BatteryStats will keep using local settings."
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled && isAvailable
        guard isEnabled,
              let store = resolveStore() else {
            cancelScheduledSynchronize()
            return
        }

        _ = store.synchronize()
    }

    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let changedStoreIdentifier = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated {
                guard let self,
                      let store = self.store,
                      let changedStoreIdentifier,
                      changedStoreIdentifier == ObjectIdentifier(store as AnyObject) else {
                    return
                }

                handler(keys)
            }
        }
    }

    func removeObserver(_ token: NSObjectProtocol) {
        notificationCenter.removeObserver(token)
    }

    func hasValue(forKey key: String) -> Bool {
        guard let store = enabledStore() else {
            return false
        }

        return store.object(forKey: key) != nil
    }

    func bool(forKey key: String) -> Bool? {
        guard let store = enabledStore() else {
            return nil
        }

        return Self.strictBool(store.object(forKey: key))
    }

    func string(forKey key: String) -> String? {
        guard let store = enabledStore() else {
            return nil
        }

        return store.string(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        guard let store = enabledStore() else {
            return
        }

        guard Self.strictBool(store.object(forKey: key)) != value else {
            return
        }

        store.set(value, forKey: key)
        scheduleSynchronize()
    }

    func set(_ value: String, forKey key: String) {
        guard let store = enabledStore() else {
            return
        }

        guard store.string(forKey: key) != value else {
            return
        }

        store.set(value, forKey: key)
        scheduleSynchronize()
    }

    func removeValue(forKey key: String) {
        guard let store = enabledStore() else {
            return
        }

        guard store.object(forKey: key) != nil else {
            return
        }

        store.removeObject(forKey: key)
        scheduleSynchronize()
    }

    func flush() {
        cancelScheduledSynchronize()
        guard let store = enabledStore() else {
            return
        }

        _ = store.synchronize()
    }

    private func scheduleSynchronize() {
        cancelScheduledSynchronize()
        synchronizeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: .milliseconds(750))
            guard Task.isCancelled == false,
                  isEnabled,
                  let store = resolveStore() else {
                return
            }

            _ = store.synchronize()
            synchronizeTask = nil
        }
    }

    private func cancelScheduledSynchronize() {
        synchronizeTask?.cancel()
        synchronizeTask = nil
    }

    static func strictBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }

        return number.boolValue
    }

    private func enabledStore() -> (any ICloudPreferencesKeyValueStoring)? {
        isEnabled ? resolveStore() : nil
    }

    private func resolveStore() -> (any ICloudPreferencesKeyValueStoring)? {
        guard isAvailable else {
            return nil
        }

        if store == nil {
            store = storeProvider()
        }

        return store
    }
}
