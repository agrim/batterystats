import Foundation

enum ManufactureDateDecoder {
    private static let minimumSupportedYear = 2006
    private static let gregorianUTCCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static func decode(
        rawValue: Int?,
        calendar providedCalendar: Calendar? = nil,
        latestDate: Date = Date()
    ) -> Date? {
        guard let rawValue else {
            return nil
        }

        guard (1...Int(UInt16.max)).contains(rawValue) else {
            return nil
        }

        let day = rawValue & 0x1F
        let month = (rawValue >> 5) & 0x0F
        let year = 1980 + ((rawValue >> 9) & 0x7F)

        guard year >= minimumSupportedYear,
              (1...31).contains(day),
              (1...12).contains(month) else {
            return nil
        }

        let calendar = providedCalendar ?? gregorianUTCCalendar
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }

        let decodedComponents = calendar.dateComponents([.year, .month, .day], from: date)
        guard decodedComponents.year == year,
              decodedComponents.month == month,
              decodedComponents.day == day else {
            return nil
        }

        let decodedDay = calendar.startOfDay(for: date)
        let latestDay = calendar.startOfDay(for: latestDate)
        guard decodedDay <= latestDay else {
            return nil
        }

        return date
    }

}
