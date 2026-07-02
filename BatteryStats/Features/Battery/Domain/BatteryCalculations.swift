import Foundation

enum BatteryCalculations {
    private static let maximumPlausibleBatteryCapacityMilliampHours = 1_000_000
    private static let maximumPlausibleBatteryCurrentMilliamps = 1_000_000
    private static let maximumPlausibleBatteryVoltageMillivolts = 100_000
    private static let maximumPlausibleBatteryEnergyWattHours = 100_000.0
    private static let minimumPlausibleBatteryPowerWatts = 0.1
    private static let maximumPlausibleBatteryPowerWatts = 1_000.0
    private static let maximumUnverifiedInputPowerWatts = 90.0
    private static let adapterCapabilityEchoTolerance = 0.02
    private static let counterBackedAdapterCapabilityEchoTolerance = 0.005
    private static let highWattageCounterBackedAdapterCapabilityEchoTolerance = 0.05
    private static let maximumPlausibleAdapterWatts = 1_000
    private static let maximumPlausibleCycleCount = 100_000
    private static let maximumPlausibleDurationMinutes = 24 * 60
    private static let gregorianUTCCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    private static let minimumPlausibleManufactureDateComponents = DateComponents(year: 2006, month: 1, day: 1)

    static func stateOfChargePercent(
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?,
        publicPercentage: Double?
    ) -> Double? {
        let publicPercentage = publicPercentage.flatMap(normalizedPercent)

        if let currentChargeMilliampHours = plausibleCapacityMilliampHours(currentChargeMilliampHours),
           let fullChargeCapacityMilliampHours = plausibleCapacityMilliampHours(fullChargeCapacityMilliampHours, allowsZero: false) {
            let calculatedPercentage = (Double(currentChargeMilliampHours) / Double(fullChargeCapacityMilliampHours)) * 100
            guard let normalizedCalculatedPercentage = normalizedPercent(calculatedPercentage) else {
                return publicPercentage
            }

            if let publicPercentage,
               shouldPreferCapacityPercent(calculated: normalizedCalculatedPercentage, publicPercentage: publicPercentage) {
                return normalizedCalculatedPercentage
            }

            if let publicPercentage,
               shouldPreferFullPublicPercentWhenCapacityIsEmpty(calculated: normalizedCalculatedPercentage, publicPercentage: publicPercentage) {
                return publicPercentage
            }

            if let publicPercentage,
               shouldPreferPublicPercent(calculated: normalizedCalculatedPercentage, publicPercentage: publicPercentage) {
                return publicPercentage
            }

            return normalizedCalculatedPercentage
        }

        return publicPercentage
    }

    static func reconciledCurrentChargeMilliampHours(
        smartCurrentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?,
        publicPercentage: Double?
    ) -> Int? {
        let smartCurrentChargeMilliampHours = plausibleCapacityMilliampHours(smartCurrentChargeMilliampHours)
        let derivedCurrentChargeMilliampHours = deriveCurrentChargeMilliampHours(
            publicPercentage: publicPercentage,
            fullChargeCapacityMilliampHours: fullChargeCapacityMilliampHours
        )

        guard let smartCurrentChargeMilliampHours else {
            return derivedCurrentChargeMilliampHours
        }

        guard let fullChargeCapacityMilliampHours = plausibleCapacityMilliampHours(fullChargeCapacityMilliampHours, allowsZero: false) else {
            return smartCurrentChargeMilliampHours
        }

        let smartPercentage = (Double(smartCurrentChargeMilliampHours) / Double(fullChargeCapacityMilliampHours)) * 100
        guard let normalizedSmartPercentage = normalizedPercent(smartPercentage) else {
            return derivedCurrentChargeMilliampHours
        }
        let boundedSmartCurrentChargeMilliampHours = min(smartCurrentChargeMilliampHours, fullChargeCapacityMilliampHours)

        guard let publicPercentage = publicPercentage.flatMap(normalizedPercent) else {
            return boundedSmartCurrentChargeMilliampHours
        }

        if shouldPreferCapacityPercent(calculated: normalizedSmartPercentage, publicPercentage: publicPercentage) {
            return boundedSmartCurrentChargeMilliampHours
        }

        if shouldPreferFullPublicPercentWhenCapacityIsEmpty(calculated: normalizedSmartPercentage, publicPercentage: publicPercentage) {
            return derivedCurrentChargeMilliampHours ?? boundedSmartCurrentChargeMilliampHours
        }

        if shouldPreferPublicPercent(calculated: normalizedSmartPercentage, publicPercentage: publicPercentage) {
            return derivedCurrentChargeMilliampHours ?? boundedSmartCurrentChargeMilliampHours
        }

        return boundedSmartCurrentChargeMilliampHours
    }

    static func healthPercent(fullChargeCapacityMilliampHours: Int?, designCapacityMilliampHours: Int?) -> Double? {
        guard let fullChargeCapacityMilliampHours = plausibleCapacityMilliampHours(fullChargeCapacityMilliampHours, allowsZero: false),
              let designCapacityMilliampHours = plausibleCapacityMilliampHours(designCapacityMilliampHours, allowsZero: false) else {
            return nil
        }

        let calculatedPercent = (Double(fullChargeCapacityMilliampHours) / Double(designCapacityMilliampHours)) * 100
        guard calculatedPercent.isFinite,
              calculatedPercent >= 0,
              calculatedPercent <= 120 else {
            return nil
        }

        return min(100, calculatedPercent)
    }

    static func wattHours(milliampHours: Int?, voltageMillivolts: Int?) -> Double? {
        guard let milliampHours = plausibleCapacityMilliampHours(milliampHours),
              let voltageMillivolts = plausibleVoltageMillivolts(voltageMillivolts) else {
            return nil
        }

        return plausibleWattHours((Double(milliampHours) * Double(voltageMillivolts)) / 1_000_000)
    }

    static func dischargeRateMilliamps(from signedCurrentMilliamps: Int?) -> Int? {
        negativeCurrentMagnitude(signedCurrentMilliamps)
    }

    static func plausibleCapacityMilliampHours(_ value: Int?, allowsZero: Bool = true) -> Int? {
        guard let value,
              value >= (allowsZero ? 0 : 1),
              value <= maximumPlausibleBatteryCapacityMilliampHours else {
            return nil
        }

        return value
    }

    static func plausibleVoltageMillivolts(_ value: Int?) -> Int? {
        guard let value,
              value > 0,
              value <= maximumPlausibleBatteryVoltageMillivolts else {
            return nil
        }

        return value
    }

    static func plausibleSignedCurrentMilliamps(_ value: Int?) -> Int? {
        guard let value,
              value != Int.min,
              plausibleCurrentMagnitudeMilliamps(value < 0 ? -value : value) != nil else {
            return nil
        }

        return value
    }

    static func plausibleCurrentMagnitudeMilliamps(_ value: Int?) -> Int? {
        guard let value,
              value >= 0,
              value <= maximumPlausibleBatteryCurrentMilliamps else {
            return nil
        }

        return value
    }

    static func plausibleDischargeRateMilliamps(_ value: Int?) -> Int? {
        guard let value = plausibleCurrentMagnitudeMilliamps(value),
              value > 40 else {
            return nil
        }

        return value
    }

    static func plausibleWattHours(_ value: Double?) -> Double? {
        guard let value,
              value.isFinite,
              value >= 0,
              value <= maximumPlausibleBatteryEnergyWattHours else {
            return nil
        }

        return value
    }

    static func presentationPercent(_ value: Double?, maximumAllowed: Double) -> Double? {
        guard let value,
              value.isFinite,
              value >= 0,
              value <= maximumAllowed else {
            return nil
        }

        return min(100, value)
    }

    static func positiveWattHours(_ value: Double?) -> Double? {
        guard let value = plausibleWattHours(value),
              value > 0 else {
            return nil
        }

        return value
    }

    static func plausibleWatts(_ value: Double?) -> Double? {
        guard let value,
              value.isFinite,
              value >= minimumPlausibleBatteryPowerWatts,
              value <= maximumPlausibleBatteryPowerWatts else {
            return nil
        }

        return value
    }

    static func plausibleInputPowerWatts(_ value: Double?, adapterMaxWatts: Int?) -> Double? {
        guard let value = plausibleWatts(value) else {
            return nil
        }

        guard let adapterMaxWatts = plausibleAdapterWatts(adapterMaxWatts) else {
            return value
        }

        return value <= Double(adapterMaxWatts) * 1.15 ? value : nil
    }

    static func displayableInputPowerWatts(_ value: Double?, adapterMaxWatts: Int?) -> Double? {
        guard let value = plausibleInputPowerWatts(value, adapterMaxWatts: adapterMaxWatts) else {
            return nil
        }

        guard plausibleAdapterWatts(adapterMaxWatts) != nil || value < maximumUnverifiedInputPowerWatts else {
            return nil
        }

        guard isDistinctFromAdapterCapability(value, adapterMaxWatts: adapterMaxWatts) else {
            return nil
        }

        return value
    }

    static func displayableCounterBackedInputPowerWatts(_ value: Double?, adapterMaxWatts: Int?) -> Double? {
        guard let value = plausibleInputPowerWatts(value, adapterMaxWatts: adapterMaxWatts) else {
            return nil
        }

        guard plausibleAdapterWatts(adapterMaxWatts) != nil || value < maximumUnverifiedInputPowerWatts else {
            return nil
        }

        guard isDistinctFromCounterBackedAdapterCapability(value, adapterMaxWatts: adapterMaxWatts) else {
            return nil
        }

        return value
    }

    static func plausibleAdapterWatts(_ value: Int?) -> Int? {
        guard let value,
              value > 0,
              value <= maximumPlausibleAdapterWatts else {
            return nil
        }

        return value
    }

    static func plausibleCycleCount(_ value: Int?) -> Int? {
        guard let value,
              value >= 0,
              value <= maximumPlausibleCycleCount else {
            return nil
        }

        return value
    }

    static func chargeRateWatts(voltageMillivolts: Int?, signedCurrentMilliamps: Int?) -> Double? {
        guard let voltageMillivolts = plausibleVoltageMillivolts(voltageMillivolts),
              let chargeCurrentMilliamps = chargeRateMilliamps(from: signedCurrentMilliamps) else {
            return nil
        }

        return plausibleWatts((Double(voltageMillivolts) * Double(chargeCurrentMilliamps)) / 1_000_000)
    }

    static func chargeRateMilliamps(from signedCurrentMilliamps: Int?) -> Int? {
        guard let signedCurrentMilliamps = plausibleSignedCurrentMilliamps(signedCurrentMilliamps),
              signedCurrentMilliamps > 40 else {
            return nil
        }

        return signedCurrentMilliamps
    }

    static func dischargeRateWatts(voltageMillivolts: Int?, signedCurrentMilliamps: Int?) -> Double? {
        guard let voltageMillivolts = plausibleVoltageMillivolts(voltageMillivolts),
              let dischargeCurrentMilliamps = negativeCurrentMagnitude(signedCurrentMilliamps) else {
            return nil
        }

        return plausibleWatts((Double(voltageMillivolts) * Double(dischargeCurrentMilliamps)) / 1_000_000)
    }

    static func timeRemainingMinutes(currentChargeMilliampHours: Int?, dischargeRateMilliamps: Int?) -> Int? {
        guard let currentChargeMilliampHours = plausibleCapacityMilliampHours(currentChargeMilliampHours),
              let dischargeRateMilliamps = plausibleDischargeRateMilliamps(dischargeRateMilliamps) else {
            return nil
        }

        let hours = Double(currentChargeMilliampHours) / Double(dischargeRateMilliamps)
        let minutes = Int((hours * 60).rounded())
        guard (1...1_440).contains(minutes) else {
            return nil
        }

        return minutes
    }

    static func estimatedTimeToFullMinutes(
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?,
        chargeCurrentMilliamps: Int?,
        reportedTimeToFullMinutes: Int?
    ) -> Int? {
        let reportedTimeToFullMinutes = plausibleDurationMinutes(reportedTimeToFullMinutes)

        guard let currentChargeMilliampHours = plausibleCapacityMilliampHours(currentChargeMilliampHours),
              let fullChargeCapacityMilliampHours = plausibleCapacityMilliampHours(fullChargeCapacityMilliampHours, allowsZero: false) else {
            return reportedTimeToFullMinutes
        }

        if currentChargeMilliampHours >= fullChargeCapacityMilliampHours {
            return 0
        }

        guard let chargeCurrentMilliamps = plausibleCurrentMagnitudeMilliamps(chargeCurrentMilliamps),
              chargeCurrentMilliamps > 40 else {
            return reportedTimeToFullMinutes
        }

        let totalCapacity = Double(fullChargeCapacityMilliampHours)
        let startRatio = max(0, min(0.995, Double(currentChargeMilliampHours) / totalCapacity))
        let remainingRatio = 1 - startRatio

        guard remainingRatio > 0 else {
            return 0
        }

        let steps = 40
        let sliceCapacity = (totalCapacity * remainingRatio) / Double(steps)
        var accumulatedMinutes = 0.0

        for step in 0..<steps {
            let progress = (Double(step) + 0.5) / Double(steps)
            let chargePercent = (startRatio + (progress * remainingRatio)) * 100
            accumulatedMinutes += (sliceCapacity / Double(chargeCurrentMilliamps)) * 60 * chargeTaperMultiplier(forPercent: chargePercent)
        }

        let estimatedMinutes = Int(accumulatedMinutes.rounded())
        guard (1...1_440).contains(estimatedMinutes) else {
            return reportedTimeToFullMinutes
        }

        return estimatedMinutes
    }

    static func plausibleDurationMinutes(_ value: Int?) -> Int? {
        guard let value,
              (0...maximumPlausibleDurationMinutes).contains(value) else {
            return nil
        }

        return value
    }

    static func smoothedDischargeRate(_ samples: [Int], fallback: Int?) -> Int? {
        var total = 0
        var count = 0

        for sample in samples.suffix(8) {
            guard let sample = plausibleDischargeRateMilliamps(sample) else {
                continue
            }

            total += sample
            count += 1
        }

        guard count > 0 else {
            return plausibleDischargeRateMilliamps(fallback)
        }

        return Int((Double(total) / Double(count)).rounded())
    }

    static func plausibleManufactureDate(_ manufactureDate: Date?, now: Date) -> Date? {
        guard let manufactureDate,
              isOnOrAfterMinimumPlausibleManufactureDay(manufactureDate),
              isManufactureDay(manufactureDate, onOrBefore: now) else {
            return nil
        }

        return manufactureDate
    }

    static func batteryAgeComponents(
        from manufactureDate: Date?,
        now: Date,
        calendar providedCalendar: Calendar? = nil
    ) -> DateComponents? {
        guard let manufactureDate = plausibleManufactureDate(manufactureDate, now: now) else {
            return nil
        }

        let calendar = providedCalendar ?? gregorianUTCCalendar
        let manufactureDay = calendar.startOfDay(for: manufactureDate)
        let nowDay = calendar.startOfDay(for: now)
        guard manufactureDay <= nowDay else {
            return nil
        }

        return calendar.dateComponents([.year, .month, .day], from: manufactureDay, to: nowDay)
    }

    static func displayableBatteryAgeComponents(_ components: DateComponents?) -> DateComponents? {
        guard let components else {
            return nil
        }

        guard (components.year == nil) == (components.month == nil) else {
            return nil
        }

        let years = components.year ?? 0
        let months = components.month ?? 0
        guard years >= 0,
              months >= 0,
              months <= 11,
              (components.day ?? 0) >= 0 else {
            return nil
        }

        return DateComponents(year: years, month: months)
    }

    static func displayableBatteryAgeMonthCount(_ components: DateComponents?) -> Int? {
        guard let components = displayableBatteryAgeComponents(components),
              let years = components.year,
              let months = components.month,
              years <= Int.max / 12 else {
            return nil
        }

        let (yearMonths, multipliedOverflow) = years.multipliedReportingOverflow(by: 12)
        let (totalMonths, addedOverflow) = yearMonths.addingReportingOverflow(months)
        guard !multipliedOverflow, !addedOverflow else {
            return nil
        }

        return totalMonths
    }

    private static func isOnOrAfterMinimumPlausibleManufactureDay(_ date: Date) -> Bool {
        isDate(date, onOrAfter: minimumPlausibleManufactureDateComponents, calendar: gregorianUTCCalendar)
            || isDate(date, onOrAfter: minimumPlausibleManufactureDateComponents, calendar: Calendar(identifier: .gregorian))
    }

    private static func isManufactureDay(_ manufactureDate: Date, onOrBefore now: Date) -> Bool {
        let manufactureDay = gregorianUTCCalendar.startOfDay(for: manufactureDate)
        let nowDay = gregorianUTCCalendar.startOfDay(for: now)
        return manufactureDay <= nowDay
    }

    private static func isDate(
        _ date: Date,
        onOrAfter minimumComponents: DateComponents,
        calendar: Calendar
    ) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let minimumYear = minimumComponents.year,
              let minimumMonth = minimumComponents.month,
              let minimumDay = minimumComponents.day else {
            return false
        }

        if year != minimumYear {
            return year > minimumYear
        }

        if month != minimumMonth {
            return month > minimumMonth
        }

        return day >= minimumDay
    }

    static func temperatureCelsius(fromRaw rawValue: Int?) -> Double? {
        guard let rawValue else {
            return nil
        }

        let candidateCelsius = Double(rawValue) / 100.0
        if isPlausibleTemperatureCelsius(candidateCelsius) {
            return candidateCelsius
        }

        let kelvinTenthsCandidate = (Double(rawValue) / 10.0) - 273.15
        if isPlausibleTemperatureCelsius(kelvinTenthsCandidate) {
            return kelvinTenthsCandidate
        }

        return nil
    }

    static func plausibleTemperatureCelsius(_ value: Double?) -> Double? {
        guard let value,
              isPlausibleTemperatureCelsius(value) else {
            return nil
        }

        return value
    }

    static func isPlausibleTemperatureCelsius(_ value: Double) -> Bool {
        value.isFinite && (-20...120).contains(value)
    }

    static func deriveCurrentChargeMilliampHours(publicPercentage: Double?, fullChargeCapacityMilliampHours: Int?) -> Int? {
        guard let publicPercentage = publicPercentage.flatMap(normalizedPercent),
              let fullChargeCapacityMilliampHours = plausibleCapacityMilliampHours(fullChargeCapacityMilliampHours, allowsZero: false) else {
            return nil
        }

        return Int((publicPercentage / 100 * Double(fullChargeCapacityMilliampHours)).rounded())
    }

    static func derivePowerState(
        isCharging: Bool,
        isCharged: Bool,
        isExternalPowerConnected: Bool,
        signedCurrentMilliamps: Int?,
        currentChargeMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?
    ) -> BatteryPowerState {
        if dischargeRateMilliamps(from: signedCurrentMilliamps) != nil {
            return isExternalPowerConnected ? .connectedDischarging : .onBattery
        }

        if chargeRateMilliamps(from: signedCurrentMilliamps) != nil {
            return .charging
        }

        if isExternalPowerConnected == false {
            return .onBattery
        }

        if isCharging {
            return .charging
        }

        if isCharged {
            return .fullOnAC
        }

        if let currentChargeMilliampHours = plausibleCapacityMilliampHours(currentChargeMilliampHours),
           let fullChargeCapacityMilliampHours = plausibleCapacityMilliampHours(fullChargeCapacityMilliampHours, allowsZero: false) {
            let threshold = max(8, Int(Double(fullChargeCapacityMilliampHours) * 0.01))
            if currentChargeMilliampHours >= fullChargeCapacityMilliampHours - threshold {
                return .fullOnAC
            }
        }

        return isExternalPowerConnected ? .connectedNotCharging : .unknown
    }

    static func normalizedPowerFlags(for powerState: BatteryPowerState) -> (isCharging: Bool, isExternalPowerConnected: Bool) {
        (powerState == .charging, powerState.isExternallyPowered)
    }

    private static func chargeTaperMultiplier(forPercent chargePercent: Double) -> Double {
        switch chargePercent {
        case ..<70:
            return 1.0
        case ..<85:
            return 1.08
        case ..<92:
            return 1.18
        case ..<97:
            return 1.38
        default:
            return 1.75
        }
    }

    private static func normalizedPercent(_ value: Double) -> Double? {
        guard value.isFinite else {
            return nil
        }

        if value < 0 {
            return nil
        }

        if value > 105 {
            return nil
        }

        return max(0, min(100, value))
    }

    private static func shouldPreferCapacityPercent(calculated: Double, publicPercentage: Double) -> Bool {
        if isEmptyPercent(publicPercentage) {
            return calculated > 1
        }

        if isTransientLowPercent(publicPercentage) {
            return calculated > 20
        }

        if isFullPercent(publicPercentage) {
            return isNonExtremePercent(calculated)
        }

        return false
    }

    private static func shouldPreferPublicPercent(calculated: Double, publicPercentage: Double) -> Bool {
        guard isStablePublicPercent(publicPercentage) else {
            return false
        }

        return abs(calculated - publicPercentage) >= 2
    }

    private static func shouldPreferFullPublicPercentWhenCapacityIsEmpty(calculated: Double, publicPercentage: Double) -> Bool {
        isFullPercent(publicPercentage) && isEmptyPercent(calculated)
    }

    private static func isEmptyPercent(_ value: Double) -> Bool {
        value <= 1
    }

    private static func isTransientLowPercent(_ value: Double) -> Bool {
        value <= 10
    }

    private static func isFullPercent(_ value: Double) -> Bool {
        value >= 99
    }

    private static func isStablePublicPercent(_ value: Double) -> Bool {
        !isEmptyPercent(value)
            && !isTransientLowPercent(value)
            && !isFullPercent(value)
    }

    private static func isNonExtremePercent(_ value: Double) -> Bool {
        value > 1 && value < 99
    }

    private static func negativeCurrentMagnitude(_ value: Int?) -> Int? {
        guard let value = plausibleSignedCurrentMilliamps(value),
              value < 0,
              -value > 40 else {
            return nil
        }

        return -value
    }

    private static func isDistinctFromAdapterCapability(_ watts: Double, adapterMaxWatts: Int?) -> Bool {
        guard let adapterMaxWatts = plausibleAdapterWatts(adapterMaxWatts) else {
            return true
        }

        let adapterWatts = Double(adapterMaxWatts)
        let toleranceWatts = max(0.001, adapterWatts * adapterCapabilityEchoTolerance)
        return abs(watts - adapterWatts) > toleranceWatts
    }

    private static func isDistinctFromCounterBackedAdapterCapability(_ watts: Double, adapterMaxWatts: Int?) -> Bool {
        guard let adapterMaxWatts = plausibleAdapterWatts(adapterMaxWatts) else {
            return true
        }

        let adapterWatts = Double(adapterMaxWatts)
        let tolerance = adapterMaxWatts >= 90
            ? highWattageCounterBackedAdapterCapabilityEchoTolerance
            : counterBackedAdapterCapabilityEchoTolerance
        let toleranceWatts = max(0.1, adapterWatts * tolerance)
        return abs(watts - adapterWatts) > toleranceWatts
    }
}
