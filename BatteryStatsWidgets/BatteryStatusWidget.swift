import SwiftUI
import WidgetKit

struct BatteryStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot?

    var updatedAt: Date? {
        snapshot?.timestamp
    }

    static var placeholder: BatteryStatusEntry {
        BatteryStatusEntry(date: .now, snapshot: .previewDischarging)
    }
}

struct BatteryStatusProvider: TimelineProvider {
    private let snapshotStore: any BatteryWidgetSnapshotStoring = BatteryWidgetSnapshotStore.shared

    func placeholder(in context: Context) -> BatteryStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryStatusEntry) -> Void) {
        completion(makeEntry(at: .now, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryStatusEntry>) -> Void) {
        let entry = makeEntry(at: .now, isPreview: context.isPreview)
        let nextRefreshDate = BatteryWidgetUpdateFormatting.nextStatusChangeDate(
            updatedAt: entry.updatedAt,
            now: entry.date
        )
        completion(Timeline(entries: [entry], policy: .after(nextRefreshDate)))
    }

    private func makeEntry(at date: Date, isPreview: Bool) -> BatteryStatusEntry {
        if isPreview {
            return .placeholder
        }

        let snapshot = snapshotStore.snapshot(now: date, maximumAge: BatteryWidgetSnapshotStore.defaultRetentionAge)
        return BatteryStatusEntry(date: date, snapshot: snapshot)
    }
}

struct BatteryStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BatteryWidgetTimeline.kind, provider: BatteryStatusProvider()) { entry in
            BatteryStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Battery Circles")
        .description("See battery health, charge, time remaining, and power state at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
