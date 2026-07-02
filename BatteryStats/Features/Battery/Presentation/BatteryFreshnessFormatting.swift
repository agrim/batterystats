import Foundation

enum BatteryFreshnessFormatting {
    static func statusText(lastUpdated: Date?, now: Date, isRefreshing: Bool) -> String {
        if isRefreshing {
            return "Refreshing..."
        }

        guard let lastUpdated else {
            return "Waiting for battery change"
        }

        guard BatterySnapshotFreshnessPolicy.isWithinFutureSkew(updatedAt: lastUpdated, now: now) else {
            return "Waiting for battery change"
        }

        let relativeText = BatterySnapshotFreshnessPolicy.relativeUpdateText(updatedAt: lastUpdated, now: now)
        guard hasUsableUpdate(lastUpdated: lastUpdated, now: now) else {
            return "Stale - Updated \(relativeText)"
        }

        return "Live - Updated \(relativeText)"
    }

    static func hasUsableUpdate(lastUpdated: Date?, now: Date) -> Bool {
        guard let lastUpdated else {
            return false
        }

        return BatterySnapshotFreshnessPolicy.isLive(updatedAt: lastUpdated, now: now)
    }

    static func nextStatusChangeDate(lastUpdated: Date?, now: Date, isRefreshing: Bool) -> Date {
        guard isRefreshing == false,
              let lastUpdated else {
            return now.addingTimeInterval(60)
        }

        let futureOffset = lastUpdated.timeIntervalSince(now)
        if futureOffset > BatterySnapshotFreshnessPolicy.allowableFutureSkew {
            return lastUpdated.addingTimeInterval(-BatterySnapshotFreshnessPolicy.allowableFutureSkew)
        }

        let nextRelativeDate = BatterySnapshotFreshnessPolicy.nextRelativeUpdateDate(updatedAt: lastUpdated, now: now)

        if hasUsableUpdate(lastUpdated: lastUpdated, now: now) {
            let staleDate = lastUpdated.addingTimeInterval(BatterySnapshotFreshnessPolicy.maximumLiveAge + 1)
            if staleDate > now {
                return min(nextRelativeDate, staleDate)
            }
        }

        return nextRelativeDate
    }
}
