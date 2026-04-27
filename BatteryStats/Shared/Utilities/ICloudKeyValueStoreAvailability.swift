import Foundation
import Security

enum ICloudKeyValueStoreAvailability {
    static var isAvailable: Bool {
        hasAccount && hasEntitlement
    }

    static var hasAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    static var hasEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.ubiquity-kvstore-identifier" as CFString,
                nil
              ) else {
            return false
        }

        return CFGetTypeID(value) == CFStringGetTypeID()
    }
}
