import Foundation

enum SignedIntegerNormalizer {
    static func normalize(_ rawValue: Any?) -> Int? {
        switch rawValue {
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return nil
            }

            let numericType = String(cString: value.objCType)
            if numericType == "f" || numericType == "d" {
                return normalizeFloatingPoint(value.doubleValue)
            }

            let unsignedValue = value.uint64Value
            if unsignedValue > UInt64(Int64.max) {
                return Int(truncatingIfNeeded: Int64(bitPattern: unsignedValue))
            }

            return Int(truncatingIfNeeded: value.int64Value)
        case let value as Int:
            return value
        case let value as Int64:
            return Int(truncatingIfNeeded: value)
        case let value as Double:
            return normalizeFloatingPoint(value)
        case let value as Float:
            return normalizeFloatingPoint(Double(value))
        case let value as UInt64:
            return Int(truncatingIfNeeded: Int64(bitPattern: value))
        case let value as UInt:
            return Int(truncatingIfNeeded: value)
        case let value as String:
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedValue.isEmpty == false else {
                return nil
            }

            if let signed = Int(trimmedValue) {
                return signed
            }

            if let unsigned = UInt64(trimmedValue) {
                return Int(truncatingIfNeeded: Int64(bitPattern: unsigned))
            }

            if let floatingPoint = Double(trimmedValue) {
                return normalizeFloatingPoint(floatingPoint)
            }

            return nil
        default:
            return nil
        }
    }

    private static func normalizeFloatingPoint(_ value: Double) -> Int? {
        guard value.isFinite,
              value.rounded(.towardZero) == value,
              value >= Double(Int.min),
              value <= Double(Int.max) else {
            return nil
        }

        return Int(value)
    }
}

enum BooleanFlagNormalizer {
    static func normalize(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }

            let numericValue = number.doubleValue
            if numericValue == 0 || numericValue == 1 {
                return numericValue == 1
            }

            return nil
        }

        return value as? Bool
    }
}
