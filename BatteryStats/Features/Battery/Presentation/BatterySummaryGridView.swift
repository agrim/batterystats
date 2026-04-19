import AppKit
import SwiftUI

struct BatterySummaryGridView: View {
    let snapshot: BatterySnapshot
    let compact: Bool
    let temperatureUnitPreference: TemperatureUnitPreference

    var body: some View {
        summaryContent
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func tint(for tone: BatteryLevelTone) -> Color {
        switch tone {
        case .green:
            return Color(nsColor: .systemGreen)
        case .midGreen:
            return Color(nsColor: .systemGreen)
        case .greenYellow:
            return Color(nsColor: .systemYellow)
        case .yellow:
            return Color(nsColor: .systemYellow)
        case .red:
            return Color(nsColor: .systemRed)
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 10) {
            BatteryCapacityBarSectionView(
                title: "Health",
                capacityValue: BatteryFormatting.compactCapacityPair(
                    current: snapshot.fullChargeCapacityMilliampHours,
                    maximum: snapshot.designCapacityMilliampHours
                ),
                percentValue: BatteryFormatting.percent(snapshot.healthPercent, decimals: 0),
                progress: snapshot.healthPercent,
                tint: Self.tint(for: snapshot.healthTone),
                compact: compact
            )

            BatteryCapacityBarSectionView(
                title: "Charge",
                capacityValue: BatteryFormatting.compactCapacityPair(
                    current: snapshot.currentChargeMilliampHours,
                    maximum: snapshot.fullChargeCapacityMilliampHours
                ),
                percentValue: BatteryFormatting.percent(snapshot.stateOfChargePercent, decimals: 0),
                progress: snapshot.stateOfChargePercent,
                tint: Self.tint(for: snapshot.chargeTone),
                compact: compact
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    BatteryDetailRowView(title: timeTitle, value: timeSummary, compact: compact)

                    Divider()

                    BatteryDetailRowView(title: "Status", value: snapshot.statusDisplayTitle, compact: compact)

                    if let cycleCount = snapshot.cycleCount {
                        Divider()

                        BatteryDetailRowView(title: "Charge Cycles", value: String(cycleCount), compact: compact)
                    }

                    if snapshot.temperatureCelsius != nil {
                        Divider()

                        BatteryDetailRowView(
                            title: "Temperature",
                            value: BatteryFormatting.temperature(snapshot.temperatureCelsius, unitPreference: temperatureUnitPreference),
                            compact: compact
                        )
                    }
                }
                .padding(.horizontal, compact ? 8 : 9)
                .padding(.vertical, compact ? 2 : 3)
            }
        }
    }

    private var timeTitle: String {
        snapshot.powerState == .charging ? "Time to Full" : "Time Left"
    }

    private var timeSummary: String {
        let timeText: String?
        switch snapshot.powerState {
        case .onBattery:
            timeText = BatteryFormatting.compactDuration(minutes: snapshot.rateBasedTimeRemainingMinutes ?? snapshot.systemTimeRemainingMinutes)
        case .charging:
            timeText = BatteryFormatting.compactDuration(minutes: snapshot.timeToFullMinutes)
        case .connectedNotCharging, .fullOnAC, .unknown:
            timeText = nil
        }

        let rateText: String?
        switch snapshot.powerState {
        case .onBattery:
            rateText = snapshot.dischargeRateMilliamps.map(BatteryFormatting.milliamps)
        case .charging:
            rateText = BatteryCalculations.chargeRateMilliamps(from: snapshot.currentMilliampsSigned).map(BatteryFormatting.milliamps)
        case .connectedNotCharging, .fullOnAC, .unknown:
            rateText = nil
        }

        let components = [timeText, rateText].compactMap { value -> String? in
            guard let value, value.isEmpty == false, value != "—" else {
                return nil
            }

            return value
        }

        return components.isEmpty ? "—" : components.joined(separator: " / ")
    }
}

private struct BatteryCapacityBarSectionView: View {
    let title: String
    let capacityValue: String
    let percentValue: String
    let progress: Double?
    let tint: Color
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 5) {
            LabeledContent {
                Text(capacityValue)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .monospacedDigit()
            } label: {
                Text(title)
                    .foregroundStyle(.primary)
            }
            .font(compact ? .caption : .subheadline)

            HStack(alignment: .center, spacing: compact ? 8 : 10) {
                ProgressView(value: clampedProgress)
                    .progressViewStyle(.linear)
                    .controlSize(compact ? .small : .regular)
                    .tint(tint)
                    .frame(maxWidth: .infinity)

                Text(percentValue)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: compact ? 34 : 38, alignment: .trailing)
            }
        }
    }

    private var clampedProgress: Double {
        max(0, min(100, progress ?? 0)) / 100
    }
}

private struct BatteryDetailRowView: View {
    let title: String
    let value: String
    let compact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 10 : 12) {
            Text(title)
                .font(rowFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.9 : 0.85)

            Spacer(minLength: compact ? 12 : 16)

            Text(value)
                .font(rowFont)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .layoutPriority(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? 4 : 5)
    }

    private var rowFont: Font {
        compact ? .caption : .subheadline
    }
}

#Preview {
    BatterySummaryGridView(snapshot: .previewDischarging, compact: false, temperatureUnitPreference: .celsius)
        .padding()
}
