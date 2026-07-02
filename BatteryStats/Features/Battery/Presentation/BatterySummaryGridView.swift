import SwiftUI

struct BatterySummaryGridView: View {
    let snapshot: BatterySnapshot
    let temperatureUnitPreference: TemperatureUnitPreference
    let temperatureUnitResolutionToken: Int
    let showsAdvancedValues: Bool

    var body: some View {
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
                tint: BatteryPresentationStyle.healthTint(for: snapshot)
            )

            BatteryCapacityBarSectionView(
                title: "Charge",
                capacityValue: BatteryFormatting.compactCapacityPair(
                    current: snapshot.currentChargeMilliampHours,
                    maximum: snapshot.fullChargeCapacityMilliampHours
                ),
                percentValue: BatterySummaryDetailFormatting.compactPercent(snapshot.presentationStateOfChargePercent),
                progress: snapshot.presentationStateOfChargePercent,
                tint: BatteryPresentationStyle.chargeTint(for: snapshot)
            )

            GroupBox {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
                    BatteryDetailRowView(title: timeTitle, value: timeSummary)

                    Divider()
                        .gridCellColumns(2)

                    BatteryDetailRowView(title: "Status", value: snapshot.statusDisplayTitle)

                    if let cycleCount = BatterySummaryDetailFormatting.cycleCount(snapshot.cycleCount) {
                        Divider()
                            .gridCellColumns(2)

                        BatteryDetailRowView(title: "Charge Cycles", value: cycleCount)
                    }

                    if let temperature = BatterySummaryDetailFormatting.temperature(
                        snapshot.presentationTemperatureCelsius,
                        unitPreference: temperatureUnitPreference
                    ) {
                        Divider()
                            .gridCellColumns(2)

                        BatteryDetailRowView(
                            title: "Temperature",
                            value: temperature
                        )
                        .id(temperatureUnitResolutionToken)
                    }

                    powerConnectionRows

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
        BatterySummaryDetailFormatting.timeTitle(for: snapshot)
    }

    private var timeSummary: String {
        BatterySummaryDetailFormatting.timeSummary(for: snapshot)
    }

    @ViewBuilder
    private var powerConnectionRows: some View {
        if let adapter = BatterySummaryDetailFormatting.adapter(snapshot.adapterMaxWatts) {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Adapter Rating", value: adapter)
        }

        if let chargingSpeed = BatterySummaryDetailFormatting.chargingSpeed(for: snapshot) {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Charging Speed", value: chargingSpeed)
        }
    }

    @ViewBuilder
    private var advancedRows: some View {
        if BatterySummaryDetailFormatting.chargingSpeed(for: snapshot) == nil,
           let power = BatterySummaryDetailFormatting.power(snapshot.activePowerWatts) {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: BatterySummaryDetailFormatting.powerTitle(for: snapshot), value: power)
        }

        if let voltage = BatterySummaryDetailFormatting.voltage(snapshot.voltageMillivolts) {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Voltage", value: voltage)
        }

        if let energy = BatterySummaryDetailFormatting.energy(
            current: snapshot.currentChargeWattHours,
            maximum: snapshot.fullChargeCapacityWattHours
        ) {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(
                title: "Energy",
                value: energy
            )
        }

        if let manufactureDate = BatterySummaryDetailFormatting.manufactureDate(snapshot.validatedManufactureDate) {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Made", value: manufactureDate)
        }

        if let age = BatterySummaryDetailFormatting.age(for: snapshot) {
            Divider()
                .gridCellColumns(2)

            BatteryDetailRowView(title: "Age", value: age)
        }
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

    static func timeTitle(for snapshot: BatterySnapshot) -> String {
        if snapshot.powerState == .charging {
            return "Time to Full"
        } else if snapshot.powerState.isBatteryDischarging {
            return "Time Left"
        } else {
            return "Time"
        }
    }

    static func timeSummary(for snapshot: BatterySnapshot) -> String {
        let timeText: String?
        switch snapshot.powerState {
        case .onBattery, .connectedDischarging, .charging:
            if let displayedTimeMinutes = BatteryCalculations.plausibleDurationMinutes(snapshot.displayedTimeMinutes) {
                timeText = BatteryFormatting.compactDuration(minutes: displayedTimeMinutes)
            } else {
                timeText = nil
            }
        case .connectedNotCharging, .fullOnAC, .unknown:
            timeText = nil
        }

        let rateText: String?
        if snapshot.powerState == .charging {
            if let activePowerWatts = BatteryCalculations.plausibleWatts(snapshot.activePowerWatts) {
                rateText = BatteryFormatting.watts(activePowerWatts)
            } else if let activeCurrentMilliamps = BatteryCalculations.plausibleCurrentMagnitudeMilliamps(snapshot.activeCurrentMilliamps) {
                rateText = BatteryFormatting.milliamps(activeCurrentMilliamps)
            } else {
                rateText = nil
            }
        } else if snapshot.powerState.isBatteryDischarging {
            if let activeCurrentMilliamps = BatteryCalculations.plausibleCurrentMagnitudeMilliamps(snapshot.activeCurrentMilliamps) {
                rateText = BatteryFormatting.milliamps(activeCurrentMilliamps)
            } else {
                rateText = nil
            }
        } else {
            rateText = nil
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

    static func cycleCount(_ value: Int?) -> String? {
        guard let value = BatteryCalculations.plausibleCycleCount(value) else {
            return nil
        }

        return String(value)
    }

    static func temperature(_ value: Double?, unitPreference: TemperatureUnitPreference) -> String? {
        guard let value = BatteryCalculations.plausibleTemperatureCelsius(value) else {
            return nil
        }

        return BatteryFormatting.temperature(value, unitPreference: unitPreference)
    }

    static func power(_ value: Double?) -> String? {
        guard let value = BatteryCalculations.plausibleWatts(value) else {
            return nil
        }

        return BatteryFormatting.watts(value)
    }

    static func adapter(_ value: Int?) -> String? {
        guard let value = BatteryCalculations.plausibleAdapterWatts(value) else {
            return nil
        }

        return "\(value.formatted(.number.grouping(.automatic))) W"
    }

    static func chargingSpeed(for snapshot: BatterySnapshot) -> String? {
        guard snapshot.powerState == .charging else {
            return nil
        }

        if let visibleInputPowerWatts = snapshot.visibleInputPowerWatts {
            return BatteryFormatting.watts(visibleInputPowerWatts)
        }

        guard let chargeRateWatts = BatteryCalculations.plausibleWatts(snapshot.chargeRateWatts) else {
            return nil
        }

        return BatteryFormatting.watts(chargeRateWatts)
    }

    static func powerTitle(for snapshot: BatterySnapshot) -> String {
        BatteryPowerDisplayRole.role(for: snapshot).title
    }

    static func voltage(_ value: Int?) -> String? {
        guard let value = BatteryCalculations.plausibleVoltageMillivolts(value) else {
            return nil
        }

        return BatteryFormatting.millivolts(value)
    }

    static func energy(current: Double?, maximum: Double?) -> String? {
        let current = BatteryCalculations.plausibleWattHours(current)
        let maximum = positiveWattHours(maximum)

        guard current != nil || maximum != nil else {
            return nil
        }

        return BatteryFormatting.compactWattHourPair(current: current, maximum: maximum)
    }

    static func manufactureDate(_ value: Date?) -> String? {
        guard let value else {
            return nil
        }

        return BatteryFormatting.date(value)
    }

    static func age(_ value: DateComponents?) -> String? {
        guard BatteryCalculations.displayableBatteryAgeComponents(value) != nil else {
            return nil
        }

        return BatteryFormatting.age(value)
    }

    static func age(for snapshot: BatterySnapshot) -> String? {
        age(snapshot.validatedBatteryAgeComponents)
    }

    private static func positiveWattHours(_ value: Double?) -> Double? {
        guard let value = BatteryCalculations.plausibleWattHours(value),
              value > 0 else {
            return nil
        }

        return value
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

    private var progressPresentation: BatteryCapacityProgressPresentation {
        BatteryCapacityProgressPresentation(progress: progress)
    }

    private var valueAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.35)
    }
}

struct BatteryCapacityProgressPresentation: Equatable {
    let fillFraction: Double?

    var isUnavailable: Bool {
        fillFraction == nil
    }

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
                    .fill(tint.opacity(presentation.isUnavailable ? 0.12 : 0.18))

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

    private var valueAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
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
