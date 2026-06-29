import Foundation

struct ReleaseVersion: Equatable {
    let marketingVersion: String
    let buildNumber: String

    var displayText: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }

    static func from(_ infoDictionary: [String: Any]?) -> ReleaseVersion? {
        guard
            let rawMarketingVersion = metadataString(infoDictionary?["CFBundleShortVersionString"]),
            let rawBuildNumber = metadataString(infoDictionary?["CFBundleVersion"])
        else {
            return nil
        }

        let marketingVersion = rawMarketingVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = rawBuildNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            marketingVersion.isEmpty == false,
            buildNumber.isEmpty == false
        else {
            return nil
        }

        return ReleaseVersion(marketingVersion: marketingVersion, buildNumber: buildNumber)
    }

    private static func metadataString(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }

        return nil
    }
}
