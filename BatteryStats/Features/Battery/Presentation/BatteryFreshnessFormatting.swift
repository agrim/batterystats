import Foundation

enum BatteryFreshnessFormatting {
    static func statusText(lastUpdated: Date?, now: Date, isRefreshing: Bool) -> String {
        if isRefreshing {
            return "Refreshing..."
        }

        guard let lastUpdated else {
            return "Waiting for battery change"
        }

        let elapsedSeconds = max(0, Int(now.timeIntervalSince(lastUpdated).rounded(.down)))
        if elapsedSeconds < 60 {
            return "Live - Updated just now"
        }

        let elapsedMinutes = elapsedSeconds / 60
        if elapsedMinutes < 60 {
            return "Live - Updated \(elapsedMinutes)m ago"
        }

        let elapsedHours = elapsedMinutes / 60
        if elapsedHours < 24 {
            return "Live - Updated \(elapsedHours)h ago"
        }

        let elapsedDays = elapsedHours / 24
        return "Live - Updated \(elapsedDays)d ago"
    }
}
