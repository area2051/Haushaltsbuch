import Foundation

/// Kalendertag ohne Uhrzeit/Zeitzone (Jahr, Monat, Tag). Stringform `YYYY-MM-DD`.
public struct CalendarDay: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Liefert `nil` für ungültige Kalendertage (z. B. 2026-02-29).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              day >= 1, day <= Self.daysIn(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Strikt `YYYY-MM-DD` (4-2-2 Ziffern), sonst `nil`.
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var monthKey: MonthKey { MonthKey(year: year, month: month) }

    /// „Heute“ in der Zeitzone des übergebenen Kalenders.
    public static func today(calendar: Calendar = .current, now: Date = Date()) -> CalendarDay {
        let c = gregorian(timeZone: calendar.timeZone).dateComponents([.year, .month, .day], from: now)
        return CalendarDay(year: c.year!, month: c.month!, day: c.day!)!
    }

    /// Gregorianischer Kalender in der Zeitzone des Geräte-Kalenders (unabhängig von dessen Kalendersystem).
    private static func gregorian(timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// Verschiebt um ganze Tage (negativ = zurück).
    public func adding(days: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> CalendarDay {
        let cal = Self.gregorian(timeZone: calendar.timeZone)
        let base = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        let moved = cal.date(byAdding: .day, value: days, to: base)!
        let c = cal.dateComponents([.year, .month, .day], from: moved)
        return CalendarDay(year: c.year!, month: c.month!, day: c.day!)!
    }

    public static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // MARK: Codable (als String)

    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = CalendarDay(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Ungültiger Kalendertag: \(s)"))
        }
        self = d
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }

    static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// Jahr + Monat.
public struct MonthKey: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public func adding(months: Int) -> MonthKey {
        let index = year * 12 + (month - 1) + months
        let y = Int((Double(index) / 12).rounded(.down))
        return MonthKey(year: y, month: index - y * 12 + 1)
    }

    public func contains(_ d: CalendarDay) -> Bool {
        d.year == year && d.month == month
    }

    /// Z. B. „November 2026“, „März 2026“.
    public var title: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))!
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }

    public static func < (a: MonthKey, b: MonthKey) -> Bool {
        (a.year, a.month) < (b.year, b.month)
    }
}
