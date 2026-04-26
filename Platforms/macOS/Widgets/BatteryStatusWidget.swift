import SwiftUI
import WidgetKit

struct BatteryStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: BatterySnapshot?

    static let placeholder = BatteryStatusEntry(date: .now, snapshot: .previewDischarging)
}

struct BatteryStatusProvider: TimelineProvider {
    private let service = BatteryReadingService()

    func placeholder(in context: Context) -> BatteryStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryStatusEntry) -> Void) {
        completion(makeEntry(at: .now, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryStatusEntry>) -> Void) {
        let entry = makeEntry(at: .now, isPreview: context.isPreview)
        // Widgets refresh on a coarse schedule, so ask for a modest cadence.
        let nextRefreshDate = entry.date.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextRefreshDate)))
    }

    private func makeEntry(at date: Date, isPreview: Bool) -> BatteryStatusEntry {
        if isPreview {
            return .placeholder
        }

        return BatteryStatusEntry(date: date, snapshot: service.read(at: date).snapshot)
    }
}

struct BatteryStatusWidget: Widget {
    private let kind = "BatteryStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryStatusProvider()) { entry in
            BatteryStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Battery Circles")
        .description("See battery health, charge, time remaining, and power state at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
