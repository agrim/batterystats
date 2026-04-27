import SwiftUI
import WidgetKit

struct BatteryStatusWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    let entry: BatteryStatusEntry

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemMedium:
                BatteryMediumWidgetView(
                    snapshot: entry.snapshot,
                    healthTint: BatteryPresentationStyle.healthTint(for: entry.snapshot),
                    chargeTint: BatteryPresentationStyle.chargeTint(for: entry.snapshot),
                    timeTint: BatteryPresentationStyle.timeTint(for: entry.snapshot),
                    statusDescriptor: BatteryPresentationStyle.statusDescriptor(for: entry.snapshot)
                )
            default:
                GeometryReader { geometry in
                    let layout = BatteryWidgetLayout(size: geometry.size)

                    ZStack(alignment: .topLeading) {
                        BatteryWidgetMetricTile(metric: healthMetric, size: layout.circleDiameter)
                            .offset(x: layout.leadingInset, y: layout.topInset)

                        BatteryWidgetMetricTile(metric: chargeMetric, size: layout.circleDiameter)
                            .offset(x: layout.trailingColumnInset, y: layout.topInset)

                        BatteryWidgetMetricTile(metric: timeMetric, size: layout.circleDiameter)
                            .offset(x: layout.leadingInset, y: layout.bottomRowInset)

                        BatteryWidgetMetricTile(metric: statusMetric, size: layout.circleDiameter)
                            .offset(x: layout.trailingColumnInset, y: layout.bottomRowInset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .containerBackground(for: .widget) {
            BatteryWidgetBackground()
        }
    }

    private var healthMetric: BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .symbol("heart.fill"),
            progress: clampedProgress(entry.snapshot?.healthPercent) ?? 0.25,
            ringTint: BatteryPresentationStyle.healthTint(for: entry.snapshot),
            contentTint: .white
        )
    }

    private var chargeMetric: BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .symbol("bolt.fill"),
            progress: clampedProgress(entry.snapshot?.stateOfChargePercent) ?? 0.25,
            ringTint: BatteryPresentationStyle.chargeTint(for: entry.snapshot),
            contentTint: .white
        )
    }

    private var timeMetric: BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .text(timeText),
            progress: timeProgress,
            ringTint: BatteryPresentationStyle.timeTint(for: entry.snapshot),
            contentTint: .white
        )
    }

    private var statusMetric: BatteryWidgetMetric {
        let descriptor = BatteryPresentationStyle.statusDescriptor(for: entry.snapshot)
        return BatteryWidgetMetric(
            content: .symbol(descriptor.symbolName),
            progress: statusProgress,
            ringTint: descriptor.ringTint,
            contentTint: descriptor.contentTint
        )
    }

    private var timeText: String {
        guard let snapshot = entry.snapshot else {
            return "--"
        }

        if let displayedMinutes = snapshot.displayedTimeMinutes {
            return BatteryFormatting.compactWidgetDuration(minutes: displayedMinutes)
        }

        return "--"
    }

    private var timeProgress: Double {
        guard let snapshot = entry.snapshot else {
            return 0.25
        }

        if let displayedMinutes = snapshot.displayedTimeMinutes {
            let normalizedHours = Double(displayedMinutes) / (24 * 60)
            return max(0.15, min(1, normalizedHours))
        }

        switch snapshot.powerState {
        case .connectedNotCharging, .fullOnAC:
            return clampedProgress(snapshot.stateOfChargePercent) ?? 0.5
        case .charging:
            return clampedProgress(snapshot.stateOfChargePercent) ?? 0.7
        case .onBattery:
            return clampedProgress(snapshot.stateOfChargePercent) ?? 0.35
        case .unknown:
            return 0.25
        }
    }

    private var statusProgress: Double {
        guard entry.snapshot != nil else {
            return 0.25
        }

        return 1
    }

    private func clampedProgress(_ value: Double?) -> Double? {
        guard let value else {
            return nil
        }

        return max(0, min(100, value)) / 100
    }
}
