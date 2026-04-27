import Foundation

@MainActor
final class ICloudPreferencesSync {
    private lazy var store = NSUbiquitousKeyValueStore.default
    private(set) var isEnabled = false
    private var synchronizeTask: Task<Void, Never>?

    init() {}

    var isICloudAccountAvailable: Bool {
        ICloudKeyValueStoreAvailability.hasAccount
    }

    var availabilityDescription: String {
        guard ICloudKeyValueStoreAvailability.hasEntitlement else {
            return "iCloud sync requires an iCloud Key-Value Storage entitlement in the signed app."
        }

        if isICloudAccountAvailable {
            return "Uses your existing iCloud account when the app is signed with iCloud Key-Value Storage."
        }

        return "iCloud is not available on this Mac right now. BatteryStats will keep using local settings."
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled && ICloudKeyValueStoreAvailability.isAvailable
        guard isEnabled else {
            return
        }

        store.synchronize()
    }

    func observeChanges(_ handler: @escaping @Sendable ([String]) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            handler(keys)
        }
    }

    func removeObserver(_ token: NSObjectProtocol) {
        NotificationCenter.default.removeObserver(token)
    }

    func bool(forKey key: String) -> Bool? {
        guard isEnabled else {
            return nil
        }

        guard store.object(forKey: key) != nil else {
            return nil
        }

        return store.bool(forKey: key)
    }

    func string(forKey key: String) -> String? {
        guard isEnabled else {
            return nil
        }

        return store.string(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        guard isEnabled else {
            return
        }

        store.set(value, forKey: key)
        scheduleSynchronize()
    }

    func set(_ value: String, forKey key: String) {
        guard isEnabled else {
            return
        }

        store.set(value, forKey: key)
        scheduleSynchronize()
    }

    func flush() {
        synchronizeTask?.cancel()
        synchronizeTask = nil
        guard isEnabled else {
            return
        }

        store.synchronize()
    }

    private func scheduleSynchronize() {
        synchronizeTask?.cancel()
        synchronizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard Task.isCancelled == false else {
                return
            }

            self?.store.synchronize()
            self?.synchronizeTask = nil
        }
    }
}
