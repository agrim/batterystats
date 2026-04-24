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

    static func compactDuration(minutes: Int?) -> String {
        guard let minutes else {
            return "—"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            if remainingMinutes == 0 {
                return "\(hours)h"
            }

            return "\(hours)h \(remainingMinutes)m"
        }

        return "\(remainingMinutes)m"
    }

    static func compactWidgetDuration(minutes: Int?) -> String {
        guard let minutes else {
            return "—"
        }

        if minutes < 60 {
            return "\(max(1, minutes))m"
        }

        let roundedHours = max(1, Int((Double(minutes) / 60).rounded(.toNearestOrAwayFromZero)))
        return "\(roundedHours)h"
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

    static func compactCapacityPair(current: Int?, maximum: Int?) -> String {
        guard let current, let maximum else {
            return "Unavailable"
        }

        return "\(current.formatted(.number.grouping(.automatic))) / \(maximum.formatted(.number.grouping(.automatic))) mAh"
    }

    static func compactWattHourPair(current: Double?, maximum: Double?) -> String {
        guard let current, let maximum else {
            return "Unavailable"
        }

        let currentText = current.formatted(.number.precision(.fractionLength(1)))
        let maximumText = maximum.formatted(.number.precision(.fractionLength(1)))
        return "\(currentText) / \(maximumText) Wh"
    }
}
