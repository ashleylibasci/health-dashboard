import Foundation

/// One day's recovery score and what moved it.
struct RecoveryDay: Equatable {
    var date: String
    /// 1–99. Around 80 is a typical day for you.
    var score: Int
    /// HRV vs. your 4-week normal, as a fraction (−0.15 = 15% lower).
    var hrvChange: Double?
    /// Resting HR vs. your 4-week normal, in bpm.
    var restingHrChange: Double?
    /// Last night's sleep vs. your typical night, in minutes.
    var sleepChange: Double?
    /// Whether the night before started after 2am.
    var afterLateNight: Bool

    var label: String { score >= 75 ? "Good" : score >= 50 ? "Moderate" : "Low" }

    /// The biggest thing pulling the score down (or up), in plain words.
    var reason: String {
        let parts: [(String, Double)] = [
            ("a short night", min(0, (sleepChange ?? 0) / 60 * 6)),
            ("lower HRV than usual", min(0, (hrvChange ?? 0) * 80)),
            ("a higher resting heart rate", min(0, -(restingHrChange ?? 0) * 2.5)),
        ]
        if let worst = parts.min(by: { $0.1 < $1.1 }), worst.1 <= -3 {
            return score >= 75 ? "Close to your normal, with \(worst.0) pulling it down a little." : "Mostly \(worst.0)."
        }
        return score >= 80 ? "Your heart and sleep both look like your normal or better." : "Nothing big stands out; a few small dips added up."
    }
}

/// Typical night length over the 4 weeks before `date`, in minutes.
func typicalSleep(_ nights: [Night], before date: String) -> Double? {
    median(nights.filter { (1...28).contains(Day.between($0.date, date)) }.map { Double($0.asleepMinutes) })
}

/// Recovery for each of the last `days` days that have enough history behind them.
/// Each day is compared with the 28 days before it, so the score is always "vs. your normal".
func recoveryDays(_ nights: [Night], restingHr: [String: Double], hrv: [String: Double], days: Int = 14, today: String = Day.key(.now)) -> [RecoveryDay] {
    let byWake = Dictionary(nights.map { ($0.wakeDate, $0) }, uniquingKeysWith: { a, _ in a })
    return (0..<days).reversed().compactMap { back in
        let day = Day.shift(today, -back)
        func baseline(_ series: [String: Double]) -> Double? {
            let past = (1...28).compactMap { series[Day.shift(day, -$0)] }
            return past.count >= 7 ? median(past) : nil
        }
        let night = byWake[day]
        let hrvBase = baseline(hrv), rhrBase = baseline(restingHr)
        let hrvChange = zip2(hrv[day], hrvBase).map { $0 / $1 - 1 }
        let rhrChange = zip2(restingHr[day], rhrBase).map { $0 - $1 }
        let sleepChange = zip2(night.map { Double($0.asleepMinutes) }, night.flatMap { typicalSleep(nights, before: $0.date) }).map { $0 - $1 }
        guard hrvChange != nil || rhrChange != nil, sleepChange != nil || night == nil else { return nil }

        var score = 80.0
        score += max(-25, min(15, (hrvChange ?? 0) * 80))
        score += max(-20, min(10, -(rhrChange ?? 0) * 2.5))
        score += max(-20, min(8, (sleepChange ?? 0) / 60 * 6))
        return RecoveryDay(
            date: day,
            score: Int(max(1, min(99, score)).rounded()),
            hrvChange: hrvChange, restingHrChange: rhrChange, sleepChange: sleepChange,
            afterLateNight: (night?.bedtime ?? 0) >= lateBedtime
        )
    }
}

private func zip2(_ a: Double?, _ b: Double?) -> (Double, Double)? {
    guard let a, let b else { return nil }
    return (a, b)
}

/// How consistent bed and wake times are, 0–100. Night-to-night shifts of about half an hour
/// score in the 80s; a two-hour swing every night scores in the 40s.
func sleepRegularity(_ nights: [Night], count: Int = 14) -> Int? {
    let recent = Array(nights.suffix(count))
    guard recent.count >= 7 else { return nil }
    let shifts = zip(recent, recent.dropFirst()).map { a, b in
        (Double(abs(b.bedtime - a.bedtime)) + Double(abs(b.wake - a.wake))) / 2
    }
    guard let avg = mean(shifts) else { return nil }
    return Int(max(0, min(100, 100 - avg / 2)).rounded())
}
