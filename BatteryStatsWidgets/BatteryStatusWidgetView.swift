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
                    now: entry.date
                )
            default:
                GeometryReader { geometry in
                    let circleDiameter = floor(min(geometry.size.width * 0.392, geometry.size.height * 0.399))
                    let spacing = max(20, round(min(geometry.size.width, geometry.size.height) * 0.073))
                    let statusDescriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)
                    let healthMetric = BatteryWidgetMetric(
                        content: .text(BatteryWidgetMetricFormatting.percentText(snapshot?.presentationHealthPercent)),
                        progress: BatteryWidgetMetricFormatting.clampedProgress(snapshot?.presentationHealthPercent),
                        ringTint: BatteryPresentationStyle.healthTintStyle(for: snapshot).color
                    )
                    let chargeMetric = BatteryWidgetMetric(
                        content: .text(BatteryWidgetMetricFormatting.percentText(snapshot?.presentationStateOfChargePercent)),
                        progress: BatteryWidgetMetricFormatting.clampedProgress(snapshot?.presentationStateOfChargePercent),
                        ringTint: BatteryPresentationStyle.chargeTintStyle(for: snapshot).color
                    )
                    let timeMetric = BatteryWidgetMetric(
                        content: .text(BatteryWidgetMetricFormatting.timeText(for: snapshot)),
                        progress: BatteryWidgetMetricFormatting.timeProgress(for: snapshot),
                        ringTint: BatteryPresentationStyle.timeTintStyle(for: snapshot).color
                    )
                    let statusMetric = BatteryWidgetMetric(
                        content: .symbol(statusDescriptor.symbolName),
                        progress: statusDescriptor.progress,
                        ringTint: statusDescriptor.ringTint,
                        contentTint: statusDescriptor.contentTint
                    )

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
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)
        }
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
