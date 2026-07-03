import SwiftUI

struct BatteryFreshnessView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let lastUpdated: Date?
    let isRefreshing: Bool

    @State private var isPulseActive = false

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
        .task(id: pulseTrigger) {
            await runPulse()
        }
    }

    private var pulseTrigger: BatteryFreshnessPulseTrigger {
        BatteryFreshnessPulseTrigger(
            lastUpdated: lastUpdated,
            isRefreshing: isRefreshing,
            reduceMotion: reduceMotion
        )
    }

    @ViewBuilder
    private func freshnessIndicator(now: Date) -> some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.62)
                .frame(width: 8, height: 8)
        } else {
            let hasLiveUpdate = BatteryFreshnessFormatting.hasUsableUpdate(
                lastUpdated: lastUpdated,
                now: now
            )

            Circle()
                .fill(hasLiveUpdate ? .green : .secondary)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulseActive ? 1.45 : 1)
                .opacity(isPulseActive ? 1 : 0.72)
                .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: isPulseActive)
                .accessibilityHidden(true)
        }
    }

    @MainActor
    private func runPulse() async {
        await Task.yield()
        guard isRefreshing == false,
              BatteryFreshnessFormatting.hasUsableUpdate(lastUpdated: lastUpdated, now: Date()),
              reduceMotion == false else {
            isPulseActive = false
            return
        }

        isPulseActive = true

        try? await Task.sleep(for: .milliseconds(320))
        guard Task.isCancelled == false else {
            return
        }

        isPulseActive = false
    }
}

private struct BatteryFreshnessPulseTrigger: Equatable {
    let lastUpdated: Date?
    let isRefreshing: Bool
    let reduceMotion: Bool
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
