import SwiftUI

struct BatteryFreshnessView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let lastUpdated: Date?
    let isRefreshing: Bool

    @State private var pulseToken = 0
    @State private var isPulseActive = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                freshnessIndicator

                Text(BatteryFreshnessFormatting.statusText(
                    lastUpdated: lastUpdated,
                    now: context.date,
                    isRefreshing: isRefreshing
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .onChange(of: lastUpdated) { _, _ in
            triggerPulse()
        }
    }

    @ViewBuilder
    private var freshnessIndicator: some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.62)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(indicatorTint)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulseActive ? 1.45 : 1)
                .opacity(isPulseActive ? 1 : 0.72)
                .animation(pulseAnimation, value: isPulseActive)
                .accessibilityHidden(true)
        }
    }

    private var indicatorTint: Color {
        lastUpdated == nil ? .secondary : .green
    }

    private var pulseAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.28)
    }

    private func triggerPulse() {
        guard lastUpdated != nil, reduceMotion == false else {
            return
        }

        let nextToken = pulseToken + 1
        pulseToken = nextToken
        isPulseActive = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard pulseToken == nextToken else {
                return
            }

            isPulseActive = false
        }
    }
}
