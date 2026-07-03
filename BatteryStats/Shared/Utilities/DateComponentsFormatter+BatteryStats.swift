import Foundation

extension DateComponentsFormatter {
    static let batteryStatsDuration = batteryStatsFormatter(allowedUnits: [.hour, .minute])
    static let batteryStatsAge = batteryStatsFormatter(allowedUnits: [.year, .month])

    private static func batteryStatsFormatter(allowedUnits: NSCalendar.Unit) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = allowedUnits
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        formatter.maximumUnitCount = 2
        return formatter
    }
}
