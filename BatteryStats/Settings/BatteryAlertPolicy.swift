import Foundation

struct BatteryAlertPolicy: Equatable {
    var isLowBatteryAlertEnabled = false
    var isChargeCompleteAlertEnabled = false
    var isHighTemperatureAlertEnabled = false
    var temperatureUnitPreference: TemperatureUnitPreference = .system

    var lowBatteryThresholdPercent: Double = 20
    var highTemperatureThresholdCelsius: Double = 40

    var hasEnabledAlerts: Bool {
        isLowBatteryAlertEnabled
            || isChargeCompleteAlertEnabled
            || isHighTemperatureAlertEnabled
    }

    static let disabled = BatteryAlertPolicy()
}

struct BatteryHistoryPolicy: Equatable {
    var isEnabled = false
    var syncsToICloud = false

    static let disabled = BatteryHistoryPolicy()
}
