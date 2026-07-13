enum BatteryTelemetrySanitization {
    static func displayableAdapterMaxWatts(
        _ adapterMaxWatts: Int?,
        powerState: BatteryPowerState
    ) -> Int? {
        powerState.isExternallyPowered
            ? BatteryCalculations.plausibleAdapterWatts(adapterMaxWatts)
            : nil
    }

    static func displayableInputPowerWatts(
        _ inputPowerWatts: Double?,
        evidence: BatteryInputPowerEvidence? = nil,
        adapterMaxWatts: Int? = nil,
        powerState: BatteryPowerState
    ) -> Double? {
        powerState.isExternallyPowered
            ? BatteryCalculations.displayableInputPowerWatts(
                inputPowerWatts,
                evidence: evidence,
                adapterMaxWatts: adapterMaxWatts
            )
            : nil
    }

    static func displayablePowerRates(
        powerState: BatteryPowerState,
        chargeRateWatts: Double?,
        dischargeRateWatts: Double?
    ) -> (chargeRateWatts: Double?, dischargeRateWatts: Double?) {
        if powerState.isBatteryDischarging {
            return (nil, BatteryCalculations.plausibleWatts(dischargeRateWatts))
        } else if powerState == .charging {
            return (BatteryCalculations.plausibleWatts(chargeRateWatts), nil)
        } else {
            return (nil, nil)
        }
    }

    static func displayableTiming(
        powerState: BatteryPowerState,
        rateBasedTimeRemainingMinutes: Int?,
        systemTimeRemainingMinutes: Int?,
        timeToFullMinutes: Int?
    ) -> (
        rateBasedTimeRemainingMinutes: Int?,
        systemTimeRemainingMinutes: Int?,
        timeToFullMinutes: Int?
    ) {
        if powerState.isBatteryDischarging {
            return (
                BatteryCalculations.plausibleDurationMinutes(rateBasedTimeRemainingMinutes),
                BatteryCalculations.plausibleDurationMinutes(systemTimeRemainingMinutes),
                nil
            )
        } else if powerState == .charging {
            return (
                nil,
                nil,
                BatteryCalculations.plausibleDurationMinutes(timeToFullMinutes)
            )
        } else {
            return (nil, nil, nil)
        }
    }

    static func preferredTimeToFullMinutes(
        computedTimeToFullMinutes: Int?,
        reportedTimeToFullMinutes: Int?
    ) -> Int? {
        BatteryCalculations.plausibleDurationMinutes(reportedTimeToFullMinutes)
            ?? BatteryCalculations.plausibleDurationMinutes(computedTimeToFullMinutes)
    }

    static func chargeRateWattsWithinAdapterContract(
        voltageMillivolts: Int?,
        signedCurrentMilliamps: Int?,
        adapterMaxWatts: Int?
    ) -> Double? {
        BatteryCalculations.displayableLiveMeasuredInputPowerWatts(
            BatteryCalculations.chargeRateWatts(
                voltageMillivolts: voltageMillivolts,
                signedCurrentMilliamps: signedCurrentMilliamps
            ),
            adapterMaxWatts: adapterMaxWatts
        )
    }
}
