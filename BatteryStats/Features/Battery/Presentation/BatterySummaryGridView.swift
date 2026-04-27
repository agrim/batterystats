import SwiftUI

struct BatterySummaryGridView: View {
    let snapshot: BatterySnapshot
    let temperatureUnitPreference: TemperatureUnitPreference
    let showsAdvancedValues: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BatteryCapacityBarSectionView(
                title: "Health",
                capacityValue: BatteryFormatting.compactCapacityPair(
                    current: snapshot.fullChargeCapacityMilliampHours,
                    maximum: snapshot.designCapacityMilliampHours
                ),
                percentValue: BatteryFormatting.percent(snapshot.healthPercent, decimals: 0),
                progress: snapshot.healthPercent,
                tint: BatteryPresentationStyle.tint(for: snapshot.healthTone)
            )

            BatteryCapacityBarSectionView(
                title: "Charge",
                capacityValue: BatteryFormatting.compactCapacityPair(
                    current: snapshot.currentChargeMilliampHours,
                    maximum: snapshot.fullChargeCapacityMilliampHours
                ),
                percentValue: BatteryFormatting.percent(snapshot.stateOfChargePercent, decimals: 0),
                progress: snapshot.stateOfChargePercent,
                tint: BatteryPresentationStyle.tint(for: snapshot.chargeTone)
            )

            GroupBox {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
                    BatteryDetailRowView(title: timeTitle, value: timeSummary)

                    Divider()
                        .gridCellColumns(2)

                    BatteryDetailRowView(title: "Status", value: snapshot.statusDisplayTitle)

                    if let cycleCount = snapshot.cycleCount {
                        Divider()
                            .gridCellColumns(2)

                        BatteryDetailRowView(title: "Charge Cycles", value: String(cycleCount))
                    }

                    if snapshot.temperatureCelsius != nil {
                        Divider()
                            .gridCellColumns(2)

                        BatteryDetailRowView(
                            title: "Temperature",
                            value: BatteryFormatting.temperature(snapshot.temperatureCelsius, unitPreference: temperatureUnitPreference)
                        )
                    }

                    if showsAdvancedValues {
                        advancedRows
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var advancedRows: some View {
        if let activePowerWatts = snapshot.activePowerWatts {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Power", value: BatteryFormatting.watts(activePowerWatts))
        }

        if snapshot.voltageMillivolts != nil {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Voltage", value: BatteryFormatting.millivolts(snapshot.voltageMillivolts))
        }

        if snapshot.currentChargeWattHours != nil || snapshot.fullChargeCapacityWattHours != nil {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(
                title: "Energy",
                value: BatteryFormatting.compactWattHourPair(
                    current: snapshot.currentChargeWattHours,
                    maximum: snapshot.fullChargeCapacityWattHours
                )
            )
        }

        if let adapterMaxWatts = snapshot.adapterMaxWatts {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Adapter", value: "\(adapterMaxWatts) W")
        }

        if snapshot.manufactureDate != nil {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Made", value: BatteryFormatting.date(snapshot.manufactureDate))
        }

        if snapshot.batteryAgeComponents != nil {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Age", value: BatteryFormatting.age(snapshot.batteryAgeComponents))
        }
    }
}

private struct BatteryCapacityBarSectionView: View {
    private static let valueSpacing: CGFloat = 8
    private static let barSpacing: CGFloat = 10
    private static let barMinimumWidth: CGFloat = 148

    let title: String
    let capacityValue: String
    let percentValue: String
    let progress: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Self.valueSpacing) {
                Text(title)
                    .lineLimit(1)

                Text(capacityValue)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)
            }
            .font(.subheadline)

            HStack(alignment: .firstTextBaseline, spacing: Self.barSpacing) {
                ProgressView(value: clampedProgress)
                    .controlSize(.small)
                    .tint(tint)
                    .frame(minWidth: Self.barMinimumWidth, maxWidth: .infinity)

                Text(percentValue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
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

    var body: some View {
        GridRow {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(value)
                .monospacedDigit()
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)
                .gridColumnAlignment(.trailing)
                .contentTransition(.numericText())
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

#Preview {
    BatterySummaryGridView(snapshot: .previewDischarging, temperatureUnitPreference: .celsius, showsAdvancedValues: true)
        .padding()
}
