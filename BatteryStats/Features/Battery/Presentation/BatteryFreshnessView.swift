import SwiftUI

struct BatteryFreshnessView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let lastUpdated: Date?
    let isRefreshing: Bool

    @State private var isPulseActive = false
    @State private var pulseUpdateTask: Task<Void, Never>?
    @State private var pulseTask: Task<Void, Never>?

    var body: some View {
        TimelineView(BatteryFreshnessTimelineSchedule(lastUpdated: lastUpdated, isRefreshing: isRefreshing)) { context in
            HStack(spacing: 6) {
                freshnessIndicator(now: context.date)

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
        .onAppear {
            schedulePulse()
        }
        .onChange(of: lastUpdated) { _, _ in
            schedulePulse()
        }
        .onChange(of: isRefreshing) { _, isRefreshing in
            if isRefreshing {
                schedulePulseCancellation()
            } else {
                schedulePulse()
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion {
                schedulePulseCancellation()
            } else {
                schedulePulse()
            }
        }
        .onDisappear {
            cancelPulseUpdate()
            cancelPulse()
        }
    }

    @ViewBuilder
    private func freshnessIndicator(now: Date) -> some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.62)
                .frame(width: 8, height: 8)
        } else {
            Circle()
                .fill(indicatorTint(now: now))
                .frame(width: 6, height: 6)
                .scaleEffect(isPulseActive ? 1.45 : 1)
                .opacity(isPulseActive ? 1 : 0.72)
                .animation(pulseAnimation, value: isPulseActive)
                .accessibilityHidden(true)
        }
    }

    private func indicatorTint(now: Date) -> Color {
        BatteryFreshnessFormatting.hasUsableUpdate(lastUpdated: lastUpdated, now: now) ? .green : .secondary
    }

    private var pulseAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.28)
    }

    private func schedulePulse() {
        schedulePulseUpdate { triggerPulse() }
    }

    private func schedulePulseCancellation() {
        schedulePulseUpdate { cancelPulse() }
    }

    private func schedulePulseUpdate(_ update: @escaping @MainActor () -> Void) {
        pulseUpdateTask?.cancel()
        pulseUpdateTask = Task { @MainActor in
            await Task.yield()
            guard Task.isCancelled == false else {
                return
            }

            pulseUpdateTask = nil
            update()
        }
    }

    private func cancelPulseUpdate() {
        pulseUpdateTask?.cancel()
        pulseUpdateTask = nil
    }

    private func triggerPulse() {
        pulseTask?.cancel()

        guard isRefreshing == false,
              lastUpdated != nil,
              BatteryFreshnessFormatting.hasUsableUpdate(lastUpdated: lastUpdated, now: Date()),
              reduceMotion == false else {
            isPulseActive = false
            return
        }

        isPulseActive = true

        pulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard Task.isCancelled == false else {
                return
            }

            isPulseActive = false
            pulseTask = nil
        }
    }

    private func cancelPulse() {
        pulseTask?.cancel()
        pulseTask = nil
        isPulseActive = false
    }
}

private struct BatteryFreshnessTimelineSchedule: TimelineSchedule {
    let lastUpdated: Date?
    let isRefreshing: Bool

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(
            nextDate: startDate,
            lastUpdated: lastUpdated,
            isRefreshing: isRefreshing
        )
    }

    struct Entries: Sequence, IteratorProtocol {
        var nextDate: Date
        let lastUpdated: Date?
        let isRefreshing: Bool

        mutating func next() -> Date? {
            let date = nextDate
            nextDate = BatteryFreshnessFormatting.nextStatusChangeDate(
                lastUpdated: lastUpdated,
                now: date,
                isRefreshing: isRefreshing
            )
            return date
        }
    }
}
