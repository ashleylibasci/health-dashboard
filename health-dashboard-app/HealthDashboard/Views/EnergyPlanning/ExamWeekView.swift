import SwiftUI
import HealthCore

/// Exam week: the next exam, how this week compares with normal, and a short
/// plan, with the way into exam-week mode.
struct ExamWeekView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var showExamMode = false

    var body: some View {
        let exams = model.examsToShow
        Screen(title: "Exam week", accent: .indigo) {
            SampleDataBanner()
            (Text("Exam week ") + Text("plan").foregroundStyle(Accent.yellow.ink(scheme)))
                .font(.scaled(size: 34, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if exams.isEmpty {
                Card(accent: .yellow) {
                    Text("No exams on your list").font(.scaled(size: 17, weight: .bold))
                    Text("Add your exams and this screen plans the nights before each one, your caffeine and your study blocks.")
                        .font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                    LinkRow(title: "Add an exam", systemImage: "plus.circle.fill", accent: .yellow) { ExamListView() }
                }
            }
            if let exam = exams.first {
                let plan = ExamPlanner.plan(examStart: exam.start, daysUntil: min(exam.daysUntil, 2),
                                            usualBedtime: store.data.bedtime, latency: AppModel.planLatency,
                                            cycleLength: model.sleepCycleLength, need: model.tonightNeed.total,
                                            energyTemplate: model.energyToday, caffeineCutoff: model.caffeineCutoff,
                                            windowLength: AppModel.alarmWindowLead)
                examCard(exam)
                comparison
                planCard(exam, plan: plan)
                PrimaryButton(title: store.data.examModeOn ? "Open exam-week mode" : "Turn on exam-week mode", accent: .yellow) {
                    store.data.examModeOn = true
                    showExamMode = true
                }
                linksCard(exam, plan: plan)
            }
        }
        .navigationDestination(isPresented: $showExamMode) { ExamModeView() }
    }

    // MARK: Exam + week strip

    private func examCard(_ exam: UpcomingExam) -> some View {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: exam.date)?.start ?? cal.startOfDay(for: exam.date)
        // The app day: at 1am it's still the evening before.
        let today = cal.startOfDay(for: model.appDayDate)
        let days: [Date] = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let summary = "Week of \(weekStart.formatted(.dateTime.month(.wide).day())). \(exam.title) on \(exam.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))."
        return Card {
            HStack(spacing: 8) {
                Label("Next exam".uppercased(), systemImage: "calendar")
                    .font(.scaled(size: 12, weight: .bold))
                    .secondaryText()
                if exam.isExample { ExamExampleTag() }
                Spacer(minLength: 0)
                NavigationLink { ExamListView() } label: {
                    Text(exam.isExample ? "Add yours" : "Edit")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(Accent.yellow.ink(scheme))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(exam.isExample ? "Add your exams" : "Edit your exams")
            }
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let isExam = cal.isDate(d, inSameDayAs: exam.date)
                    let isToday = cal.isDate(d, inSameDayAs: today)
                    let isPrep = d > today && d < exam.date
                    let style: ExamWeekDayCell.Style = isExam ? .exam : (isToday ? .today : (isPrep ? .prep : .plain))
                    ExamWeekDayCell(weekday: d.formatted(.dateTime.weekday(.abbreviated)),
                            day: d.formatted(.dateTime.day()),
                            style: style)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            HStack(spacing: 8) {
                Text(exam.title).font(.scaled(size: 16, weight: .bold))
                Text("· \(exam.date.formatted(.dateTime.weekday(.abbreviated))) \(Clock.format(exam.start))")
                    .font(.scaled(size: 14)).secondaryText()
                Spacer(minLength: 4)
                if model.isLateLuteal {
                    NavigationLink { CycleView() } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Accent.purple.fill(scheme)).frame(width: 8, height: 8)
                            Text("late luteal").font(.scaled(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Accent.purple.ink(scheme))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 30)
                        .background(Accent.purple.tint(scheme), in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Late luteal phase. Open cycle.")
                    InfoButton(topic: .luteal)
                }
            }
        }
    }

    // MARK: This week vs normal

    private var comparison: some View {
        let fresh = model.lastNightIsFresh
        let asleep = model.lastNight.asleep
        let usualAsleep = model.usualAsleep
        let onset = model.lastNight.onset
        let usualOnset = model.usualSleepOnset
        let onsetLate: Bool = usualOnset.map { signedClockDiff(onset, $0) > 30 } ?? false
        let usualCaffeine = model.weekRecap?.averageCaffeine
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                Text("Right now vs. your normal").font(.scaled(size: 20, weight: .bold))
                InfoButton(title: "Your normal",
                           meaning: "Your own average over the last 30 days. Red numbers are further from your normal.",
                           forYou: "Exam stress often shows up as shorter, later sleep and a higher resting heart rate. Seeing it early helps you protect your sleep before the exam.")
            }
            .padding(.top, 4)
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
                            worse: model.hasHeartData && model.restingHRDelta >= 2, topic: .restingHR)
                NavigationLink { CaffeineView() } label: {
                    ExamCompareTile(title: "Caffeine", systemImage: "cup.and.saucer.fill", accent: .yellow,
                                value: "\(model.caffeineMgToday) mg",
                                normal: usualCaffeine.map { "Normal \($0) mg" } ?? "Limit 400 mg",
                                worse: model.caffeineMgToday > (usualCaffeine ?? 400) + 50, topic: .caffeineCutoff)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Signed minutes from `b` to `a` on a 24h clock, in -720..<720.
    private func signedClockDiff(_ a: Minutes, _ b: Minutes) -> Int {
        ((((a - b) % 1440) + 1440 + 720) % 1440) - 720
    }

    // MARK: Plan

    private func planCard(_ exam: UpcomingExam, plan: [ExamDayPlan]) -> some View {
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
        return Card(accent: .indigo) {
            SectionLabel(text: "Your plan", accent: .indigo)
            ExamNumberedRow(number: 1, accent: .purple, text: sleepLine, topic: .tonightNeed)
            ExamNumberedRow(number: 2, accent: .yellow, text: caffeineLine, topic: .caffeineCutoff)
            ExamNumberedRow(number: 3, accent: .pink, text: heartLine, topic: .restingHR)
        }
    }

    /// Sleep through the whole week of studying, not one night, is what
    /// stores it (Park 8; Okano 2019).
    static let sleepMakesItStick = "Sleep all week, especially the nights after you study, is what makes it stick."

    private func linksCard(_ exam: UpcomingExam, plan: [ExamDayPlan]) -> some View {
        let tonight = plan.first { $0.dayOffset == -exam.daysUntil + 1 }?.bedtimeBefore ?? store.data.bedtime
        return Card {
            LinkRow(title: "Tonight · bed \(Clock.format(tonight))", subtitle: "Your sleep plan",
                    systemImage: "moon.fill", accent: .purple) { SleepView() }
            LinkRow(title: "Caffeine", subtitle: model.caffeineCutoffShown.map { "Cutoff \(Clock.format($0)) today" } ?? model.caffeineNoCutoffShort,
                    systemImage: "cup.and.saucer.fill", accent: .yellow) { CaffeineView() }
        }
    }

    private func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }
}

// MARK: - Subviews

private struct ExamWeekDayCell: View {
    enum Style { case plain, today, prep, exam }
    var weekday: String
    var day: String
    var style: Style
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        let weekdayColor: Color = style == .today ? Accent.indigo.ink(scheme) : (style == .exam ? Accent.yellow.ink(scheme) : p.tertiary)
        let dayColor: Color = style == .exam ? Color(hex: 0x1A1400) : (style == .today ? Accent.indigo.ink(scheme) : p.primary)
        VStack(spacing: 6) {
            Text(weekday)
                .font(.scaled(size: 12, weight: .semibold))
                .foregroundStyle(weekdayColor)
            Text(day)
                .font(.scaled(size: 15, weight: .bold))
                .foregroundStyle(dayColor)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(background(p), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func background(_ p: Palette) -> Color {
        switch style {
        case .plain: return p.chip
        case .today, .prep: return Accent.indigo.fill(scheme).opacity(0.28)
        case .exam: return Accent.yellow.fill(scheme)
        }
    }
}

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
                Text(title).font(.scaled(size: 14, weight: .bold))
                InfoButton(topic: topic).padding(.vertical, -12)
                Spacer(minLength: 0)
                Image(systemName: systemImage).foregroundStyle(accent.ink(scheme)).accessibilityHidden(true)
            }
            Text(value)
                .font(.scaledNumber(24))
                .foregroundStyle(worse ? Accent.coral.ink(scheme) : Palette(scheme: scheme).primary)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(normal).font(.scaled(size: 12, weight: .semibold)).secondaryText()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                .font(.scaled(size: 14, weight: .heavy))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 28, height: 28)
                .background(accent.fill(scheme).opacity(0.28), in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.scaled(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 0)
            InfoButton(topic: topic).padding(.top, -8)
        }
    }
}
