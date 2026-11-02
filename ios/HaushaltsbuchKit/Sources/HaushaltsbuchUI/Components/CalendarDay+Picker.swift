import Foundation
import HaushaltsbuchCore

extension CalendarDay {
    private static var pickerCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Calendar.current.timeZone
        return cal
    }

    /// Mittag des Tages in der Gerätezeitzone, für `DatePicker`.
    static func pickerDate(_ day: CalendarDay) -> Date {
        pickerCalendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date()
    }

    static func from(pickerDate date: Date) -> CalendarDay {
        let c = pickerCalendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: c.year!, month: c.month!, day: c.day!)!
    }
}
