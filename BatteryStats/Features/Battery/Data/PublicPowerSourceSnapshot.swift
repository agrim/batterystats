import Foundation

struct PublicPowerSourceSnapshot {
    let isPresent: Bool
    let isCharging: Bool
    let isCharged: Bool
    let isExternalPowerConnected: Bool
    let isInternalBattery: Bool
    let stateOfChargePercent: Double?
    let systemTimeRemainingMinutes: Int?
    let timeToFullMinutes: Int?
    let powerSourceState: String?
    let rawDescription: [String: Any]
}
