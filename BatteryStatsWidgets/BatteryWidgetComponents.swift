import SwiftUI
import WidgetKit

struct BatteryWidgetLayout {
    let circleDiameter: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let leadingInset: CGFloat
    let topInset: CGFloat

    init(size: CGSize) {
        // Match Apple's widget by giving the rings more true center gap while
        // keeping the overall grid tucked close to the widget edges.
        circleDiameter = floor(min(size.width * 0.392, size.height * 0.399))
        horizontalSpacing = max(20, round(min(size.width, size.height) * 0.073))
        verticalSpacing = max(20, round(min(size.width, size.height) * 0.073))

        let contentWidth = (circleDiameter * 2) + horizontalSpacing
        let contentHeight = (circleDiameter * 2) + verticalSpacing

        leadingInset = floor(max(0, (size.width - contentWidth) / 2))
        topInset = floor(max(0, (size.height - contentHeight) / 2))
    }

    var trailingColumnInset: CGFloat {
        leadingInset + circleDiameter + horizontalSpacing
    }

    var bottomRowInset: CGFloat {
        topInset + circleDiameter + verticalSpacing
    }
}

struct BatteryWidgetBackground: View {
    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)

            ContainerRelativeShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.black.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            ContainerRelativeShape()
                .stroke(Color.white.opacity(0.10), lineWidth: 0.9)
        }
    }
}

struct BatteryWidgetMetricTile: View {
    let metric: BatteryWidgetMetric
    let size: CGFloat

    var body: some View {
        Gauge(value: metric.progress) {
            EmptyView()
        } currentValueLabel: {
            BatteryWidgetMetricContent(metric: metric, size: size)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(metric.ringTint)
        .frame(width: size, height: size)
    }
}

struct BatteryWidgetMetric {
    enum Content {
        case text(String)
        case symbol(String)
    }

    let content: Content
    let progress: Double
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
    let healthTint: Color
    let chargeTint: Color
    let timeTint: Color
    let statusDescriptor: BatteryStatusDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: snapshot?.batterySymbolName ?? "battery.0")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(chargeTint)

                Text(statusTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text(BatteryFormatting.percent(snapshot?.stateOfChargePercent))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    BatteryMediumMetricView(
                        title: "Health",
                        value: BatteryFormatting.percent(snapshot?.healthPercent, decimals: 0),
                        symbolName: "heart.fill",
                        tint: healthTint
                    )

                    BatteryMediumMetricView(
                        title: "Charge",
                        value: BatteryFormatting.percent(snapshot?.stateOfChargePercent, decimals: 0),
                        symbolName: "bolt.fill",
                        tint: chargeTint
                    )
                }

                GridRow {
                    BatteryMediumMetricView(
                        title: timeTitle,
                        value: BatteryFormatting.compactDuration(minutes: snapshot?.displayedTimeMinutes),
                        symbolName: "clock",
                        tint: timeTint
                    )

                    BatteryMediumMetricView(
                        title: "Power",
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
        snapshot?.powerState == .charging ? "To Full" : "Time Left"
    }

    private var powerValue: String {
        guard let activePowerWatts = snapshot?.activePowerWatts else {
            return snapshot?.statusDisplayTitle ?? "-"
        }

        return BatteryFormatting.watts(activePowerWatts)
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
