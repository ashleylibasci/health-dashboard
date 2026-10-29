import Foundation

/// The break-week pattern (H-A4): after three packs, what her own logs show
/// clustering in the break, the way hormone-withdrawal symptoms (headache,
/// pelvic pain, mood) do for many people (Sulak 2000). Nothing when
/// nothing stands out.
public enum BreakWeekPattern {
    /// Finished packs it looks at (the last three).
    public static let packsNeeded = 3
    /// A symptom stands out when it's at least this many times as common on
    /// break days as on active-pill days…
    public static let symptomRatio = 2.0
    /// …is logged on at least this share of break days…
    public static let symptomMinShare = 1.0 / 7
    /// …and shows up in the break of at least this many of the packs.
    public static let symptomMinPacks = 2
    /// A 1–5 rating stands out when it averages at least this much worse on
    /// break days, worse in at least `symptomMinPacks` packs.
    public static let scoreShift = 0.5

    /// A daily score to compare (mood, a morning check-in…).
    public struct Score {
        public var name: String
        public var byDay: [Date: Double]
        public var higherIsWorse: Bool
        public init(name: String, byDay: [Date: Double], higherIsWorse: Bool) {
            self.name = name; self.byDay = byDay; self.higherIsWorse = higherIsWorse
        }
    }

    /// What stands out, strongest first: symptom names as logged, then
    /// score names. nil before three finished packs.
    public static func find(symptoms: [Date: Set<String>], scores: [Score], packs: [Int],
                            in calendar: PackCalendar, cal: Calendar = .current) -> [String]? {
        guard calendar.hasBreak, packs.count >= packsNeeded else { return nil }
        let used = Set(packs.suffix(packsNeeded))
        let breakDays = Double(packsNeeded * (calendar.packLength - calendar.activeDays))
        let activeDays = Double(packsNeeded * calendar.activeDays)

        var found: [(name: String, strength: Double)] = []
        // Symptoms.
        var inBreak: [String: [Int]] = [:], inActive: [String: Int] = [:]
        for (day, names) in symptoms {
            let at = calendar.position(of: day, calendar: cal)
            guard used.contains(at.pack) else { continue }
            for name in names {
                if calendar.isBreak(day: at.day) { inBreak[name, default: []].append(at.pack) } else { inActive[name, default: 0] += 1 }
            }
        }
        for (name, packsSeen) in inBreak {
            let breakShare = Double(packsSeen.count) / breakDays
            let activeShare = Double(inActive[name] ?? 0) / activeDays
            guard breakShare >= symptomMinShare, Set(packsSeen).count >= symptomMinPacks,
                  breakShare >= symptomRatio * activeShare else { continue }
            // As if logged on one active day when it never was.
            found.append((name, breakShare / max(activeShare, 1 / activeDays)))
        }
        // Scores.
        for score in scores {
            var shifts: [Double] = []
            for pack in used {
                var b: [Double] = [], a: [Double] = []
                for (day, v) in score.byDay {
                    let at = calendar.position(of: day, calendar: cal)
                    guard at.pack == pack else { continue }
                    if calendar.isBreak(day: at.day) { b.append(v) } else { a.append(v) }
                }
                guard b.count >= 2, a.count >= 5, let mb = b.mean, let ma = a.mean else { continue }
                shifts.append(score.higherIsWorse ? mb - ma : ma - mb)
            }
            guard shifts.filter({ $0 > 0 }).count >= symptomMinPacks, let mean = shifts.mean, mean >= scoreShift else { continue }
            found.append((score.name, mean))
        }
        // Symptoms first (their strength is a ratio), then scores.
        let symptomsFound = found.filter { inBreak[$0.name] != nil }.sorted { $0.strength > $1.strength }
        let scoresFound = found.filter { inBreak[$0.name] == nil }.sorted { $0.strength > $1.strength }
        return (symptomsFound + scoresFound).map(\.name)
    }
}
