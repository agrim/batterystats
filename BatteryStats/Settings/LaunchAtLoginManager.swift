import Foundation
import Observation
import ServiceManagement

@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    var isEnabled: Bool { get }
    var statusDescription: String { get }

    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class LaunchAtLoginManager: LaunchAtLoginManaging {
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

@MainActor
@Observable
final class LaunchAtLoginSettingsModel {
    private(set) var isEnabled: Bool
    private(set) var statusDescription: String
    private(set) var errorMessage: String?
    private(set) var isUpdating = false

    @ObservationIgnored private let manager: any LaunchAtLoginManaging

    init(manager: any LaunchAtLoginManaging = LaunchAtLoginManager()) {
        self.manager = manager
        isEnabled = manager.isEnabled
        statusDescription = manager.statusDescription
    }

    func refresh(clearsError: Bool = true) {
        isEnabled = manager.isEnabled
        statusDescription = manager.statusDescription
        if clearsError {
            errorMessage = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard manager.isEnabled != enabled else {
            refresh()
            return
        }

        isUpdating = true
        defer {
            refresh(clearsError: false)
            isUpdating = false
        }

        do {
            try manager.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disableForReset() {
        guard manager.isEnabled else {
            refresh()
            return
        }

        setEnabled(false)
    }
}
