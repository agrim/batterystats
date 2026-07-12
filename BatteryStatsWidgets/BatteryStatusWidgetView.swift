import SwiftUI
import WidgetKit

struct BatteryStatusWidgetView: View {
    let entry: BatteryStatusEntry

    var body: some View {
        let snapshot = entry.snapshot
        let displayedTimeMinutes = snapshot == nil ? nil : entry.displayedTimeMinutes

        GeometryReader { geometry in
            let shortestSide = min(geometry.size.width, geometry.size.height)
            let circleDiameter = floor(shortestSide * BatterySmallWidgetLayout.ringDiameterRatio)
            let spacing = round(shortestSide * BatterySmallWidgetLayout.interRingSpacingRatio)
            let statusDescriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)
            let healthText = BatteryMetricFormatting.percentText(snapshot?.presentationHealthPercent)
            let healthMetric = BatteryWidgetMetric(
                content: snapshot?.presentationHealthPercent == nil ? .empty : .text(healthText),
                progress: BatteryMetricFormatting.clampedProgress(snapshot?.presentationHealthPercent),
                ringTint: BatteryPresentationStyle.healthTintStyle(for: snapshot).color,
                accessibilityLabel: "Battery Health",
                accessibilityValue: snapshot?.presentationHealthPercent == nil ? "Unavailable" : healthText
            )
            let chargeText = BatteryMetricFormatting.percentText(snapshot?.presentationStateOfChargePercent)
            let chargeMetric = BatteryWidgetMetric(
                content: snapshot?.presentationStateOfChargePercent == nil ? .empty : .text(chargeText),
                progress: BatteryMetricFormatting.clampedProgress(snapshot?.presentationStateOfChargePercent),
                ringTint: BatteryPresentationStyle.chargeTintStyle(for: snapshot).color,
                accessibilityLabel: "Charge",
                accessibilityValue: snapshot?.presentationStateOfChargePercent == nil ? "Unavailable" : chargeText
            )
            let timeText = BatteryMetricFormatting.timeText(minutes: displayedTimeMinutes)
            let timeRingTint = BatteryPresentationStyle.timeTintStyle(
                for: snapshot,
                displayedTimeMinutes: displayedTimeMinutes
            ).color
            let timeMetric = BatteryWidgetMetric(
                content: displayedTimeMinutes == nil ? .empty : .text(timeText),
                progress: BatteryMetricFormatting.timeProgress(minutes: displayedTimeMinutes),
                ringTint: timeRingTint,
                accessibilityLabel: snapshot?.powerState.timeTitle(
                    charging: "Time to Full",
                    discharging: "Time Remaining"
                ) ?? "Time Remaining",
                accessibilityValue: displayedTimeMinutes == nil ? "Unavailable" : timeText
            )
            let statusMetric = BatteryWidgetMetric(
                content: snapshot == nil ? .empty : .symbol(statusDescriptor.symbolName),
                progress: statusDescriptor.progress,
                ringTint: statusDescriptor.ringTint,
                accessibilityLabel: "Power State",
                accessibilityValue: snapshot?.statusDisplayTitle ?? "Unavailable",
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
        .containerBackground(for: .widget) {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)
        }
    }
}

private enum BatterySmallWidgetLayout {
    // Measured from Apple's four-device Batteries widget: large rings, a narrow
    // inter-ring gutter, and equal optical insets around the 2-by-2 grid.
    static let ringDiameterRatio: CGFloat = 0.40
    static let interRingSpacingRatio: CGFloat = 0.065
}
