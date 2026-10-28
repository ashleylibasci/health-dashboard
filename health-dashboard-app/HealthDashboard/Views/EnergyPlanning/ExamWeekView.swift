import SwiftUI
import HealthCore

/// Exam week: the next exam and tonight's sleep first, then the way into
/// exam-week mode, the short plan, how this week compares with normal and
/// her exam list (with the calendar's state), one tap each.
struct ExamWeekView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore

    var body: some View {
        let exams = model.examsToShow
        Screen(title: "Exam week", accent: .indigo) {
            SampleDataBanner()
            // One title, the nav title (Valtonen F8).
            if let exam = exams.first {
                let plan = ExamPlanner.plan(examStart: exam.start, daysUntil: min(exam.daysUntil, 2),
                                            usualBedtime: store.data.bedtime, latency: AppModel.planLatency,
                                            cycleLength: model.sleepCycleLength, need: model.tonightNeed.total,
                                            energyTemplate: model.energyToday, caffeineCutoff: model.caffeineCutoff,
                                            windowLength: AppModel.alarmWindowLead)
                summary(exam, plan: plan)
                RowCard {
                    MetricRow(title: "Exam-week mode",
                              note: store.data.examModeOn ? "On \u{00B7} planning for \(exam.course)" : "Off \u{00B7} plans sleep and study",
                              verdict: store.data.examModeOn ? RowVerdict(text: "On", accent: .yellow) : nil,
                              systemImage: "graduationcap.fill", accent: .yellow) { ExamModeView() }
                    RowDivider()
                    ExpandRow(title: "Your plan", summary: "Sleep, caffeine and your heart rate",
                              systemImage: "list.number", accent: .indigo) { planRows(exam, plan: plan) }
                    RowDivider()
                    ExpandRow(title: "Right now vs. your normal", summary: comparisonSummary,
                              systemImage: "chart.bar.fill", accent: .purple) { comparison }
                    RowDivider()
                    ExamsLinkRow()
                }
                Card(density: .compact) {
                    LearnMoreRow("Learn more about sleep and exams", article: .examWeek, accent: .indigo)
                }
            } else {
                Card(accent: .yellow) {
                    Text("No exams on your list").font(.cardTitle)
                    Text("Add your exams and this screen plans the nights before each one, your caffeine and your study blocks.")
                        .font(.bodyText).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                    LinkRow(title: "Add an exam", systemImage: "plus.circle.fill", accent: .yellow) { ExamListView() }
                }
            }
        }
    }

    // MARK: Summary

    private func summary(_ exam: UpcomingExam, plan: [ExamDayPlan]) -> some View {
        let days = exam.daysUntil
        // Tonight's night in the plan: its bedtime, and the wake after it.
        let tonight = plan.first { $0.dayOffset == -days + 1 }
        var pairs = [StatPair(label: "Bed tonight", value: Clock.format(tonight?.bedtimeBefore ?? store.data.bedtime))]
        if let tonight {
            let morning = Calendar.current.date(byAdding: .day, value: tonight.dayOffset, to: exam.date) ?? exam.date
            pairs.append(StatPair(label: "Up \(morning.formatted(.dateTime.weekday(.abbreviated)))", value: Clock.format(tonight.wake)))
        }
        return SummaryHeader(eyebrow: exam.isExample ? "Next exam \u{00B7} example" : "Next exam",
                             value: days == 0 ? "Today" : "\(days)",
                             unit: days == 0 ? nil : (days == 1 ? "day to go" : "days to go"),
                             status: model.isLateLuteal ? SummaryStatus(text: "Late luteal", accent: .purple) : nil,
                             line: "\(exam.title), \(exam.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) at \(Clock.format(exam.start)).",
                             pairs: pairs, accent: .yellow,
                             info: model.isLateLuteal ? Topic.luteal.explanation : nil)
    }

    // MARK: This week vs normal

    private var comparisonSummary: String {
        let sleep = model.lastNightIsFresh ? "Sleep \(Clock.duration(model.lastNight.asleep))" : "No sleep recorded"
        guard model.hasHeartData else { return sleep }
        return "\(sleep) \u{00B7} resting HR \(Int(model.restingHR.rounded()))"
    }

    private var comparison: some View {
        let fresh = model.lastNightIsFresh
        let asleep = model.lastNight.asleep
        let usualAsleep = model.usualAsleep
        let onset = model.lastNight.onset
        let usualOnset = model.usualSleepOnset
        let onsetLate: Bool = usualOnset.map { signedClockDiff(onset, $0) > 30 } ?? false
        let usualCaffeine = model.weekRecap?.averageCaffeine
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: Space.m) {
            Text("Your own average over the last 30 days. Red numbers are further from your normal. Exam stress often shows up as shorter, later sleep and a higher resting heart rate.")
                .font(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: columns, spacing: 12) {
                ExamCompareTile(title: "Sleep", systemImage: "moon.fill", accent: .purple,
                            value: fresh ? Clock.duration(asleep) : "No sleep",
                            normal: fresh ? (usualAsleep.map { "Normal \(Clock.duration($0))" } ?? "Last night") : "recorded last night",
                            worse: fresh && (usualAsleep.map { asleep < $0 - 15 } ?? false), topic: .sleepNeed)
                ExamCompareTile(title: "Asleep at", systemImage: "bed.double.fill", accent: .indigo,
                            value: fresh ? Clock.format(onset) : "\u{2014}",
                            normal: usualOnset.map { "Normal \(Clock.format($0))" } ?? "Last night",
                            worse: fresh && onsetLate, topic: .regularity)
                ExamCompareTile(title: "Resting HR", systemImage: "heart.fill", accent: .pink,
                            value: model.hasHeartData ? "\(Int(model.restingHR.rounded())) bpm" : "No reading",
                            normal: model.hasHeartData ? "Normal \(Int(model.usualRestingHR.rounded()))" : "yet today",
                            worse: model.hasHeartData && model.restingHRLevel == .above, topic: .restingHR)
                ExamCompareTile(title: "Caffeine", systemImage: "cup.and.saucer.fill", accent: .yellow,
                            value: "\(model.caffeineMgToday) mg",
                            normal: usualCaffeine.map { "Normal \($0) mg" } ?? "Limit 400 mg",
                            worse: model.caffeineMgToday > (usualCaffeine ?? 400) + 50, topic: .caffeineCutoff)
            }
        }
    }

    /// Signed minutes from `b` to `a` on a 24h clock, in -720..<720.
    private func signedClockDiff(_ a: Minutes, _ b: Minutes) -> Int {
        ((((a - b) % 1440) + 1440 + 720) % 1440) - 720
    }

    // MARK: Plan

    @ViewBuilder
    private func planRows(_ exam: UpcomingExam, plan: [ExamDayPlan]) -> some View {
        let lines = planLines(exam, plan: plan)
        ExamNumberedRow(number: 1, accent: .purple, text: lines.sleep, topic: .tonightNeed)
        ExamNumberedRow(number: 2, accent: .yellow, text: lines.caffeine, topic: .caffeineCutoff)
        ExamNumberedRow(number: 3, accent: .pink, text: lines.heart, topic: .restingHR)
    }

    private func planLines(_ exam: UpcomingExam, plan: [ExamDayPlan]) -> (sleep: String, caffeine: String, heart: String) {
        let cal = Calendar.current
        // Nights still ahead: the bedtime before each upcoming day.
        let upcoming = plan.filter { $0.dayOffset > -exam.daysUntil }
        let nights: [(name: String, bed: Minutes)] = upcoming.map { d in
            let date = cal.date(byAdding: .day, value: d.dayOffset - 1, to: exam.date) ?? exam.date
            return (name: date.formatted(.dateTime.weekday(.abbreviated)), bed: d.bedtimeBefore)
        }
        let sleepLine: String
        if let first = nights.first, nights.allSatisfy({ $0.bed == first.bed }) {
            sleepLine = "In bed by \(Clock.format(first.bed)) \(joined(nights.map { $0.name })). " + Self.sleepMakesItStick
        } else if !nights.isEmpty {
            sleepLine = "In bed by " + joined(nights.map { "\(Clock.format($0.bed)) \($0.name)" }) + ". " + Self.sleepMakesItStick
        } else {
            sleepLine = "Keep your usual bedtime. " + Self.sleepMakesItStick
        }
        let caffeineLine: String
        if model.caffeineCutoffShown != nil {
            caffeineLine = model.caffeineCutoffSentence
                + (model.isLateLuteal ? " Before your period, sleep may feel a bit lighter already." : " Anything later is still around at bedtime.")
        } else {
            // The cutoff for a typical drink falls before she's up: no clock time.
            caffeineLine = model.caffeineNoCutoffShort + ", soon after you wake. "
                + (model.caffeineLastsLonger ? "On your birth control, caffeine lasts \(model.caffeineLongerPhrase), so even a morning coffee leaves some at bedtime." : "Even a morning coffee leaves some at bedtime.")
        }
        let heartLine = "Your resting heart rate may read a little high until after the \(exam.kind.lowercased()). Stress alone can do that. If you also feel unwell, rest."
        return (sleepLine, caffeineLine, heartLine)
    }

    /// Sleep through the whole week of studying, not one night, is what
    /// stores it (Park 8; Okano 2019).
    static let sleepMakesItStick = "Sleep all week, especially the nights after you study, is what makes it stick."

    private func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }
}

// MARK: - Subviews

private struct ExamCompareTile: View {
    var title: String
    var systemImage: String
    var accent: Accent
    var value: String
    var normal: String
    var worse: Bool
    var topic: Topic
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(title).font(.bodyEmphasis)
                InfoButton(topic: topic).padding(.vertical, -12)
                Spacer(minLength: 0)
                Image(systemName: systemImage).foregroundStyle(accent.ink(scheme)).accessibilityHidden(true)
            }
            Text(value)
                .font(.numberM)
                .foregroundStyle(worse ? Accent.coral.ink(scheme) : Palette(scheme: scheme).primary)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(normal).font(.secondary).fontWeight(.semibold).secondaryText()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(worse ? "Further from your normal" : ""))
    }
}

private struct ExamNumberedRow: View {
    var number: Int
    var accent: Accent
    var text: String
    var topic: Topic
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.bodyEmphasis)
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 28, height: 28)
                .background(accent.fill(scheme).opacity(0.28), in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 0)
            InfoButton(topic: topic).padding(.top, -8)
        }
    }
}
