import Foundation
import Testing
@testable import HealthDashboard

private func night(_ date: String, bed: Int = 360, wake: Int = 840, asleep: Int = 480) -> Night {
    Night(date: date, weekday: Day.weekday(date), bedtime: bed, wake: wake, asleepMinutes: asleep, wakeDate: Day.shift(date, 1))
}

struct RecoveryTests {
    @Test func typicalDayScoresAround80AndDipsAfterAShortNight() {
        let today = "2026-10-18"
        var nights: [Night] = [], rhr: [String: Double] = [:], hrv: [String: Double] = [:]
        for back in 1...40 {
            let d = Day.shift(today, -back)
            nights.append(night(d, asleep: back == 1 ? 360 : 480))
            rhr[Day.shift(d, 1)] = back == 1 ? 72 : 66
            hrv[Day.shift(d, 1)] = back == 1 ? 40 : 50
        }
        nights.sort { $0.date < $1.date }
        let days = recoveryDays(nights, restingHr: rhr, hrv: hrv, days: 2, today: today)
        #expect(days.first?.score == 80)
        let todayScore = days.last!
        #expect(todayScore.date == today)
        #expect(todayScore.score < 60)
        #expect(todayScore.restingHrChange == 6)
        #expect(todayScore.reason.hasPrefix("Mostly"))
    }

    @Test func steadyBedtimesScoreHigherThanSwingingOnes() {
        let steady = (0..<14).map { night(Day.shift("2026-10-01", $0), bed: 360 + ($0 % 2) * 20) }
        let swinging = (0..<14).map { night(Day.shift("2026-10-01", $0), bed: 300 + ($0 % 2) * 150, wake: 800 + ($0 % 2) * 150) }
        #expect(sleepRegularity(steady, today: "2026-10-15")! > 85)
        #expect(sleepRegularity(swinging, today: "2026-10-15")! < 40)
        // Nights days apart aren't compared.
        let gappy = (0..<14).map { night(Day.shift("2026-10-01", $0 * 2)) }
        #expect(sleepRegularity(gappy, today: "2026-10-30") == nil)
    }
}

struct FitnessAndCaffeineTests {
    @Test func fitnessAgeFollowsTypicalValuesForWomen() {
        #expect(fitnessAge(vo2Max: 38) == 20)
        #expect(fitnessAge(vo2Max: 32) == 40)
        #expect(fitnessAge(vo2Max: 60) == 18)
    }

    @Test func caffeineNoteOnlyAppearsPast400() {
        #expect(caffeineLimitNote(400) == nil)
        #expect(caffeineLimitNote(500)?.contains("500 mg") == true)
    }

    @Test func caffeineHalvesEveryFiveHours() {
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let logs = [Reading(date: morning, value: 130)]
        #expect(abs(caffeineLeft(logs, at: morning.addingTimeInterval(5 * 3600)) - 65) < 0.01)
        #expect(caffeineLeft(logs, at: morning.addingTimeInterval(-60)) == 0)
    }
}

struct CycleTests {
    @Test func flowDaysGroupIntoPeriodsAndCycles() {
        var flow: [String: Int] = [:]
        for start in ["2026-08-01", "2026-08-29", "2026-09-28"] { for k in 0..<5 { flow[Day.shift(start, k)] = 3 } }
        flow["2026-08-07"] = 2 // light bleeding 2 days after still belongs to that period
        let ps = periods(flow)
        #expect(ps.count == 3)
        #expect(ps[0].end == "2026-08-07")
        #expect(cycleLengths(ps) == [28, 30])
        let status = cycleStatus(flow, wristTemp: [:], predict: true, today: "2026-10-10")!
        #expect(status.day == 13)
        #expect(status.typicalLength == 29)
        #expect(status.nextStart == "2026-10-27")
        #expect(status.phase == .follicular)
    }

    @Test func irregularCyclesGetNoPrediction() {
        var flow: [String: Int] = [:]
        for start in ["2026-05-01", "2026-06-02", "2026-07-20", "2026-08-18"] { flow[start] = 3 }
        #expect(cycleStatus(flow, wristTemp: [:], predict: true, today: "2026-09-01")!.nextStart == nil)
    }

    @Test func threeOverSixFindsTheTemperatureRise() {
        var temp: [String: Double] = [:]
        for d in 0..<28 { temp[Day.shift("2026-09-01", d)] = d < 15 ? 34.5 : 34.8 }
        #expect(temperatureShift(temp, from: "2026-09-01", to: "2026-09-28") == 15)
    }

    @Test func packDayWrapsEvery28Days() {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        #expect(packStatus(packStart: start, today: "2026-09-16")!.day == 16)
        #expect(packStatus(packStart: start, today: "2026-09-29")!.day == 1)
        #expect(packStatus(packStart: start, today: "2026-09-25")!.isBreakWeek)
    }
}

struct WellbeingTests {
    @Test func sickNeedsThreeSignalsMovingTogether() {
        var data = HealthData()
        let today = "2026-10-18"
        for back in 0...30 {
            let d = Day.shift(today, -back)
            let ill = back <= 1
            data.restingHr[d] = ill ? 72 : 66
            data.hrv[d] = ill ? 38 : 50
            data.wristTemp[d] = ill ? 35.2 : 34.6
            data.respiratory[d] = 14
        }
        let s = sickSignals(data, lutealAdjust: false, today: today)!
        #expect(s.count == 3)
        #expect(s.breathing == nil)
        // In the luteal phase the same temperature rise is partly expected, so only 2 signals remain.
        data.wristTemp[today] = 34.95; data.wristTemp[Day.shift(today, -1)] = 34.95
        #expect(sickSignals(data, lutealAdjust: true, today: today) == nil)
    }

    @Test func streaksCountBackFromYesterdayWhenTodayIsntDoneYet() {
        let days: Set<String> = ["2026-10-15", "2026-10-16", "2026-10-17"]
        #expect(streak(endingAt: "2026-10-18") { days.contains($0) } == 3)
        #expect(streak(endingAt: "2026-10-20") { days.contains($0) } == 0)
    }
}


struct BugFixTests {
    @Test func spottingNeverCountsAsAPeriod() {
        var flow: [String: Int] = [:]
        for k in 0..<5 { flow[Day.shift("2026-09-01", k)] = 3 }
        flow["2026-09-14"] = 1 // spotting mid-cycle
        for k in 0..<5 { flow[Day.shift("2026-09-29", k)] = 3 }
        #expect(periods(flow).count == 2)
        #expect(cycleLengths(periods(flow)) == [28])
    }

    @Test func aFewUnloggedDaysDontStartANewPeriod() {
        let flow = ["2026-09-01": 3, "2026-09-02": 3, "2026-09-06": 2]
        #expect(periods(flow).count == 1)
        #expect(!startsNewPeriod("2026-09-06", flow: flow))
        #expect(startsNewPeriod("2026-09-29", flow: flow))
    }

    @Test func shortCyclesDontCrashThePhasePage() {
        var data = HealthData()
        for start in ["2026-08-01", "2026-08-16", "2026-08-31"] { for k in 0..<3 { data.flow[Day.shift(start, k)] = 3 } }
        #expect(phaseStats(data).isEmpty)
    }

    @Test func oneCompleteCycleIsUsedForThePrediction() {
        let flow = ["2026-08-01": 3, "2026-09-05": 3]
        let c = cycleStatus(flow, wristTemp: [:], predict: true, today: "2026-09-10")!
        #expect(c.typicalLength == 35)
        #expect(c.nextStart == "2026-10-10")
    }

    @Test func afterMidnightBelongsToLastNight() {
        let chicago = TimeZone(identifier: "America/Chicago")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = chicago
        let oneAM = cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 1, minute: 30))!
        #expect(Day.evening(oneAM, in: chicago) == "2026-10-17")
        #expect(Day.eveningHour(oneAM, in: chicago) == 25.5)
    }

    @Test func allNightersCountButAfternoonNapsDont() {
        let chicago = TimeZone(identifier: "America/Chicago")!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = chicago; f.dateFormat = "yyyy-MM-dd HH:mm"
        let short = SleepSample(start: f.date(from: "2026-10-17 05:00")!, end: f.date(from: "2026-10-17 07:00")!, timeZone: chicago)
        let nap = SleepSample(start: f.date(from: "2026-10-17 13:00")!, end: f.date(from: "2026-10-17 16:30")!, timeZone: chicago)
        let nights = buildNights([short, nap])
        #expect(nights.count == 1)
        #expect(nights[0].date == "2026-10-16")
        #expect(nights[0].asleepMinutes == 120)
    }

    @Test func cutoffTestPutsLateNightCaffeineAfter3pm() {
        let chicago = TimeZone(identifier: "America/Chicago")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = chicago
        var logs: [Reading] = [], nights: [Night] = []
        for d in 0..<3 {
            let evening = Day.shift("2026-10-01", d)
            let next = Day.shift(evening, 1).split(separator: "-").compactMap { Int($0) }
            logs.append(Reading(date: cal.date(from: DateComponents(year: next[0], month: next[1], day: next[2], hour: 1))!, value: 80))
            nights.append(Night(date: evening, weekday: 0, bedtime: 500, wake: 900, asleepMinutes: 300, wakeDate: Day.shift(evening, 1)))
        }
        let test = cutoffTest(logs, nights: nights, today: "2026-10-05")
        #expect(test.daysLogged == 3)
        #expect(test.buckets.map(\.label) == ["After 3pm"])
    }
}
