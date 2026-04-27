import SwiftUI

struct HistoryStatsView: View {
    let stats: BatteryHistoryStats?
    let unitPreference: TemperatureUnitPreference
    let emptyText: String

    var body: some View {
        Group {
            if let stats {
                VStack(alignment: .leading, spacing: 5) {
                    HistoryStatRow(title: "History", value: "\(stats.sampleCount) samples")
                    HistoryStatRow(title: "Latest", value: dateText(stats.latestTimestamp))
                    HistoryStatRow(title: "Captured", value: capturedText(for: stats))
                    HistoryStatRow(title: "Power", value: powerText(for: stats))
                    HistoryStatRow(
                        title: "Charge",
                        value: percentRangeText(
                            minimum: stats.minimumChargePercent,
                            maximum: stats.maximumChargePercent
                        )
                    )
                    HistoryStatRow(
                        title: "Temperature",
                        value: temperatureRangeText(
                            minimum: stats.minimumTemperatureCelsius,
                            maximum: stats.maximumTemperatureCelsius
                        )
                    )
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

    private func capturedText(for stats: BatteryHistoryStats) -> String {
        if Calendar.current.isDate(stats.firstTimestamp, inSameDayAs: stats.latestTimestamp) {
            return "\(dateText(stats.firstTimestamp)) - \(timeText(stats.latestTimestamp))"
        }

        return "\(dateText(stats.firstTimestamp)) - \(dateText(stats.latestTimestamp))"
    }

    private func powerText(for stats: BatteryHistoryStats) -> String {
        switch (stats.averagePowerWatts, stats.peakPowerWatts) {
        case let (.some(average), .some(peak)):
            return "Avg \(BatteryFormatting.watts(average)), Peak \(BatteryFormatting.watts(peak))"
        case let (.some(average), .none):
            return "Avg \(BatteryFormatting.watts(average))"
        case let (.none, .some(peak)):
            return "Peak \(BatteryFormatting.watts(peak))"
        case (.none, .none):
            return "Unavailable"
        }
    }

    private func percentRangeText(minimum: Double?, maximum: Double?) -> String {
        guard let minimum, let maximum else {
            return "Unavailable"
        }

        let minimumText = BatteryFormatting.percent(minimum)
        let maximumText = BatteryFormatting.percent(maximum)
        guard minimumText != maximumText else {
            return minimumText
        }

        return "\(minimumText) - \(maximumText)"
    }

    private func temperatureRangeText(minimum: Double?, maximum: Double?) -> String {
        guard let minimum, let maximum else {
            return "Unavailable"
        }

        let minimumText = BatteryFormatting.temperature(minimum, unitPreference: unitPreference)
        let maximumText = BatteryFormatting.temperature(maximum, unitPreference: unitPreference)
        guard minimumText != maximumText else {
            return minimumText
        }

        return "\(minimumText) - \(maximumText)"
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
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
