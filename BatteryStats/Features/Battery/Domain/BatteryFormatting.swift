import Foundation

enum BatteryFormatting {
    private static let manufactureDateStyle = Date.FormatStyle(
        date: .omitted,
        time: .omitted,
        locale: .current,
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
    )
    .year()
    .month(.abbreviated)

    static func milliampHours(_ value: Int?, allowsZero: Bool = true) -> String {
        BatteryCalculations.plausibleCapacityMilliampHours(value, allowsZero: allowsZero)
            .map { "\($0.formatted(.number.grouping(.automatic))) mAh" } ?? "Unavailable"
    }

    static func millivolts(_ value: Int?) -> String {
        BatteryCalculations.plausibleVoltageMillivolts(value)
            .map { "\($0.formatted(.number.grouping(.automatic))) mV" } ?? "Unavailable"
    }

    static func wattHours(_ value: Double?) -> String {
        BatteryCalculations.plausibleWattHours(value)
            .map { "\($0.formatted(.number.precision(.fractionLength(1)))) Wh" } ?? "Unavailable"
    }

    static func watts(_ value: Double?) -> String {
        BatteryCalculations.plausibleWatts(value)
            .map { "\($0.formatted(.number.precision(.fractionLength(1)))) W" } ?? "Unavailable"
    }

    static func adapterWatts(_ value: Int?) -> String? {
        BatteryCalculations.plausibleAdapterWatts(value).map {
            "\($0.formatted(.number.grouping(.automatic))) W"
        }
    }

    static func percent(_ value: Double?, decimals: Int = 0) -> String {
        guard let value,
              value.isFinite,
              value >= 0,
              value <= 100 else {
            return "Unavailable"
        }

        return "\(value.formatted(.number.precision(.fractionLength(decimals))))%"
    }

    static func signedMilliamps(_ value: Int?) -> String {
        BatteryCalculations.plausibleSignedCurrentMilliamps(value).map(formattedMilliamps) ?? "Unavailable"
    }

    static func milliamps(_ value: Int?) -> String {
        BatteryCalculations.plausibleCurrentMagnitudeMilliamps(value).map(formattedMilliamps) ?? "Unavailable"
    }

    static func duration(minutes: Int?) -> String {
        guard let minutes = BatteryCalculations.plausibleDurationMinutes(minutes) else {
            return "Unavailable"
        }

        if minutes == 0 {
            return "0m"
        }

        return DateComponentsFormatter.batteryStatsDuration.string(from: TimeInterval(minutes * 60)) ?? "Unavailable"
    }

    static func compactDuration(minutes: Int?) -> String {
        guard let minutes = BatteryCalculations.plausibleDurationMinutes(minutes) else {
            return "—"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        guard hours > 0 else {
            return "\(remainingMinutes)m"
        }

        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    static func compactWidgetDuration(minutes: Int?) -> String {
        guard let minutes = BatteryCalculations.plausibleDurationMinutes(minutes) else {
            return "—"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        guard hours > 0 else {
            return "\(remainingMinutes)m"
        }

        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h\(remainingMinutes)m"
    }

    static func temperature(_ celsiusValue: Double?, unitPreference: TemperatureUnitPreference) -> String {
        guard let celsiusValue = BatteryCalculations.plausibleTemperatureCelsius(celsiusValue) else {
            return "Unavailable"
        }

        switch unitPreference.resolvedUnit {
        case .celsius:
            return "\(celsiusValue.formatted(.number.precision(.fractionLength(1)))) °C"
        case .fahrenheit:
            let fahrenheitValue = (celsiusValue * 9 / 5) + 32
            return "\(fahrenheitValue.formatted(.number.precision(.fractionLength(1)))) °F"
        }
    }

    static func date(_ value: Date?) -> String {
        value.map { $0.formatted(manufactureDateStyle) } ?? "Unavailable"
    }

    static func age(_ components: DateComponents?) -> String {
        guard let completedComponents = BatteryCalculations.displayableBatteryAgeComponents(components) else {
            return "Unavailable"
        }

        if (completedComponents.year ?? 0) == 0,
           (completedComponents.month ?? 0) == 0 {
            return "0 mo"
        }

        return DateComponentsFormatter.batteryStatsAge.string(from: completedComponents) ?? "Unavailable"
    }

    static func summaryText(for snapshot: BatterySnapshot) -> String {
        let capacity = milliampHours(snapshot.fullChargeCapacityMilliampHours, allowsZero: false)
        let health = percent(snapshot.presentationHealthPercent, decimals: 1)
        return "\(capacity) • \(health) health"
    }

    static func compactCapacityPair(current: Int?, maximum: Int?, currentAllowsZero: Bool = true) -> String {
        let current = BatteryCalculations.plausibleCapacityMilliampHours(current, allowsZero: currentAllowsZero)
        let maximum = BatteryCalculations.plausibleCapacityMilliampHours(maximum, allowsZero: false)
        let displayCurrent = displayablePairCurrent(current: current, maximum: maximum, numericValue: Double.init)

        return compactPair(displayCurrent, maximum: maximum, unit: "mAh") {
            $0.formatted(.number.grouping(.automatic))
        }
    }

    static func compactWattHourPair(current: Double?, maximum: Double?) -> String {
        let current = BatteryCalculations.plausibleWattHours(current)
        let maximum = BatteryCalculations.positiveWattHours(maximum)
        let displayCurrent = displayablePairCurrent(current: current, maximum: maximum) { $0 }

        return compactPair(displayCurrent, maximum: maximum, unit: "Wh", numberText: wattHourNumber)
    }

    private static func formattedMilliamps(_ value: Int) -> String {
        "\(value.formatted(.number.grouping(.automatic))) mA"
    }

    private static func wattHourNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func compactPair<Value>(
        _ current: Value?,
        maximum: Value?,
        unit: String,
        numberText: (Value) -> String
    ) -> String {
        switch (current, maximum) {
        case let (current?, maximum?):
            return "\(numberText(current)) / \(numberText(maximum)) \(unit)"
        case let (current?, nil):
            return "\(numberText(current)) \(unit)"
        case let (nil, maximum?):
            return "\(numberText(maximum)) \(unit) max"
        case (nil, nil):
            return "Unavailable"
        }
    }

    private static func displayablePairCurrent<Value>(
        current: Value?,
        maximum: Value?,
        numericValue: (Value) -> Double
    ) -> Value? {
        guard let current, let maximum else {
            return current
        }

        let currentValue = numericValue(current)
        let maximumValue = numericValue(maximum)
        guard currentValue > maximumValue else {
            return current
        }

        let overagePercent = (currentValue / maximumValue) * 100
        guard overagePercent.isFinite,
              overagePercent <= 105 else {
            return nil
        }

        return current
    }
}
