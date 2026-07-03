import SwiftUI

struct BatteryWidgetBackground: View {
    var body: some View {
        ContainerRelativeShape()
            .fill(.ultraThinMaterial)
    }
}

struct BatteryWidgetMetricTile: View {
    let metric: BatteryWidgetMetric
    let size: CGFloat

    var body: some View {
        Group {
            if let progress = metric.progress {
                Gauge(value: progress) {
                    EmptyView()
                } currentValueLabel: {
                    BatteryWidgetMetricContent(metric: metric, size: size)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(metric.ringTint)
            } else {
                ZStack {
                    Circle()
                        .stroke(
                            metric.ringTint.opacity(0.24),
                            style: StrokeStyle(lineWidth: max(4, size * 0.065), lineCap: .round)
                        )

                    BatteryWidgetMetricContent(metric: metric, size: size)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct BatteryWidgetMetric {
    enum Content {
        case text(String)
        case symbol(String)
    }

    let content: Content
    let progress: Double?
    let ringTint: Color
    let contentTint: Color
}

private struct BatteryWidgetMetricContent: View {
    let metric: BatteryWidgetMetric
    let size: CGFloat

    var body: some View {
        switch metric.content {
        case let .text(value):
            Text(value)
                .font(.system(size: max(16, size * 0.26), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metric.contentTint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: max(18, size * 0.30), weight: .semibold, design: .rounded))
                .foregroundStyle(metric.contentTint)
        }
    }
}

struct BatteryMediumWidgetView: View {
    let snapshot: BatterySnapshot?
    let updatedAt: Date?
    let now: Date

    var body: some View {
        let healthTint = BatteryPresentationStyle.healthTintStyle(for: snapshot).color
        let chargeTint = BatteryPresentationStyle.chargeTintStyle(for: snapshot).color
        let timeTint = BatteryPresentationStyle.timeTintStyle(for: snapshot).color
        let statusDescriptor = BatteryPresentationStyle.statusDescriptor(for: snapshot)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: BatteryPresentationStyle.batterySymbolName(for: snapshot))
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(chargeTint)

                Text(statusTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(BatteryWidgetMetricFormatting.percentText(snapshot?.presentationStateOfChargePercent))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)

                    Text(BatteryWidgetUpdateFormatting.statusText(updatedAt: updatedAt, now: now))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    BatteryMediumMetricView(
                        title: "Health",
                        value: BatteryWidgetMetricFormatting.percentText(snapshot?.presentationHealthPercent),
                        symbolName: "heart.fill",
                        tint: healthTint
                    )

                    BatteryMediumMetricView(
                        title: "Charge",
                        value: BatteryWidgetMetricFormatting.percentText(snapshot?.presentationStateOfChargePercent),
                        symbolName: "bolt.fill",
                        tint: chargeTint
                    )
                }

                GridRow {
                    BatteryMediumMetricView(
                        title: timeTitle,
                        value: BatteryWidgetMetricFormatting.timeText(for: snapshot),
                        symbolName: "clock",
                        tint: timeTint
                    )

                    BatteryMediumMetricView(
                        title: powerTitle,
                        value: powerValue,
                        symbolName: statusDescriptor.symbolName,
                        tint: statusDescriptor.ringTint
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusTitle: String {
        snapshot?.statusDisplayTitle ?? "Unavailable"
    }

    private var timeTitle: String {
        snapshot?.powerState.timeTitle(charging: "To Full", discharging: "Time Left") ?? "Time"
    }

    private var powerTitle: String {
        BatteryPowerDisplayRole.role(for: snapshot).title
    }

    private var powerValue: String {
        BatteryWidgetMetricFormatting.powerText(for: snapshot)
    }
}

private struct BatteryMediumMetricView: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
