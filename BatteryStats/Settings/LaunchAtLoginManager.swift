import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        switch service.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    var statusDescription: String {
        switch service.status {
        case .notRegistered:
            return "Off. This Mac will not reopen BatteryStats when you sign in."
        case .enabled:
            return "BatteryStats will launch after you sign in."
        case .requiresApproval:
            return "Approval is required in System Settings to finish enabling launch at login."
        case .notFound:
            return "Launch at login is unavailable in unsigned builds."
        @unknown default:
            return "Launch at login status is currently unavailable."
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
