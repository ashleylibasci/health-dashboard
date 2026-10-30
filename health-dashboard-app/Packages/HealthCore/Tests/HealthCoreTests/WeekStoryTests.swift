import XCTest
@testable import HealthCore

/// Saved-ideas build (Oct 29): "Your week" as a story (D-P1).
final class WeekStoryTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    // D-P1: best night, energy split, caffeine habit.
    func testWeekStory() {
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        func day(_ i: Int, energy: Int, asleep: Int, bed: Int, mg: Int, last: Int?) -> DaySummary {
            DaySummary(date: cal.date(byAdding: .day, value: i, to: monday)!, energy: energy, asleep: asleep, bedtime: bed,
                       wake: 480, wokeFromLightSleep: true, daylightMinutes: 20, caffeineMg: mg, lastCaffeine: last)
        }
        let days = [day(0, energy: 70, asleep: 420, bed: 30, mg: 130, last: 570),
                    day(1, energy: 78, asleep: 483, bed: 5, mg: 130, last: 580),
                    day(2, energy: 66, asleep: 483, bed: 20, mg: 210, last: 910),
                    day(3, energy: 64, asleep: 400, bed: 60, mg: 0, last: nil),
                    day(4, energy: 60, asleep: 380, bed: 90, mg: 250, last: 960),
                    day(5, energy: 50, asleep: 470, bed: 120, mg: 70, last: 750),
                    day(6, energy: 54, asleep: 470, bed: 100, mg: 0, last: nil)]
        let s = WeekStory.make(days: days, cutoff: 840, calendar: cal)!
        XCTAssertEqual(s.bestNight.date, days[1].date)          // tie on 483: the earlier bedtime
        XCTAssertEqual(s.bestDay.date, days[1].date)
        XCTAssertEqual(s.lowestDay.date, days[5].date)
        XCTAssertEqual(s.weekdayEnergy, 68)
        XCTAssertEqual(s.weekendEnergy, 52)
        XCTAssertEqual(s.caffeine.days, 5)
        XCTAssertEqual(s.caffeine.averageMg, 158)
        XCTAssertEqual(s.caffeine.typicalLast, 750)
        XCTAssertEqual(s.caffeine.daysAfterCutoff, 2)
        XCTAssertNil(WeekStory.make(days: Array(days.prefix(2)), cutoff: nil, calendar: cal))
        XCTAssertNil(WeekStory.make(days: Array(days.prefix(4)), cutoff: nil, calendar: cal)?.weekendEnergy)
    }

    // D-P1: the pack card's week, and what comes next.
    func testPackWeek() {
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let pack = PillPack(start: start, activeDays: 21, packLength: 28)
        let today = cal.date(byAdding: .day, value: 17, to: start)!            // pill 18
        let days = (1...7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }   // pills 11–17
        let w = PackWeek.make(pack: pack, days: days, today: today, taken: { cal.component(.day, from: $0) != 11 }, calendar: cal)!
        XCTAssertEqual(w.firstDay, 11)
        XCTAssertEqual(w.lastDay, 17)
        XCTAssertEqual(w.pillDays, 7)
        XCTAssertEqual(w.taken, 6)
        XCTAssertEqual(w.breakDays, 0)
        XCTAssertEqual(w.next?.kind, .breakStarts)
        XCTAssertEqual(w.next?.date, cal.date(byAdding: .day, value: 21, to: start))
        // In the break: the new pack is next.
        let inBreak = cal.date(byAdding: .day, value: 24, to: start)!
        let breakDays = (1...7).reversed().map { cal.date(byAdding: .day, value: -$0, to: inBreak)! }
        let b = PackWeek.make(pack: pack, days: breakDays, today: inBreak, taken: { _ in true }, calendar: cal)!
        XCTAssertEqual(b.breakDays, 3)
        XCTAssertEqual(b.next?.kind, .newPack)
    }
}
