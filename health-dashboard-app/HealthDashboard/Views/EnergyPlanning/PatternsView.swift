import SwiftUI
import HealthCore

/// Patterns (D-P2): what her own nights show after 2+ drinks, in exam weeks
/// or on the mornings she tagged in the check-in, once there are enough of
/// them and the difference is bigger than her usual night-to-night wobble.
/// Plain words about what happened, never what caused it. Everything
/// still counting is one row each underneath.
struct PatternsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let factors = model.patternFactors
        let found = factors.filter { $0.sentence != nil }
        let learning = factors.filter { $0.sentence == nil }
        Screen(title: "Patterns", accent: .indigo) {
            SampleDataBanner()
            SummaryHeader(eyebrow: "From your own nights", value: "\(found.count)",
                          unit: found.count == 1 ? "pattern" : "patterns",
                          line: found.isEmpty
                              ? "Nothing clear yet. A pattern shows once your nights differ by more than their usual wobble."
                              : "What happened on your nights. It doesn't say what caused it.",
                          accent: .indigo, info: Self.explanation)
            if !found.isEmpty {
                RowCard {
                    ForEach(Array(found.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { RowDivider(hasIcon: true) }
                        PatternRow(factor: f)
                    }
                }
            }
            if !learning.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    SectionLabel(text: "Still counting")
                    RowCard {
                        ForEach(Array(learning.enumerated()), id: \.element.id) { i, f in
                            if i > 0 { RowDivider(hasIcon: true) }
                            ExpandRow(title: f.title, summary: f.progress, systemImage: f.systemImage, accent: f.accent) {
                                Text(Self.needs(f)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        RowDivider(hasIcon: true)
                        MetricRow(title: "Tag this morning", note: "Exam, late study, workout, party, sick",
                                  systemImage: "tag.fill", accent: .orange) { CheckInView() }
                    }
                }
            }
        }
    }

    /// What a factor still counting needs, in one or two sentences.
    static func needs(_ f: PatternFactor) -> String {
        let c = f.pattern?.comparison
        if let c, c.enoughNights {
            return "You have enough \(f.flaggedNights) to compare, and so far they don't differ from your other nights by more than their usual wobble."
        }
        if let strata = f.pattern?.strata, strata.count == 2, f.pattern?.comparison.strataQualify == false {
            return "So weekends' longer sleep isn't counted for it, it's compared within alarm mornings and within free mornings, and each needs at least \(PatternComparison.nightsPerSide) \(f.flaggedNights) and \(PatternComparison.nightsPerSide) other nights. So far: \(strata[0].withCount) on alarm mornings, \(strata[1].withCount) on free mornings."
        }
        let how = f.kind == .alcohol ? "Log alcohol on the Log tab." : f.kind == .examWeek ? "Add exams in your exam list, or tag \u{201C}Exam today\u{201D} in the check-in." : "Tag it in the morning check-in."
        return "A pattern needs at least \(PatternComparison.nightsPerSide) \(f.flaggedNights), \(PatternComparison.nightsPerSide) other nights and \(PatternComparison.nightsNeeded) in all. " + how
    }

    static let explanation = Explanation(
        id: "patterns", title: "Patterns",
        meaning: "Your nights with something (2+ drinks, an exam week, a tag from your morning check-in) next to your other nights, from your own Apple Watch data.",
        forYou: "It shows what happened, not why. A late night, a party and little sleep often come together, so one of them may not be the reason. Use it as a hint about yourself, not a rule.",
        howWeGotIt: "From your last 90 nights. A pattern needs at least 20 nights, with at least 5 that had the thing and 5 that didn't. The difference between the two averages has to be more than twice its standard error (the wobble you'd see between two groups of your nights by chance) and at least 5% for HRV, 2 bpm for resting heart rate, 20 minutes of sleep or half a point in your morning check-in. A tag only counts on mornings you checked in. Exam weeks are the exam day and the 6 days before it. Drinks, exams, late study, parties and workouts are compared within alarm mornings and within free mornings, then combined, so a weekend's longer sleep isn't counted for them; that needs at least 5 nights with and 5 without on both kinds of morning.")
}

/// A found pattern: the sentence, then the two averages one tap down.
private struct PatternRow: View {
    var factor: PatternFactor

    var body: some View {
        ExpandRow(title: factor.title, summary: factor.sentence, summaryLines: 3,
                  systemImage: factor.systemImage, accent: factor.accent) {
            if let sentence = factor.sentence {
                Text(sentence).fixedSize(horizontal: false, vertical: true)
            }
            if let p = factor.pattern, let a = p.comparison.withMean, let b = p.comparison.withoutMean {
                let top = max(abs(a), abs(b), 1)
                VStack(spacing: Space.s) {
                    BarRow(label: factor.title, fraction: bar(a, top: top, metric: p.metric),
                           valueText: Self.format(a, p.metric), accent: factor.accent)
                    BarRow(label: "Other nights", fraction: bar(b, top: top, metric: p.metric),
                           valueText: Self.format(b, p.metric), accent: .indigo)
                }
                Text("\(p.comparison.withCount) \(factor.flaggedNights) and \(p.comparison.withoutCount) other nights. \(Self.measureNote(p.metric))")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Bars for measures around zero (HRV and resting heart rate against
    /// usual) start from the middle of the range shown.
    private func bar(_ x: Double, top: Double, metric: PatternMetric) -> Double {
        switch metric {
        case .hrv, .restingHR: return 0.5 + x / (2 * max(top, 10))
        case .checkIn: return x / 5
        case .asleep, .fallAsleep: return x / top
        }
    }

    static func format(_ x: Double, _ metric: PatternMetric) -> String {
        switch metric {
        case .hrv: return String(format: "%+.0f%%", x)
        case .restingHR: return String(format: "%+.0f", x)
        case .asleep, .fallAsleep: return Clock.duration(Int(x.rounded()))
        case .checkIn: return String(format: "%.1f", x)
        }
    }

    static func measureNote(_ metric: PatternMetric) -> String {
        switch metric {
        case .hrv: return "HRV against your usual."
        case .restingHR: return "Resting heart rate against your usual, in bpm."
        case .asleep: return "Time asleep."
        case .fallAsleep: return "Time to fall asleep."
        case .checkIn: return "Your morning check-in, out of 5."
        }
    }
}
