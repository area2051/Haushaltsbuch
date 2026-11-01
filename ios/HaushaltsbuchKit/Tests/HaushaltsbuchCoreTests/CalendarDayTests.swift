import Foundation
import Testing
@testable import HaushaltsbuchCore

@Test func calendarDayParsesAndRejects() {
    #expect(CalendarDay(string: "2026-02-29") == nil)
    #expect(CalendarDay(string: "2028-02-29") == CalendarDay(year: 2028, month: 2, day: 29))
    #expect(CalendarDay(string: "2026-1-5") == nil)
    #expect(CalendarDay(string: "2026-13-01") == nil)
    #expect(CalendarDay(string: "") == nil)
    #expect(CalendarDay(string: "2026-11-01 ") == nil)
}

@Test func calendarDayStringRoundTripAndOrdering() throws {
    let d = try #require(CalendarDay(string: "2026-03-05"))
    #expect(d.string == "2026-03-05")
    #expect(d < CalendarDay(year: 2026, month: 3, day: 6)!)
    #expect(d < CalendarDay(year: 2026, month: 4, day: 1)!)
    #expect(d < CalendarDay(year: 2027, month: 1, day: 1)!)
    #expect(d.monthKey == MonthKey(year: 2026, month: 3))
}

@Test func calendarDayCodableAsString() throws {
    let d = CalendarDay(year: 2026, month: 11, day: 1)!
    let data = try JSONEncoder().encode(d)
    #expect(String(data: data, encoding: .utf8) == "\"2026-11-01\"")
    #expect(try JSONDecoder().decode(CalendarDay.self, from: data) == d)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(CalendarDay.self, from: Data("\"2026-02-30\"".utf8)) }
}

@Test func calendarDayTodayUsesCalendarTimeZone() {
    var cal = Calendar(identifier: .gregorian)
    // 2026-11-01 23:30 UTC ist in Berlin (UTC+1) bereits der 2.11., in New York (UTC-4/5) noch der 1.11.
    let now = Date(timeIntervalSince1970: 1_793_575_800)
    cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
    #expect(CalendarDay.today(calendar: cal, now: now) == CalendarDay(year: 2026, month: 11, day: 2))
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    #expect(CalendarDay.today(calendar: cal, now: now) == CalendarDay(year: 2026, month: 11, day: 1))
}

@Test func calendarDayDaysBetween() {
    let a = CalendarDay(year: 2026, month: 11, day: 1)!
    #expect(a.adding(days: -90, calendar: Calendar(identifier: .gregorian)) == CalendarDay(year: 2026, month: 8, day: 3))
}

@Test func monthKeyTitleGerman() {
    #expect(MonthKey(year: 2026, month: 3).title == "März 2026")
    #expect(MonthKey(year: 2026, month: 11).title == "November 2026")
}

@Test func monthKeyAddingAcrossYear() {
    #expect(MonthKey(year: 2026, month: 12).adding(months: 1) == MonthKey(year: 2027, month: 1))
    #expect(MonthKey(year: 2026, month: 1).adding(months: -1) == MonthKey(year: 2025, month: 12))
    #expect(MonthKey(year: 2026, month: 5).adding(months: 0) == MonthKey(year: 2026, month: 5))
    #expect(MonthKey(year: 2026, month: 11) < MonthKey(year: 2027, month: 1))
}

@Test func monthKeyContains() {
    let m = MonthKey(year: 2026, month: 2)
    #expect(m.contains(CalendarDay(year: 2026, month: 2, day: 28)!))
    #expect(!m.contains(CalendarDay(year: 2026, month: 3, day: 1)!))
    #expect(!m.contains(CalendarDay(year: 2025, month: 2, day: 1)!))
}
