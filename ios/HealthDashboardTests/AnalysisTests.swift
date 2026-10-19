import Foundation
import Testing
@testable import HealthDashboard

private let chicago = TimeZone(identifier: "America/Chicago")!

/// A sleep sample from "YYYY-MM-DD HH:MM" to "YYYY-MM-DD HH:MM", Chicago time.
private func sample(_ start: String, _ end: String) -> SleepSample {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = chicago
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return SleepSample(start: f.date(from: start)!, end: f.date(from: end)!, timeZone: chicago)
}

/// One night from `bed` on `evening` to `wake` the next morning.
private func night(_ evening: String, _ bed: String, _ wake: String) -> SleepSample {
    let morning = Day.shift(evening, 1)
    return sample("\(bed >= "18:00" ? evening : morning) \(bed)", "\(morning) \(wake)")
}

struct SleepTests {
    @Test func afterMidnightBedtimeBelongsToThePreviousEvening() {
        let n = buildNights([night("2026-10-16", "00:35", "08:50")])[0]
        #expect(n.date == "2026-10-16")
        #expect(n.weekday == 5)
        #expect(clockTime(Double(n.bedtime)) == "12:35am")
        #expect(clockTime(Double(n.wake)) == "8:50am")
        #expect(n.wakeDate == "2026-10-17")
        #expect(n.asleepMinutes == 8 * 60 + 15)
    }

    @Test func watchAndPhoneRecordingTheSameSleepIsNotDoubleCounted() {
        let nights = buildNights([night("2026-10-16", "23:30", "07:30"), sample("2026-10-17 00:00", "2026-10-17 07:00")])
        #expect(nights.count == 1)
        #expect(nights[0].asleepMinutes == 8 * 60)
    }

    @Test func shortWakeUpStaysInOneNightButNapsAreIgnored() {
        let nights = buildNights([
            sample("2026-10-16 23:00", "2026-10-17 03:00"),
            sample("2026-10-17 03:20", "2026-10-17 07:00"),
            sample("2026-10-17 14:00", "2026-10-17 15:00"),
        ])
        #expect(nights.count == 1)
        #expect(nights[0].asleepMinutes == 4 * 60 + 3 * 60 + 40)
    }
}

struct WeekendShiftTests {
    @Test func measuresHowFarSleepMovesOnFridayAndSaturday() {
        let samples = (0..<28).map { d -> SleepSample in
            let evening = Day.shift("2026-09-20", d)
            return Day.weekday(evening) >= 5 ? night(evening, "02:00", "10:00") : night(evening, "00:00", "08:00")
        }
        let w = weekendShift(buildNights(samples))!
        #expect(w.midpointShift == 120)
        #expect(clockTime(w.schoolNights.bedtime) == "12:00am")
        #expect(clockTime(w.weekendNights.wake) == "10:00am")
        #expect(w.schoolNights.nights == 20)
        #expect(w.weekendNights.nights == 8)
    }
}

struct LateNightTests {
    @Test func comparesLateNightsWithNormalOnes() {
        var samples: [SleepSample] = []
        var rhr: [String: Double] = [:]
        for d in 0..<30 {
            let evening = Day.shift("2026-09-01", d)
            let late = d % 6 == 0
            samples.append(late ? night(evening, "02:30", "08:30") : night(evening, "00:00", "08:00"))
            rhr[Day.shift(evening, 1)] = late ? 80 : 75
        }
        let c = lateNightCost(buildNights(samples), restingHr: rhr, hrv: [:])!
        #expect(c.lateNights == 5)
        #expect(c.sleepLost == 120)
        #expect(c.nextDay.restingHr == 5)
        #expect(c.nextDay.hrv == nil)
    }
}

struct CalendarTests {
    let ics = """
    BEGIN:VCALENDAR\r
    BEGIN:VEVENT\r
    DTSTART;VALUE=DATE:20261022\r
    SUMMARY:MATH 347 Midterm\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    DTSTART;TZID=America/Chicago:20261020T140000\r
    SUMMARY:CS 225 quiz\\, room 1404\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    DTSTART;TZID=America/Chicago:20260901T090000\r
    RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\r
    SUMMARY:MATH 347 lecture\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    DTSTART:20261101T190000Z\r
    SUMMARY:A very long title that Google folds onto the next li\r
     ne of the file\r
    END:VEVENT\r
    END:VCALENDAR\r
    """

    @Test func readsOneOffEventsUnfoldsLinesAndSkipsRepeats() {
        let events = parseICS(ics, timeZone: chicago)
        #expect(events.map(\.title) == [
            "CS 225 quiz, room 1404",
            "MATH 347 Midterm",
            "A very long title that Google folds onto the next line of the file",
        ])
        #expect(events[0].date == "2026-10-20")
        #expect(events[0].minutes == 14 * 60)
        #expect(events[1].minutes == nil)
        // 19:00 UTC on Nov 1 is 1pm in Chicago (after the clocks change).
        #expect(events[2].minutes == 13 * 60)
    }

    @Test func readsGoogleEventsSkippingRepeatsAndCancelled() {
        let page: [String: Any] = ["items": [
            ["summary": "MATH 347 Midterm", "start": ["date": "2026-10-22"]],
            ["summary": "CS 225 quiz", "start": ["dateTime": "2026-10-20T19:00:00Z"]],
            ["summary": "Lecture", "recurringEventId": "abc", "start": ["dateTime": "2026-10-20T14:00:00-05:00"]],
            ["summary": "Old exam", "status": "cancelled", "start": ["date": "2026-10-01"]],
        ]]
        let events = googleEvents(page, timeZone: chicago)
        #expect(events.map(\.title) == ["MATH 347 Midterm", "CS 225 quiz"])
        #expect(events[0].minutes == nil)
        #expect(events[1].date == "2026-10-20")
        #expect(events[1].minutes == 14 * 60) // 19:00 UTC is 2pm in Chicago
    }

    @Test func matchesExamWordsAsWholeWords() {
        #expect(isExam("MATH 347 Midterm"))
        #expect(isExam("Finals week study group"))
        #expect(!isExam("Examine lab results"))
        #expect(!isExam("Quizlet session"))
    }

    @Test func comparesTheSixNightsBeforeExamsWithOtherNights() {
        let exams = ["2026-09-20", "2026-10-11"]
        let nights = (0..<56).map { d -> Night in
            let date = Day.shift("2026-08-30", d)
            let before = exams.contains { date < $0 && Day.shift(date, 6) >= $0 }
            return Night(date: date, weekday: 0, bedtime: before ? 420 : 360, wake: 840, asleepMinutes: before ? 360 : 480, wakeDate: Day.shift(date, 1))
        }
        let lens = examWeekLens(nights, restingHr: [:], hrv: [:], examDates: exams)!
        #expect(lens.exams == 2)
        #expect(lens.examWeeks.nights == 12)
        #expect(lens.examWeeks.asleepMinutes == 360)
        #expect(lens.normalWeeks.asleepMinutes == 480)
        #expect(lens.normalWeeks.nights == 56 - 12 - 2)
    }
}
