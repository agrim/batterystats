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
        compactDuration(minutes: minutes, separator: " ")
    }

    static func compactWidgetDuration(minutes: Int?) -> String {
        compactDuration(minutes: minutes, separator: "")
    }

    private static func compactDuration(minutes: Int?, separator: String) -> String {
        guard let minutes = BatteryCalculations.plausibleDurationMinutes(minutes) else {
            return "—"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        guard hours > 0 else {
            return "\(remainingMinutes)m"
        }

        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h\(separator)\(remainingMinutes)m"
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

    static func compactCapacityPair(current: Int?, maximum: Int?, currentAllowsZero: Bool = true) -> String {
        let current = BatteryCalculations.plausibleCapacityMilliampHours(current, allowsZero: currentAllowsZero)
        let maximum = BatteryCalculations.plausibleCapacityMilliampHours(maximum, allowsZero: false)
        let displayCurrent: Int?
        if let current, let maximum, current > maximum {
            let overagePercent = (Double(current) / Double(maximum)) * 100
            displayCurrent = overagePercent.isFinite && overagePercent <= 105 ? current : nil
        } else {
            displayCurrent = current
        }

        let numberText: (Int) -> String = {
            $0.formatted(.number.grouping(.automatic))
        }
        return switch (displayCurrent, maximum) {
        case let (current?, maximum?):
            "\(numberText(current)) / \(numberText(maximum)) mAh"
        case let (current?, nil):
            "\(numberText(current)) mAh"
        case let (nil, maximum?):
            "\(numberText(maximum)) mAh max"
        case (nil, nil):
            "Unavailable"
        }
    }

    static func compactWattHours(_ value: Double?) -> String {
        guard let value = BatteryCalculations.plausibleWattHours(value) else {
            return "Unavailable"
        }

        return "\(value.formatted(.number.precision(.fractionLength(1)))) Wh"
    }

    private static func formattedMilliamps(_ value: Int) -> String {
        "\(value.formatted(.number.grouping(.automatic))) mA"
    }

}
