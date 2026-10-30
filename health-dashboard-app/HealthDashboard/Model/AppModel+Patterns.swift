import Foundation
import HealthCore

/// One thing Patterns compares nights by (D-P2), and what her nights show.
struct PatternFactor: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case alcohol, examWeek, lateStudy, party, workout, sick
    }
    var kind: Kind
    /// The clearest measure, or the one with the most nights so far. Nil
    /// when nothing can be compared (no measures recorded).
    var pattern: Pattern?

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .alcohol: return "2+ drinks"
        case .examWeek: return "Exam weeks"
        case .lateStudy: return "Studying late"
        case .party: return "Parties"
        case .workout: return "Workouts"
        case .sick: return "Feeling sick"
        }
    }

    /// The start of her sentence: "On nights after 2+ drinks, …".
    var context: String {
        switch kind {
        case .alcohol: return "On nights after 2+ drinks"
        case .examWeek: return "In exam weeks"
        case .lateStudy: return "On nights you studied late"
        case .party: return "On nights after a party"
        case .workout: return "On nights after a workout"
        case .sick: return "On nights before a sick morning"
        }
    }

    var systemImage: String {
        switch kind {
        case .alcohol: return "wineglass.fill"
        case .examWeek: return "graduationcap.fill"
        case .lateStudy: return "book.fill"
        case .party: return "party.popper.fill"
        case .workout: return "figure.run"
        case .sick: return "thermometer.medium"
        }
    }

    var accent: Accent {
        switch kind {
        case .alcohol: return .berry
        case .examWeek, .lateStudy: return .yellow
        case .party: return .pink
        case .workout: return .mint
        case .sick: return .coral
        }
    }

    /// What counts as one of these nights, in her words.
    var flaggedNights: String {
        switch kind {
        case .alcohol: return "nights after 2+ drinks"
        case .examWeek: return "exam-week nights"
        default: return "tagged nights"
        }
    }

    /// The measures worth comparing for it, so a dozen comparisons don't
    /// turn up a difference by chance.
    var metrics: [PatternMetric] {
        switch kind {
        case .alcohol: return [.hrv, .restingHR, .asleep]
        case .examWeek, .lateStudy: return [.asleep, .checkIn]
        case .party: return [.hrv, .asleep, .checkIn]
        case .workout: return [.hrv, .restingHR, .asleep]
        case .sick: return [.restingHR, .hrv]
        }
    }

    var sentence: String? { pattern?.sentence(context: context) }

    /// Compared within alarm mornings and within free mornings: anything
    /// that can be mostly a weekend thing, so it isn't credited with the
    /// weekend's longer sleep. Feeling sick isn't.
    var withinAlarmMornings: Bool { kind != .sick }

    /// "3 of 5 tagged nights", "No clear difference yet".
    var progress: String {
        guard let c = pattern?.comparison else { return "Nothing to compare yet" }
        if let strata = pattern?.strata, strata.count == 2, !c.strataQualify,
           strata.contains(where: { $0.withCount < PatternComparison.nightsPerSide }) {
            let need = PatternComparison.nightsPerSide
            return "\(min(strata[0].withCount, need)) of \(need) on alarm mornings, \(min(strata[1].withCount, need)) of \(need) on free"
        }
        if c.withCount < PatternComparison.nightsPerSide {
            return "\(c.withCount) of \(PatternComparison.nightsPerSide) \(flaggedNights)"
        }
        if c.withoutCount < PatternComparison.nightsPerSide || c.nights < PatternComparison.nightsNeeded || !c.strataQualify {
            return "\(min(c.nights, PatternComparison.nightsNeeded)) of \(PatternComparison.nightsNeeded) nights"
        }
        return "No clear difference yet"
    }
}

extension AppModel {
    /// Patterns (D-P2), each factor with what her nights show, the ones
    /// that show first. The last 90 nights. Alcohol only while she tracks it.
    var patternFactors: [PatternFactor] {
        let nights = patternNights
        let kinds = PatternFactor.Kind.allCases.filter { $0 != .alcohol || store.data.drinksTracking }
        return kinds.map { kind in
            let factor = PatternFactor(kind: kind)
            return PatternFactor(kind: kind, pattern: Pattern.find(nights, metrics: factor.metrics,
                                                                   withinAlarmMornings: factor.withinAlarmMornings) { patternFlag(kind, $0) })
        }
        .sorted { ($0.sentence != nil ? 0 : 1) < ($1.sentence != nil ? 0 : 1) }
    }

    /// Whether a night counts for a factor; nil when it isn't known (no
    /// check-in that morning for a tag, 1 drink for "2+ drinks").
    func patternFlag(_ kind: PatternFactor.Kind, _ night: NightRecord) -> Bool? {
        switch kind {
        case .alcohol:
            if usingSampleData { return followedDrinks(night) }
            let window = NightPairing.alcoholWindow(wakeDay: night.wakeDay)
            let drinks = store.data.alcoholLog.filter { window.contains($0.date) }.map(\.standardDrinks).reduce(0, +)
            return drinks >= 2 ? true : drinks == 0 ? false : nil
        case .examWeek:
            return isExamWeek(night.wakeDay) || store.checkIn(forWakeDay: night.wakeDay)?.tags.contains(DayTag.exam.rawValue) == true
        case .lateStudy, .party, .workout, .sick:
            guard let tags = store.checkIn(forWakeDay: night.wakeDay)?.tags else { return nil }
            return tags.contains(Self.tag(for: kind).rawValue)
        }
    }

    private static func tag(for kind: PatternFactor.Kind) -> DayTag {
        switch kind {
        case .lateStudy: return .lateStudy
        case .party: return .party
        case .workout: return .workout
        default: return .sick
        }
    }

    /// The exam day or one of the 6 days before it.
    private func isExamWeek(_ wakeDay: Date) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: wakeDay)
        return store.data.exams.contains { exam in
            let examDay = cal.startOfDay(for: exam.date)
            let days = cal.dateComponents([.day], from: day, to: examDay).day ?? -1
            return (0...6).contains(days)
        }
    }

    /// The nights compared: the last 90. Example nights carry the designs'
    /// effects (as the alcohol comparison's do), so the example screen
    /// shows what a found pattern looks like; workouts are left without one.
    var patternNights: [NightRecord] {
        let recent = Array(nights.sorted { $0.wakeDay > $1.wakeDay }.prefix(90))
        guard usingSampleData else { return recent }
        return recent.map { n in
            var m = n
            if followedDrinks(n) {
                m.outcome.hrvDeltaPct = (m.outcome.hrvDeltaPct ?? 0) - 12
                m.outcome.restingHRDelta = (m.outcome.restingHRDelta ?? 0) + 6
                m.asleepMinutes -= 25
            }
            if isExamWeek(n.wakeDay) { m.asleepMinutes -= 40 }
            let tags = store.checkIn(forWakeDay: n.wakeDay)?.tags ?? []
            if tags.contains(DayTag.lateStudy.rawValue) {
                m.asleepMinutes -= 50
                m.outcome.checkIn = max(1, (m.outcome.checkIn ?? 3) - 0.8)
            }
            if tags.contains(DayTag.party.rawValue) {
                m.outcome.hrvDeltaPct = (m.outcome.hrvDeltaPct ?? 0) - 10
                m.asleepMinutes -= 30
            }
            if tags.contains(DayTag.sick.rawValue) {
                m.outcome.restingHRDelta = (m.outcome.restingHRDelta ?? 0) + 4
                m.outcome.hrvDeltaPct = (m.outcome.hrvDeltaPct ?? 0) - 8
            }
            return m
        }
    }
}
