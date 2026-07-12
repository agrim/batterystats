import SwiftUI

struct BatteryWidgetMetricTile: View {
    let metric: BatteryWidgetMetric
    let size: CGFloat

    var body: some View {
        let lineWidth = max(5, size * BatteryWidgetRingLayout.lineWidthRatio)
        let progress = metric.progress.map { min(max($0, 0), 1) }

        ZStack {
            Circle()
                .stroke(
                    Color.secondary.opacity(BatteryWidgetRingLayout.trackOpacity),
                    style: StrokeStyle(lineWidth: lineWidth)
                )
                .padding(lineWidth / 2)

            if let progress, progress > 0 {
                if progress >= 1 {
                    Circle()
                        .stroke(metric.ringTint, lineWidth: lineWidth)
                        .padding(lineWidth / 2)
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            metric.ringTint,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                        .padding(lineWidth / 2)
                        .rotationEffect(.degrees(-90))
                }
            }

            BatteryWidgetMetricContent(metric: metric, size: size)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(metric.accessibilityLabel))
        .accessibilityValue(Text(metric.accessibilityValue))
    }
}

struct BatteryWidgetMetric {
    enum Content {
        case empty
        case text(String)
        case symbol(String)
    }

    let content: Content
    let progress: Double?
    let ringTint: Color
    let contentTint: Color
    let accessibilityLabel: String
    let accessibilityValue: String

    init(
        content: Content,
        progress: Double?,
        ringTint: Color,
        accessibilityLabel: String,
        accessibilityValue: String,
        contentTint: Color = .primary
    ) {
        self.content = content
        self.progress = progress
        self.ringTint = ringTint
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.contentTint = contentTint
    }
}

private struct BatteryWidgetMetricContent: View {
    let metric: BatteryWidgetMetric
    let size: CGFloat

    var body: some View {
        switch metric.content {
        case .empty:
            EmptyView()
        case let .text(value):
            Text(value)
                .font(.system(size: max(14, size * 0.225), weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metric.contentTint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .contentTransition(.numericText())
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: max(17, size * 0.27), weight: .medium, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(metric.contentTint)
        }
    }
}

private enum BatteryWidgetRingLayout {
    static let lineWidthRatio: CGFloat = 0.088
    static let trackOpacity = 0.22
}
