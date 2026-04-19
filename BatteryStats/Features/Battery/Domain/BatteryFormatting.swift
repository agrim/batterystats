import Foundation

enum BatteryFormatting {
    static func milliampHours(_ value: Int?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(value.formatted(.number.grouping(.automatic))) mAh"
    }

    static func millivolts(_ value: Int?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(value.formatted(.number.grouping(.automatic))) mV"
    }

    static func wattHours(_ value: Double?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(value.formatted(.number.precision(.fractionLength(1)))) Wh"
    }

    static func watts(_ value: Double?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(value.formatted(.number.precision(.fractionLength(1)))) W"
    }

    static func percent(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else {
            return "Unavailable"
        }

        let clamped = max(0, min(100, value))
        return "\(clamped.formatted(.number.precision(.fractionLength(decimals))))%"
    }

    static func signedMilliamps(_ value: Int?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(value.formatted(.number.grouping(.automatic))) mA"
    }

    static func milliamps(_ value: Int?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return "\(value.formatted(.number.grouping(.automatic))) mA"
    }

    static func duration(minutes: Int?) -> String {
        guard let minutes else {
            return "Unavailable"
        }

        return DateComponentsFormatter.batteryStatsDuration.string(from: TimeInterval(minutes * 60)) ?? "Unavailable"
    }

    static func temperature(_ celsiusValue: Double?, unitPreference: TemperatureUnitPreference) -> String {
        guard let celsiusValue else {
            return "Unavailable"
        }

        let resolvedUnit = unitPreference.resolvedUnit
        switch resolvedUnit {
        case .celsius:
            return "\(celsiusValue.formatted(.number.precision(.fractionLength(1)))) °C"
        case .fahrenheit:
            let fahrenheitValue = (celsiusValue * 9 / 5) + 32
            return "\(fahrenheitValue.formatted(.number.precision(.fractionLength(1)))) °F"
        }
    }

    static func date(_ value: Date?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return value.formatted(.dateTime.year().month(.abbreviated))
    }

    static func age(_ components: DateComponents?) -> String {
        guard let components else {
            return "Unavailable"
        }

        return DateComponentsFormatter.batteryStatsAge.string(from: components) ?? "Unavailable"
    }

    static func summaryText(for snapshot: BatterySnapshot) -> String {
        let capacity = milliampHours(snapshot.fullChargeCapacityMilliampHours)
        let health = percent(snapshot.healthPercent, decimals: 1)
        return "\(capacity) • \(health) health"
    }

    static func lastUpdated(_ date: Date?) -> String {
        guard let date else {
            return "Waiting for battery data"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: date, relativeTo: .now))"
    }
}
