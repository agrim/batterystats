import SwiftUI

struct HistoryStatsView: View {
    let stats: BatteryHistoryStats?
    let unitPreference: TemperatureUnitPreference
    let unitResolutionToken: Int
    let emptyText: String

    var body: some View {
        Group {
            if let stats {
                VStack(alignment: .leading, spacing: 5) {
                    HistoryStatRow(title: "History", value: BatteryHistoryTextFormatting.sampleCountText(stats.sampleCount))
                    HistoryStatRow(title: "Latest", value: HistoryStatsFormatting.dateText(stats.latestTimestamp))
                    HistoryStatRow(title: "Captured", value: HistoryStatsFormatting.capturedText(for: stats))
                    HistoryStatRow(title: "Power", value: powerText(for: stats))
                    HistoryStatRow(
                        title: "Charge",
                        value: rangeText(
                            minimum: stats.minimumChargePercent,
                            maximum: stats.maximumChargePercent,
                            formatter: { BatteryFormatting.percent($0) }
                        )
                    )
                    HistoryStatRow(
                        title: "Temperature",
                        value: rangeText(
                            minimum: stats.minimumTemperatureCelsius,
                            maximum: stats.maximumTemperatureCelsius,
                            formatter: { BatteryFormatting.temperature($0, unitPreference: unitPreference) }
                        )
                    )
                    .id(unitResolutionToken)
                }
                .font(.footnote)
            } else {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

enum HistoryStatsFormatting {
    static func capturedText(for stats: BatteryHistoryStats, calendar: Calendar = .current) -> String {
        if stats.firstTimestamp == stats.latestTimestamp {
            return dateText(stats.firstTimestamp)
        }

        if calendar.isDate(stats.firstTimestamp, inSameDayAs: stats.latestTimestamp) {
            return "\(dateText(stats.firstTimestamp)) - \(timeText(stats.latestTimestamp))"
        }

        return "\(dateText(stats.firstTimestamp)) - \(dateText(stats.latestTimestamp))"
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

private extension HistoryStatsView {
    private func powerText(for stats: BatteryHistoryStats) -> String {
        let values = [
            stats.averagePowerWatts.map { "Avg \(BatteryFormatting.watts($0))" },
            stats.peakPowerWatts.map { "Peak \(BatteryFormatting.watts($0))" }
        ].compactMap { $0 }

        return values.isEmpty ? "Unavailable" : values.joined(separator: ", ")
    }

    private func rangeText<Value>(
        minimum: Value?,
        maximum: Value?,
        formatter: (Value) -> String
    ) -> String {
        guard let minimum, let maximum else {
            return "Unavailable"
        }

        let minimumText = formatter(minimum)
        let maximumText = formatter(maximum)
        guard minimumText != maximumText else {
            return minimumText
        }

        return "\(minimumText) - \(maximumText)"
    }
}

private struct HistoryStatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .lineLimit(2)
                .layoutPriority(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
