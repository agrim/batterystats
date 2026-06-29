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
                    snapshot: displaySnapshot,
                    updatedAt: entry.updatedAt,
                    now: entry.date,
                    healthTint: BatteryPresentationStyle.healthTint(for: displaySnapshot),
                    chargeTint: BatteryPresentationStyle.chargeTint(for: displaySnapshot),
                    timeTint: BatteryPresentationStyle.timeTint(for: displaySnapshot),
                    statusDescriptor: BatteryPresentationStyle.statusDescriptor(for: displaySnapshot)
                )
            default:
                GeometryReader { geometry in
                    let circleDiameter = floor(min(geometry.size.width * 0.392, geometry.size.height * 0.399))
                    let spacing = max(20, round(min(geometry.size.width, geometry.size.height) * 0.073))

                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            BatteryWidgetMetricTile(metric: healthMetric, size: circleDiameter)
                            BatteryWidgetMetricTile(metric: chargeMetric, size: circleDiameter)
                        }

                        HStack(spacing: spacing) {
                            BatteryWidgetMetricTile(metric: timeMetric, size: circleDiameter)
                            BatteryWidgetMetricTile(metric: statusMetric, size: circleDiameter)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .containerBackground(for: .widget) {
            BatteryWidgetBackground()
        }
    }

    private var healthMetric: BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .text(BatteryWidgetMetricFormatting.percentText(displaySnapshot?.presentationHealthPercent)),
            progress: BatteryWidgetMetricFormatting.clampedProgress(displaySnapshot?.presentationHealthPercent),
            ringTint: BatteryPresentationStyle.healthTint(for: displaySnapshot),
            contentTint: .primary
        )
    }

    private var chargeMetric: BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .text(BatteryWidgetMetricFormatting.percentText(displaySnapshot?.presentationStateOfChargePercent)),
            progress: BatteryWidgetMetricFormatting.clampedProgress(displaySnapshot?.presentationStateOfChargePercent),
            ringTint: BatteryPresentationStyle.chargeTint(for: displaySnapshot),
            contentTint: .primary
        )
    }

    private var timeMetric: BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .text(BatteryWidgetMetricFormatting.timeText(for: displaySnapshot)),
            progress: BatteryWidgetMetricFormatting.timeProgress(for: displaySnapshot),
            ringTint: BatteryPresentationStyle.timeTint(for: displaySnapshot),
            contentTint: .primary
        )
    }

    private var statusMetric: BatteryWidgetMetric {
        let descriptor = BatteryPresentationStyle.statusDescriptor(for: displaySnapshot)
        return BatteryWidgetMetric(
            content: .symbol(descriptor.symbolName),
            progress: BatteryWidgetMetricFormatting.statusProgress(for: displaySnapshot),
            ringTint: descriptor.ringTint,
            contentTint: descriptor.contentTint
        )
    }

    private var displaySnapshot: BatterySnapshot? {
        BatteryWidgetCompactDisplayPolicy.snapshotForMetrics(
            entry.snapshot,
            updatedAt: entry.updatedAt,
            now: entry.date
        )
    }
}
