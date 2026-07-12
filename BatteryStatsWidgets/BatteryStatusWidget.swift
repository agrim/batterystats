import SwiftUI
import WidgetKit

struct BatteryStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot?
    let snapshotIsDisplayable: Bool
    let displayedTimeMinutes: Int?

    static var placeholder: BatteryStatusEntry {
        let date = Date.now
        let snapshot = BatterySnapshot.previewDischarging
        return BatteryStatusEntry(
            date: date,
            snapshot: snapshot,
            snapshotIsDisplayable: true,
            displayedTimeMinutes: snapshot.displayedTimeMinutes
        )
    }
}

struct BatteryStatusProvider: TimelineProvider {
    private let snapshotStore: BatteryWidgetSnapshotStore = .shared

    func placeholder(in context: Context) -> BatteryStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryStatusEntry) -> Void) {
        guard context.isPreview == false else {
            completion(.placeholder)
            return
        }

        let now = Date.now
        let snapshot = storedSnapshot(at: now)
        let plan = BatteryWidgetTimelinePlan.make(snapshot: snapshot, now: now)
        let projection = plan.entries[0]
        completion(
            BatteryStatusEntry(
                date: now,
                snapshot: snapshot,
                snapshotIsDisplayable: projection.snapshotIsDisplayable,
                displayedTimeMinutes: projection.displayedTimeMinutes
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryStatusEntry>) -> Void) {
        guard context.isPreview == false else {
            completion(Timeline(entries: [.placeholder], policy: .never))
            return
        }

        let now = Date.now
        let snapshot = storedSnapshot(at: now)
        let plan = BatteryWidgetTimelinePlan.make(snapshot: snapshot, now: now)
        let entries = plan.entries.map { projection in
            BatteryStatusEntry(
                date: projection.date,
                snapshot: snapshot,
                snapshotIsDisplayable: projection.snapshotIsDisplayable,
                displayedTimeMinutes: projection.displayedTimeMinutes
            )
        }
        let reloadPolicy: TimelineReloadPolicy = plan.reloadAfter.map { .after($0) } ?? .never
        completion(Timeline(entries: entries, policy: reloadPolicy))
    }

    private func storedSnapshot(at date: Date) -> BatterySnapshot? {
        snapshotStore.snapshot(now: date, maximumAge: BatteryWidgetSnapshotStore.defaultRetentionAge)
    }
}

struct BatteryStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BatteryWidgetSnapshotStore.timelineKind, provider: BatteryStatusProvider()) { entry in
            BatteryStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Battery Circles")
        .description("See battery health, charge, time remaining, and power state at a glance.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
