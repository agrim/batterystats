import Foundation

final class ICloudPreferencesSync {
    private lazy var store = NSUbiquitousKeyValueStore.default
    private(set) var isEnabled = false

    init() {}

    var isICloudAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var availabilityDescription: String {
        if isICloudAccountAvailable {
            return "Uses your existing iCloud account when the app is signed with iCloud Key-Value Storage."
        }

        return "iCloud is not available on this Mac right now. BatteryStats will keep using local settings."
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard enabled else {
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
        guard store.object(forKey: key) != nil else {
            return nil
        }

        return store.bool(forKey: key)
    }

    func string(forKey key: String) -> String? {
        store.string(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        guard isEnabled else {
            return
        }

        store.set(value, forKey: key)
        store.synchronize()
    }

    func set(_ value: String, forKey key: String) {
        guard isEnabled else {
            return
        }

        store.set(value, forKey: key)
        store.synchronize()
    }
}
