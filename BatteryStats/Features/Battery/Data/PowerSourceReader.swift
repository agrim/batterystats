import Foundation
import IOKit.ps

final class PowerSourceReader: @unchecked Sendable {
    final class NotificationToken {
        static let runLoopMode: CFRunLoopMode = .commonModes

        private final class CallbackBox {
            let handler: @Sendable () -> Void

            init(handler: @escaping @Sendable () -> Void) {
                self.handler = handler
            }
        }

        private let callbackBox: Unmanaged<CallbackBox>
        private let runLoopSource: CFRunLoopSource

        init?(handler: @escaping @Sendable () -> Void) {
            let callbackBox = Unmanaged.passRetained(CallbackBox(handler: handler))
            self.callbackBox = callbackBox

            guard let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else {
                    return
                }

                let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
                box.handler()
            }, callbackBox.toOpaque()) else {
                callbackBox.release()
                return nil
            }

            let sourceReference = source.takeRetainedValue()
            self.runLoopSource = sourceReference
            CFRunLoopAddSource(CFRunLoopGetMain(), sourceReference, Self.runLoopMode)
        }

        deinit {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, Self.runLoopMode)
            callbackBox.release()
        }
    }

    func makeNotificationToken(handler: @escaping @Sendable () -> Void) -> NotificationToken? {
        NotificationToken(handler: handler)
    }

    func read() -> PublicPowerSourceSnapshot? {
        guard let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return nil
        }

        guard let powerSourceList = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as? [AnyObject] else {
            return nil
        }

        let descriptions = powerSourceList.compactMap { source -> [String: Any]? in
            guard let description = IOPSGetPowerSourceDescription(powerSourceInfo, source)?.takeUnretainedValue() as? [String: Any] else {
                return nil
            }

            return description
        }

        return Self.snapshot(from: descriptions)
    }

    static func snapshot(from descriptions: [[String: Any]]) -> PublicPowerSourceSnapshot? {
        guard let powerSource = descriptions.first(where: {
            isInternalBatteryDescription($0) && isPresentDescription($0)
        }) ?? descriptions.first(where: {
            isPresentDescription($0)
        }) ?? descriptions.first(where: {
            isInternalBatteryDescription($0)
        }) ?? descriptions.first else {
            return nil
        }

        let isInternalBattery = isInternalBatteryDescription(powerSource)

        let currentCapacity = BatteryCalculations.plausibleCapacityMilliampHours(
            SignedIntegerNormalizer.normalize(powerSource[string(for: kIOPSCurrentCapacityKey)])
        )
        let maxCapacity = BatteryCalculations.plausibleCapacityMilliampHours(
            SignedIntegerNormalizer.normalize(powerSource[string(for: kIOPSMaxCapacityKey)]),
            allowsZero: false
        )
        let stateOfChargePercent: Double? = {
            guard let currentCapacity, let maxCapacity else {
                return nil
            }

            let percent = (Double(currentCapacity) / Double(maxCapacity)) * 100
            guard percent.isFinite, percent >= 0, percent <= 105 else {
                return nil
            }

            return min(100, percent)
        }()

        let isCharging = BooleanFlagNormalizer.normalize(powerSource[string(for: kIOPSIsChargingKey)]) ?? false
        let isCharged = BooleanFlagNormalizer.normalize(powerSource[string(for: kIOPSIsChargedKey)]) ?? false
        let powerSourceState = powerSource[string(for: kIOPSPowerSourceStateKey)] as? String
        let isExplicitlyOnBattery = matchesPowerSourceState(powerSourceState, string(for: kIOPSBatteryPowerValue))
        let isExternalPowerConnected = isExplicitlyOnBattery
            ? false
            : matchesPowerSourceState(powerSourceState, string(for: kIOPSACPowerValue)) || isCharging || isCharged

        return PublicPowerSourceSnapshot(
            isPresent: BooleanFlagNormalizer.normalize(powerSource[string(for: kIOPSIsPresentKey)]) ?? true,
            isCharging: isCharging,
            isCharged: isCharged,
            isExternalPowerConnected: isExternalPowerConnected,
            isInternalBattery: isInternalBattery,
            stateOfChargePercent: stateOfChargePercent,
            systemTimeRemainingMinutes: plausibleDurationMinutes(powerSource[string(for: kIOPSTimeToEmptyKey)]),
            timeToFullMinutes: plausibleDurationMinutes(powerSource[string(for: kIOPSTimeToFullChargeKey)]),
            powerSourceState: powerSourceState,
            rawDescription: powerSource
        )
    }

    private static func string(for pointer: UnsafePointer<CChar>) -> String {
        String(cString: pointer)
    }

    private static func matchesPowerSourceState(_ value: String?, _ expectedValue: String) -> Bool {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(expectedValue) == .orderedSame
    }

    private static func isInternalBatteryDescription(_ description: [String: Any]) -> Bool {
        let type = normalizedIdentifier(description[string(for: kIOPSTypeKey)] as? String)
        let transportType = normalizedIdentifier(description[string(for: kIOPSTransportTypeKey)] as? String)

        return type == normalizedIdentifier(string(for: kIOPSInternalBatteryType))
            || type == "internalbattery"
            || transportType == normalizedIdentifier(string(for: kIOPSInternalType))
            || transportType == "internal"
    }

    private static func isPresentDescription(_ description: [String: Any]) -> Bool {
        BooleanFlagNormalizer.normalize(description[string(for: kIOPSIsPresentKey)]) ?? true
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? nil : normalized
    }

    private static func plausibleDurationMinutes(_ value: Any?) -> Int? {
        BatteryCalculations.plausibleDurationMinutes(SignedIntegerNormalizer.normalize(value))
    }

}
