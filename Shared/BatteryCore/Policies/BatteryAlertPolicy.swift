import Foundation

struct BatteryAlertPolicy: Equatable {
    var isLowBatteryAlertEnabled = false
    var isChargeCompleteAlertEnabled = false
    var isHighTemperatureAlertEnabled = false

    var lowBatteryThresholdPercent: Double = 20
    var highTemperatureThresholdCelsius: Double = 40

    static let disabled = BatteryAlertPolicy()
}

struct BatteryHistoryPolicy: Equatable {
    var isEnabled = false
    var syncsToICloud = false

    static let disabled = BatteryHistoryPolicy()
}
