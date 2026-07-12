import Foundation

@MainActor
protocol PreferencesSyncing: AnyObject {
    var isEnabled: Bool { get }
    var isAvailable: Bool { get }
    var availabilityDescription: String { get }

    func setEnabled(_ enabled: Bool)
    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol
    func removeObserver(_ token: NSObjectProtocol)
    func object(forKey key: String) -> Any?
    func set(_ value: Bool, forKey key: String)
    func set(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
    func flush()
}

@MainActor
protocol ICloudPreferencesKeyValueStoring: AnyObject {
    func object(forKey aKey: String) -> Any?
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

        guard isEnabled else {
            cancelScheduledSynchronize()
            return
        }

        _ = resolveStore()?.synchronize()
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

    func object(forKey key: String) -> Any? {
        enabledStore()?.object(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        setIfChanged(value, forKey: key) { Self.strictBool($0.object(forKey: key)) }
    }

    func set(_ value: String, forKey key: String) {
        setIfChanged(value, forKey: key) { $0.object(forKey: key) as? String }
    }

    func removeValue(forKey key: String) {
        guard let store = enabledStore(),
              store.object(forKey: key) != nil else {
            return
        }

        store.removeObject(forKey: key)
        scheduleSynchronize()
    }

    func flush() {
        cancelScheduledSynchronize()
        _ = enabledStore()?.synchronize()
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

    private func setIfChanged<Value: Equatable>(
        _ value: Value,
        forKey key: String,
        currentValue: (any ICloudPreferencesKeyValueStoring) -> Value?
    ) {
        guard let store = enabledStore(),
              currentValue(store) != value else {
            return
        }

        store.set(value as Any, forKey: key)
        scheduleSynchronize()
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
