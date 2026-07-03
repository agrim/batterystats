import SwiftUI

struct BatterySummaryGridView: View {
    let snapshot: BatterySnapshot
    let temperatureUnitPreference: TemperatureUnitPreference
    let temperatureUnitResolutionToken: Int
    let showsAdvancedValues: Bool

    var body: some View {
        let chargingSpeed = snapshot.powerState == .charging
            ? BatterySummaryDetailFormatting.power(snapshot.activePowerWatts)
            : nil

        VStack(alignment: .leading, spacing: 10) {
            BatteryCapacityBarSectionView(
                title: "Health",
                capacityValue: BatteryFormatting.compactCapacityPair(
                    current: snapshot.fullChargeCapacityMilliampHours,
                    maximum: snapshot.designCapacityMilliampHours,
                    currentAllowsZero: false
                ),
                percentValue: BatterySummaryDetailFormatting.compactPercent(snapshot.presentationHealthPercent),
                progress: snapshot.presentationHealthPercent,
                tint: BatteryPresentationStyle.healthTintStyle(for: snapshot).color
            )

            BatteryCapacityBarSectionView(
                title: "Charge",
                capacityValue: BatteryFormatting.compactCapacityPair(
                    current: snapshot.currentChargeMilliampHours,
                    maximum: snapshot.fullChargeCapacityMilliampHours
                ),
                percentValue: BatterySummaryDetailFormatting.compactPercent(snapshot.presentationStateOfChargePercent),
                progress: snapshot.presentationStateOfChargePercent,
                tint: BatteryPresentationStyle.chargeTintStyle(for: snapshot).color
            )

            GroupBox {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
                    BatteryDetailRowView(
                        title: snapshot.powerState.timeTitle(charging: "Time to Full", discharging: "Time Left"),
                        value: BatterySummaryDetailFormatting.timeSummary(for: snapshot)
                    )

                    rowDivider

                    BatteryDetailRowView(title: "Status", value: snapshot.statusDisplayTitle)

                    if let cycleCount = BatteryCalculations.plausibleCycleCount(snapshot.cycleCount) {
                        rowDivider

                        BatteryDetailRowView(title: "Charge Cycles", value: String(cycleCount))
                    }

                    if let temperature = BatteryCalculations.plausibleTemperatureCelsius(snapshot.presentationTemperatureCelsius) {
                        rowDivider

                        BatteryDetailRowView(
                            title: "Temperature",
                            value: BatteryFormatting.temperature(temperature, unitPreference: temperatureUnitPreference)
                        )
                        .id(temperatureUnitResolutionToken)
                    }

                    powerConnectionRows(chargingSpeed: chargingSpeed)

                    if showsAdvancedValues {
                        advancedRows(chargingSpeed: chargingSpeed)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func powerConnectionRows(chargingSpeed: String?) -> some View {
        if let adapter = BatteryFormatting.adapterWatts(snapshot.adapterMaxWatts) {
            rowDivider

            BatteryDetailRowView(
                title: "Adapter Rating",
                value: adapter
            )
        }

        if let chargingSpeed {
            rowDivider

            BatteryDetailRowView(title: "Charging Speed", value: chargingSpeed)
        }
    }

    @ViewBuilder
    private func advancedRows(chargingSpeed: String?) -> some View {
        if chargingSpeed == nil,
           let power = BatterySummaryDetailFormatting.power(snapshot.activePowerWatts) {
            rowDivider

            BatteryDetailRowView(title: BatteryPowerDisplayRole.role(for: snapshot).title, value: power)
        }

        if let voltage = BatteryCalculations.plausibleVoltageMillivolts(snapshot.voltageMillivolts) {
            rowDivider

            BatteryDetailRowView(title: "Voltage", value: BatteryFormatting.millivolts(voltage))
        }

        let currentEnergy = BatteryCalculations.plausibleWattHours(snapshot.currentChargeWattHours)
        let maximumEnergy = BatteryCalculations.positiveWattHours(snapshot.fullChargeCapacityWattHours)
        if currentEnergy != nil || maximumEnergy != nil {
            rowDivider

            BatteryDetailRowView(
                title: "Energy",
                value: BatteryFormatting.compactWattHourPair(current: currentEnergy, maximum: maximumEnergy)
            )
        }

        if let manufactureDate = snapshot.validatedManufactureDate {
            rowDivider

            BatteryDetailRowView(title: "Made", value: BatteryFormatting.date(manufactureDate))
        }

        if let age = snapshot.validatedBatteryAgeComponents {
            rowDivider

            BatteryDetailRowView(title: "Age", value: BatteryFormatting.age(age))
        }
    }

    private var rowDivider: some View {
        Divider()
            .gridCellColumns(2)
    }
}

enum BatterySummaryDetailFormatting {
    static func compactPercent(_ value: Double?) -> String {
        guard let value,
              value.isFinite,
              value >= 0,
              value <= 100 else {
            return "—"
        }

        return BatteryFormatting.percent(value, decimals: 0)
    }

    static func timeSummary(for snapshot: BatterySnapshot) -> String {
        let timeText = snapshot.displayedTimeMinutes.map {
            BatteryFormatting.compactDuration(minutes: $0)
        }

        let rateText: String? = switch snapshot.powerState {
        case .charging:
            power(snapshot.activePowerWatts)
                ?? BatteryCalculations.plausibleCurrentMagnitudeMilliamps(snapshot.activeCurrentMilliamps).map { BatteryFormatting.milliamps($0) }
        case .onBattery, .connectedDischarging:
            BatteryCalculations.plausibleCurrentMagnitudeMilliamps(snapshot.activeCurrentMilliamps).map { BatteryFormatting.milliamps($0) }
        case .connectedNotCharging, .fullOnAC, .unknown:
            nil
        }

        if let timeText, let rateText {
            return "\(timeText) / \(rateText)"
        }

        if let timeText {
            return timeText
        }

        if let rateText {
            return "Estimating / \(rateText)"
        }

        return "—"
    }

    static func power(_ value: Double?) -> String? {
        guard let value = BatteryCalculations.plausibleWatts(value) else {
            return nil
        }

        return BatteryFormatting.watts(value)
    }

}

private struct BatteryCapacityBarSectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let valueSpacing: CGFloat = 8
    private static let barSpacing: CGFloat = 10
    private static let barMinimumWidth: CGFloat = 148

    let title: String
    let capacityValue: String
    let percentValue: String
    let progress: Double?
    let tint: Color

    var body: some View {
        let progressPresentation = BatteryCapacityProgressPresentation(progress: progress)
        let valueAnimation: Animation? = reduceMotion ? nil : .smooth(duration: 0.35)

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

            HStack(alignment: .center, spacing: Self.barSpacing) {
                BatteryCapacityProgressBar(presentation: progressPresentation, tint: tint)
                    .frame(minWidth: Self.barMinimumWidth, maxWidth: .infinity)
                    .animation(valueAnimation, value: progressPresentation)

                Text(percentValue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .animation(valueAnimation, value: percentValue)
            }
        }
    }
}

struct BatteryCapacityProgressPresentation: Equatable {
    let fillFraction: Double?

    init(progress: Double?) {
        guard let progress, progress.isFinite, progress >= 0 else {
            fillFraction = nil
            return
        }

        fillFraction = max(0, min(100, progress)) / 100
    }
}

private struct BatteryCapacityProgressBar: View {
    let presentation: BatteryCapacityProgressPresentation
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(presentation.fillFraction == nil ? 0.12 : 0.18))

                if let fillFraction = presentation.fillFraction {
                    let fillWidth = width * fillFraction
                    if fillWidth > 0 {
                        Capsule()
                            .fill(tint)
                            .frame(width: fillWidth)
                    }
                } else if width > 0 {
                    Capsule()
                        .fill(tint.opacity(0.46))
                        .frame(width: min(width, max(36, width * 0.28)))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

private struct BatteryDetailRowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let value: String

    var body: some View {
        let valueAnimation: Animation? = reduceMotion ? nil : .smooth(duration: 0.25)

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
                .animation(valueAnimation, value: value)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

#Preview {
    BatterySummaryGridView(
        snapshot: .previewDischarging,
        temperatureUnitPreference: .celsius,
        temperatureUnitResolutionToken: 0,
        showsAdvancedValues: true
    )
        .padding()
}
