import Foundation

struct ReleaseVersion {
    let marketingVersion: String
    let buildNumber: String

    var displayText: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }

    static func from(_ infoDictionary: [String: Any]?) -> ReleaseVersion? {
        guard
            let marketingVersion = metadataString(infoDictionary?["CFBundleShortVersionString"]),
            let buildNumber = metadataString(infoDictionary?["CFBundleVersion"])
        else {
            return nil
        }

        return ReleaseVersion(marketingVersion: marketingVersion, buildNumber: buildNumber)
    }

    private static func metadataString(_ value: Any?) -> String? {
        let rawString: String
        if let string = value as? String {
            rawString = string
        } else if let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() {
            rawString = number.stringValue
        } else {
            return nil
        }

        let trimmedString = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedString.isEmpty ? nil : trimmedString
    }
}
