import Foundation

enum BatteryFreshnessFormatting {
    static func statusText(lastUpdated: Date?, now: Date, isRefreshing: Bool) -> String {
        if isRefreshing {
            return "Refreshing..."
        }

        guard let lastUpdated,
              BatterySnapshotFreshnessPolicy.isWithinFutureSkew(updatedAt: lastUpdated, now: now) else {
            return "Waiting for battery change"
        }

        let relativeText = BatterySnapshotFreshnessPolicy.relativeUpdateText(updatedAt: lastUpdated, now: now)
        let prefix = BatterySnapshotFreshnessPolicy.isLive(updatedAt: lastUpdated, now: now) ? "Live" : "Stale"
        return "\(prefix) - Updated \(relativeText)"
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
