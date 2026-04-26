import Foundation
import IOKit.ps
import OSLog

final class PowerSourceReader {
    final class NotificationToken {
        private final class CallbackBox {
            let handler: () -> Void

            init(handler: @escaping () -> Void) {
                self.handler = handler
            }
        }

        private let callbackBox: Unmanaged<CallbackBox>
        private let runLoopSource: CFRunLoopSource

        init?(handler: @escaping () -> Void) {
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
            CFRunLoopAddSource(CFRunLoopGetMain(), sourceReference, .defaultMode)
        }

        deinit {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            callbackBox.release()
        }
    }

    func makeNotificationToken(handler: @escaping () -> Void) -> NotificationToken? {
        NotificationToken(handler: handler)
    }

    func read() -> PublicPowerSourceSnapshot? {
        guard let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            Logger.powerSource.debug("Power source info unavailable")
            return nil
        }

        let powerSourceList = IOPSCopyPowerSourcesList(powerSourceInfo).takeRetainedValue() as Array
        let descriptions = powerSourceList.compactMap { source -> [String: Any]? in
            guard let description = IOPSGetPowerSourceDescription(powerSourceInfo, source)?.takeUnretainedValue() as? [String: Any] else {
                return nil
            }

            return description
        }

        let internalBattery = descriptions.first { description in
            let type = description[string(for: kIOPSTypeKey)] as? String
            let transportType = description[string(for: kIOPSTransportTypeKey)] as? String
            return type == string(for: kIOPSInternalBatteryType) || transportType == string(for: kIOPSInternalType)
        } ?? descriptions.first

        guard let internalBattery else {
            return nil
        }

        let currentCapacity = SignedIntegerNormalizer.normalize(internalBattery[string(for: kIOPSCurrentCapacityKey)])
        let maxCapacity = SignedIntegerNormalizer.normalize(internalBattery[string(for: kIOPSMaxCapacityKey)])
        let stateOfChargePercent: Double? = {
            guard let currentCapacity, let maxCapacity, maxCapacity > 0 else {
                return nil
            }

            return (Double(currentCapacity) / Double(maxCapacity)) * 100
        }()

        return PublicPowerSourceSnapshot(
            isPresent: (internalBattery[string(for: kIOPSIsPresentKey)] as? Bool) ?? true,
            isCharging: (internalBattery[string(for: kIOPSIsChargingKey)] as? Bool) ?? false,
            isCharged: (internalBattery[string(for: kIOPSIsChargedKey)] as? Bool) ?? false,
            isExternalPowerConnected: (internalBattery[string(for: kIOPSPowerSourceStateKey)] as? String) == string(for: kIOPSACPowerValue),
            isInternalBattery: true,
            stateOfChargePercent: stateOfChargePercent,
            systemTimeRemainingMinutes: SignedIntegerNormalizer.normalize(internalBattery[string(for: kIOPSTimeToEmptyKey)]),
            timeToFullMinutes: SignedIntegerNormalizer.normalize(internalBattery[string(for: kIOPSTimeToFullChargeKey)]),
            powerSourceState: internalBattery[string(for: kIOPSPowerSourceStateKey)] as? String,
            rawDescription: internalBattery
        )
    }

    private func string(for pointer: UnsafePointer<CChar>) -> String {
        String(cString: pointer)
    }
}
