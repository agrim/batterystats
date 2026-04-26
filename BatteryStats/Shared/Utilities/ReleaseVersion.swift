import Foundation

struct ReleaseVersion: Equatable {
    let marketingVersion: String
    let buildNumber: String

    var displayText: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }

    static func from(_ infoDictionary: [String: Any]?) -> ReleaseVersion? {
        guard
            let marketingVersion = infoDictionary?["CFBundleShortVersionString"] as? String,
            let buildNumber = infoDictionary?["CFBundleVersion"] as? String,
            marketingVersion.isEmpty == false,
            buildNumber.isEmpty == false
        else {
            return nil
        }

        return ReleaseVersion(marketingVersion: marketingVersion, buildNumber: buildNumber)
    }
}
