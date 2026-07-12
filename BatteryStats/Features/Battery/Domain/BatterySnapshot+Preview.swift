import Foundation

extension BatterySnapshot {
    static var previewDischarging: BatterySnapshot {
        let now = Date.now
        let manufactureDate = previewManufactureDate
        return BatterySnapshot(
            timestamp: now,
            powerState: .onBattery,
            isCharging: false,
            isExternalPowerConnected: false,
            currentChargeMilliampHours: 4_912,
            currentChargeWattHours: 62.8,
            fullChargeCapacityMilliampHours: 5_338,
            fullChargeCapacityWattHours: 68.3,
            designCapacityMilliampHours: 6_559,
            healthPercent: 81.4,
            stateOfChargePercent: 92.0,
            voltageMillivolts: 12_780,
            currentMilliampsSigned: -1_086,
            dischargeRateMilliamps: 1_086,
            chargeRateWatts: nil,
            dischargeRateWatts: 13.9,
            rateBasedTimeRemainingMinutes: 168,
            systemTimeRemainingMinutes: 180,
            timeToFullMinutes: nil,
            cycleCount: 247,
            manufactureDate: manufactureDate,
            temperatureCelsius: 34.2,
            adapterMaxWatts: nil,
            notes: []
        )
    }

    static var previewCharging: BatterySnapshot {
        let now = Date.now
        let manufactureDate = previewManufactureDate
        return BatterySnapshot(
            timestamp: now,
            powerState: .charging,
            isCharging: true,
            isExternalPowerConnected: true,
            currentChargeMilliampHours: 4_031,
            currentChargeWattHours: 52.0,
            fullChargeCapacityMilliampHours: 5_338,
            fullChargeCapacityWattHours: 68.3,
            designCapacityMilliampHours: 6_559,
            healthPercent: 81.4,
            stateOfChargePercent: 75.5,
            voltageMillivolts: 12_910,
            currentMilliampsSigned: 1_721,
            dischargeRateMilliamps: nil,
            chargeRateWatts: 22.2,
            dischargeRateWatts: nil,
            rateBasedTimeRemainingMinutes: nil,
            systemTimeRemainingMinutes: nil,
            timeToFullMinutes: 52,
            cycleCount: 247,
            manufactureDate: manufactureDate,
            temperatureCelsius: 32.0,
            adapterMaxWatts: 70,
            notes: []
        )
    }

    private static var previewManufactureDate: Date? {
        BatteryCalendar.gregorianUTC.date(from: DateComponents(year: 2023, month: 9, day: 12))
    }
}
