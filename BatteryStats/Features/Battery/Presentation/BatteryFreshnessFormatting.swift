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
        guard now.timeIntervalSince(lastUpdated) <= BatterySnapshotFreshnessPolicy.maximumLiveAge else {
            return "Stale - Updated \(relativeText)"
        }

        return "Live - Updated \(relativeText)"
    }

    static func hasUsableUpdate(lastUpdated: Date?, now: Date) -> Bool {
        lastUpdated.map { BatterySnapshotFreshnessPolicy.isLive(updatedAt: $0, now: now) } ?? false
    }

    static func nextStatusChangeDate(lastUpdated: Date?, now: Date, isRefreshing: Bool) -> Date {
        guard isRefreshing == false,
              let lastUpdated else {
            return now.addingTimeInterval(60)
        }

        return BatterySnapshotFreshnessPolicy.nextStatusChangeDate(updatedAt: lastUpdated, now: now)
    }
}
