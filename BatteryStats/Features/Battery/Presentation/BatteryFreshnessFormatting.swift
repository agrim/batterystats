import Foundation

enum BatteryFreshnessFormatting {
    static let allowableFutureSkew: TimeInterval = 60
    static let maximumLiveAge: TimeInterval = 10 * 60

    static func statusText(lastUpdated: Date?, now: Date, isRefreshing: Bool) -> String {
        if isRefreshing {
            return "Refreshing..."
        }

        guard let lastUpdated else {
            return "Waiting for battery change"
        }

        guard hasUsableUpdate(lastUpdated: lastUpdated, now: now) else {
            if lastUpdated.timeIntervalSince(now) > allowableFutureSkew {
                return "Waiting for battery change"
            }

            return "Stale - Updated \(relativeUpdateText(lastUpdated: lastUpdated, now: now))"
        }

        return "Live - Updated \(relativeUpdateText(lastUpdated: lastUpdated, now: now))"
    }

    private static func relativeUpdateText(lastUpdated: Date, now: Date) -> String {
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(lastUpdated).rounded(.down)))
        if elapsedSeconds < 60 {
            return "just now"
        }

        let elapsedMinutes = elapsedSeconds / 60
        if elapsedMinutes < 60 {
            return "\(elapsedMinutes)m ago"
        }

        let elapsedHours = elapsedMinutes / 60
        if elapsedHours < 24 {
            return "\(elapsedHours)h ago"
        }

        let elapsedDays = elapsedHours / 24
        return "\(elapsedDays)d ago"
    }

    static func hasUsableUpdate(lastUpdated: Date?, now: Date) -> Bool {
        guard let lastUpdated else {
            return false
        }

        return lastUpdated.timeIntervalSince(now) <= allowableFutureSkew
            && now.timeIntervalSince(lastUpdated) <= maximumLiveAge
    }

    static func nextStatusChangeDate(lastUpdated: Date?, now: Date, isRefreshing: Bool) -> Date {
        guard isRefreshing == false,
              let lastUpdated else {
            return now.addingTimeInterval(60)
        }

        let futureOffset = lastUpdated.timeIntervalSince(now)
        if futureOffset > allowableFutureSkew {
            return lastUpdated.addingTimeInterval(-allowableFutureSkew)
        }

        let elapsedSeconds = max(0, now.timeIntervalSince(lastUpdated))
        let nextRelativeDate: Date
        if elapsedSeconds < 60 {
            nextRelativeDate = lastUpdated.addingTimeInterval(60)
        } else if elapsedSeconds < 60 * 60 {
            let elapsedMinute = floor(elapsedSeconds / 60)
            nextRelativeDate = lastUpdated.addingTimeInterval((elapsedMinute + 1) * 60)
        } else if elapsedSeconds < 24 * 60 * 60 {
            let elapsedHour = floor(elapsedSeconds / (60 * 60))
            nextRelativeDate = lastUpdated.addingTimeInterval((elapsedHour + 1) * 60 * 60)
        } else {
            let elapsedDay = floor(elapsedSeconds / (24 * 60 * 60))
            nextRelativeDate = lastUpdated.addingTimeInterval((elapsedDay + 1) * 24 * 60 * 60)
        }

        if hasUsableUpdate(lastUpdated: lastUpdated, now: now) {
            let staleDate = lastUpdated.addingTimeInterval(maximumLiveAge + 1)
            if staleDate > now {
                return min(nextRelativeDate, staleDate)
            }
        }

        return nextRelativeDate
    }
}
