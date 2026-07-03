import SwiftUI
import WidgetKit

struct BatteryStatusWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    let entry: BatteryStatusEntry

    var body: some View {
        let snapshot = displaySnapshot

        Group {
            switch widgetFamily {
            case .systemMedium:
                BatteryMediumWidgetView(
                    snapshot: snapshot,
                    updatedAt: entry.updatedAt,
                    now: entry.date,
                    healthTint: BatteryPresentationStyle.healthTintStyle(for: snapshot).color,
                    chargeTint: BatteryPresentationStyle.chargeTintStyle(for: snapshot).color,
                    timeTint: BatteryPresentationStyle.timeTintStyle(for: snapshot).color,
                    statusDescriptor: BatteryPresentationStyle.statusDescriptor(for: snapshot)
                )
            default:
                GeometryReader { geometry in
                    let circleDiameter = floor(min(geometry.size.width * 0.392, geometry.size.height * 0.399))
                    let spacing = max(20, round(min(geometry.size.width, geometry.size.height) * 0.073))

                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            BatteryWidgetMetricTile(metric: healthMetric(for: snapshot), size: circleDiameter)
                            BatteryWidgetMetricTile(metric: chargeMetric(for: snapshot), size: circleDiameter)
                        }

                        HStack(spacing: spacing) {
                            BatteryWidgetMetricTile(metric: timeMetric(for: snapshot), size: circleDiameter)
                            BatteryWidgetMetricTile(metric: statusMetric(for: snapshot), size: circleDiameter)
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

    private func healthMetric(for snapshot: BatterySnapshot?) -> BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .text(BatteryWidgetMetricFormatting.percentText(snapshot?.presentationHealthPercent)),
            progress: BatteryWidgetMetricFormatting.clampedProgress(snapshot?.presentationHealthPercent),
            ringTint: BatteryPresentationStyle.healthTintStyle(for: snapshot).color,
            contentTint: .primary
        )
    }

    private func chargeMetric(for snapshot: BatterySnapshot?) -> BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .text(BatteryWidgetMetricFormatting.percentText(snapshot?.presentationStateOfChargePercent)),
            progress: BatteryWidgetMetricFormatting.clampedProgress(snapshot?.presentationStateOfChargePercent),
            ringTint: BatteryPresentationStyle.chargeTintStyle(for: snapshot).color,
            contentTint: .primary
        )
    }

    private func timeMetric(for snapshot: BatterySnapshot?) -> BatteryWidgetMetric {
        BatteryWidgetMetric(
            content: .text(BatteryWidgetMetricFormatting.timeText(for: snapshot)),
            progress: BatteryWidgetMetricFormatting.timeProgress(for: snapshot),
            ringTint: BatteryPresentationStyle.timeTintStyle(for: snapshot).color,
            contentTint: .primary
        )
    }

    private func statusMetric(for snapshot: BatterySnapshot?) -> BatteryWidgetMetric {
        let descriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)
        return BatteryWidgetMetric(
            content: .symbol(descriptor.symbolName),
            progress: descriptor.progress,
            ringTint: descriptor.ringTint,
            contentTint: descriptor.contentTint
        )
    }

    private var displaySnapshot: BatterySnapshot? {
        guard let snapshot = entry.snapshot,
              let updatedAt = entry.updatedAt,
              BatterySnapshotFreshnessPolicy.isLive(updatedAt: updatedAt, now: entry.date) else {
            return nil
        }

        return snapshot
    }
}
