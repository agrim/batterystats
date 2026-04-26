import Foundation

enum ManufactureDateDecoder {
    static func decode(rawValue: Int?, calendar: Calendar = .current) -> Date? {
        guard let rawValue else {
            return nil
        }

        let day = rawValue & 0x1F
        let month = (rawValue >> 5) & 0x0F
        let year = 1980 + ((rawValue >> 9) & 0x7F)

        guard (1...31).contains(day), (1...12).contains(month) else {
            return nil
        }

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
