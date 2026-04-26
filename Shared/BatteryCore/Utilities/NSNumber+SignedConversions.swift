import Foundation

enum SignedIntegerNormalizer {
    static func normalize(_ rawValue: Any?) -> Int? {
        switch rawValue {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(truncatingIfNeeded: value)
        case let value as UInt64:
            return Int(truncatingIfNeeded: Int64(bitPattern: value))
        case let value as UInt:
            return Int(truncatingIfNeeded: value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return nil
            }

            let unsignedValue = value.uint64Value
            if unsignedValue > UInt64(Int64.max) {
                return Int(truncatingIfNeeded: Int64(bitPattern: unsignedValue))
            }

            return Int(truncatingIfNeeded: value.int64Value)
        case let value as String:
            if let signed = Int(value) {
                return signed
            }

            if let unsigned = UInt64(value) {
                return Int(truncatingIfNeeded: Int64(bitPattern: unsigned))
            }

            if let floatingPoint = Double(value) {
                return Int(floatingPoint)
            }

            return nil
        default:
            return nil
        }
    }
}

extension NSNumber {
    var batteryStatsSignedIntValue: Int {
        SignedIntegerNormalizer.normalize(self) ?? intValue
    }
}
