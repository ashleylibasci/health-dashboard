import SwiftUI
import Charts
import HealthCore

/// Exam-week mode: protects sleep before an exam, plans study into her peaks
/// and plans the exam morning. The switch and the countdown come first,
/// then the day-by-day plan; exam morning and the why are one tap down.
struct ExamModeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var examID: String? = nil
    @State private var dayIndex = 0
    @State private var showSick = false

    /// Her own sleep cycle length, the one the plan uses.
    private var cycle: Int { model.sleepCycleLength }
    /// Minutes from waking until grogginess usually clears (up to an hour
    /// after deep sleep). The energy curve uses the same (Park 12).
    private let grogginess = ExamPlanner.grogginessMinutes

    var body: some View {
        let all = model.examsToShow
        Screen(title: "Exam-week mode", accent: .yellow) {
            SampleDataBanner()
            if let exam = all.first(where: { $0.id == examID }) ?? all.first {
                let plan = ExamPlanner.plan(examStart: exam.start, daysUntil: min(exam.daysUntil, 2),
                                            usualBedtime: store.data.bedtime, latency: AppModel.planLatency,
                                            cycleLength: model.sleepCycleLength, need: model.tonightNeed.total,
                                            energyTemplate: model.energyToday, caffeineCutoff: model.caffeineCutoff,
                                            windowLength: AppModel.alarmWindowLead)
                let index = min(max(dayIndex, 0), max(plan.count - 1, 0))
                if store.data.examModeOn && model.unwellTonight {
                    CalloutBar(text: "Sick before an exam? Rest comes first", systemImage: "cross.case.fill", accent: .coral) {
                        showSick = true
                    }
                }
                modeCard(exam)
                if store.data.examModeOn {
                    countdownCard(exam, plan: plan)
                    if all.count > 1 { examPicker(all, selected: exam) }
                    planSection(exam, plan: plan, index: index)
                } else {
                    offCard(all)
                }
                RowCard {
                    if store.data.examModeOn, let examDay = plan.last {
                        MetricRow(title: "Exam morning",
                                  note: "Up \(Clock.format(examDay.wake)), clear-headed by \(Clock.format(examDay.wake + grogginess))",
                                  systemImage: "sunrise.fill", accent: .orange) { ExamMorningView(exam: exam, day: examDay) }
                        RowDivider()
                    }
                    ExpandRow(title: "Why sleep comes first", summary: "Sleep debt: \(Clock.duration(model.sleepDebt))",
                              systemImage: "brain.head.profile", accent: .purple) { whyRows }
                    if store.data.examModeOn && clocksChangeBefore(exam) {
                        RowDivider()
                        MetricRow(title: "Clocks fall back \(shortDate(model.nextFallBack))",
                                  note: "Your body runs an hour ahead of the clock for a few days",
                                  systemImage: "clock.arrow.circlepath", accent: .indigo) { TimeChangeView() }
                    }
                    RowDivider()
                    ExamsLinkRow()
                }
            } else {
                noExamsCard
                RowCard {
                    ExpandRow(title: "Why sleep comes first", summary: "Sleep debt: \(Clock.duration(model.sleepDebt))",
                              systemImage: "brain.head.profile", accent: .purple) { whyRows }
                }
            }
            Card(density: .compact) {
                LearnMoreRow("Learn more about sleep and exams", article: .examWeek, accent: .yellow)
            }
        }
        .bottomSheet(isPresented: $showSick, title: "Sick before an exam?") {
            Text("Your body signals look like you may be fighting something off. Rest comes before study blocks, so the plan below drops them. Campus health can document that you're sick; ask your instructor or dean about a make-up.")
                .font(.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "Sick check", subtitle: "What your body is showing", systemImage: "thermometer.medium", accent: .coral) { SickView() }
        }
    }

    /// The clocks go back before this exam.
    private func clocksChangeBefore(_ exam: UpcomingExam) -> Bool {
        let fallBack = model.nextFallBack
        return fallBack > Calendar.current.startOfDay(for: .now) && fallBack <= exam.date
    }

    private var noExamsCard: some View {
        Card(accent: .yellow) {
            Text("No exams on your list").font(.cardTitle)
            Text("Add an exam and exam mode plans your sleep, study blocks and exam-morning alarm around it.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "Add an exam", systemImage: "plus.circle.fill", accent: .yellow) { ExamListView() }
        }
    }

    // MARK: Mode

    private func modeCard(_ exam: UpcomingExam) -> some View {
        let on = store.data.examModeOn
        return Card(accent: on ? .yellow : nil) {
            Toggle(isOn: $store.data.examModeOn) {
                HStack(spacing: 12) {
                    Image(systemName: "graduationcap.fill")
                        .font(.cardTitle)
                        .foregroundStyle(Accent.yellow.ink(scheme))
                        .frame(width: 40, height: 40)
                        .background(Accent.yellow.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exam mode").font(.cardTitle)
                        Text(on ? "On · planning for \(exam.course)" : "Off")
                            .font(.secondary).fontWeight(.semibold)
                            .foregroundStyle(on ? Accent.yellow.ink(scheme) : Palette(scheme: scheme).secondary)
                    }
                }
            }
            .tint(Accent.yellow.fill(scheme))
            .frame(minHeight: 44)
            if !on {
                Text("Plans your sleep and study blocks around your exam, and can send a one-off smart alarm window for exam morning to your Watch.")
                    .font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if exam.isExample {
                HStack(spacing: 8) {
                    ExamExampleTag()
                    Text("Add your own exams to plan for them.").font(.secondary).secondaryText()
                }
            }
        }
    }

    private func offCard(_ all: [UpcomingExam]) -> some View {
        let list = all.map { "\($0.course) on \(shortDate($0.date))" }
        let joined = list.count > 1 ? list.dropLast().joined(separator: ", ") + " and " + (list.last ?? "") : (list.first ?? "")
        return Card {
            Text("Exam mode is off").font(.cardTitle)
            Text("\(joined) \(all.count == 1 ? "is" : "are") on your list. Turn exam mode on to plan sleep and study around \(all.count == 1 ? "it" : "them").")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Exam picker + countdown

    private func examPicker(_ all: [UpcomingExam], selected: UpcomingExam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Upcoming exams".uppercased(), systemImage: "calendar")
                .font(.secondary).fontWeight(.bold)
                .secondaryText()
            HStack(spacing: 10) {
                ForEach(all.prefix(3)) { x in
                    ExamOption(course: x.course, kind: x.kind,
                               when: "\(shortDate(x.date)) · \(Clock.format(x.start))",
                               selected: x.id == selected.id) {
                        examID = x.id
                        dayIndex = 0
                    }
                }
            }
        }
    }

    /// The countdown as the screen's summary: nights (or days) to the exam,
    /// and the two things to know next.
    private func countdownCard(_ exam: UpcomingExam, plan: [ExamDayPlan]) -> some View {
        let days = exam.daysUntil
        let unit: String
        if days == 0 { unit = "exam day" } else if days <= 7 { unit = days == 1 ? "night of sleep" : "nights of sleep" } else { unit = "days" }
        let tonight = plan.first { $0.dayOffset == -days + 1 }
        let bedTonight = tonight?.bedtimeBefore ?? model.tonightBedtime
        var pairs: [StatPair] = []
        if days <= 2 {
            let studyDays = plan.filter { $0.dayOffset < 0 && $0.dayOffset > -days }
            if studyDays.isEmpty {
                pairs.append(StatPair(label: "Last study day", value: "Today"))
            } else {
                let names = studyDays.map { weekdayName(dayDate(exam, $0.dayOffset)) }.joined(separator: " and ")
                let blocks = studyDays.map(\.studyBlocks.count).reduce(0, +)
                pairs.append(StatPair(label: "Study", value: "\(names) \u{00B7} \(blocks) \(blocks == 1 ? "block" : "blocks")"))
            }
            pairs.append(StatPair(label: "Bed tonight", value: Clock.format(bedTonight)))
        } else {
            pairs.append(StatPair(label: "\(plan.count)-day lead-up", value: plan.first.map { shortDate(dayDate(exam, $0.dayOffset)) } ?? "\u{2013}"))
            pairs.append(clocksChangeBefore(exam)
                         ? StatPair(label: "Clocks fall back", value: shortDate(model.nextFallBack))
                         : StatPair(label: "Bed tonight", value: Clock.format(model.tonightBedtime)))
        }
        return SummaryHeader(eyebrow: "Countdown", value: days == 0 ? "Today" : "\(days)", unit: unit,
                             line: "Until your \(exam.title), \(shortDate(exam.date)) at \(Clock.format(exam.start)).",
                             pairs: pairs, accent: .yellow)
    }

    // MARK: Day plan

    private func planSection(_ exam: UpcomingExam, plan: [ExamDayPlan], index: Int) -> some View {
        let first = plan.first.map { shortDate(dayDate(exam, $0.dayOffset)) } ?? ""
        let last = plan.last.map { shortDate(dayDate(exam, $0.dayOffset)) } ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plan to exam day").font(.section)
                Spacer()
                Text(first == last ? first : "\(first) – \(last)").font(.secondary).secondaryText()
            }
            .padding(.top, 6)
            HStack(spacing: 8) {
                ForEach(plan.indices, id: \.self) { i in
                    let d = plan[i]
                    let isExam = d.dayOffset == 0
                    let nextBed: Minutes = plan.indices.contains(i + 1) ? plan[i + 1].bedtimeBefore : store.data.bedtime
                    let key: String = isExam
                        ? "\(exam.kind) \(Clock.format(exam.start))"
                        : "Bed \(Clock.format(nextBed))"
                    ExamDayTab(day: weekdayName(dayDate(exam, d.dayOffset)),
                           date: dayDate(exam, d.dayOffset).formatted(.dateTime.month(.abbreviated).day()),
                           key: key, isExam: isExam, selected: i == index) {
                        dayIndex = i
                    }
                }
            }
            if plan.indices.contains(index) {
                dayCard(exam, plan: plan, index: index)
            }
        }
    }

    private func tag(for d: ExamDayPlan, exam: UpcomingExam) -> (String, Accent?) {
        if d.dayOffset == 0 { return ("Exam day", .yellow) }
        if d.dayOffset == -exam.daysUntil { return ("Today", .indigo) }
        if d.dayOffset == -1 { return ("Night before", .purple) }
        return ("Plan starts", nil)
    }

    private func dayCard(_ exam: UpcomingExam, plan: [ExamDayPlan], index: Int) -> some View {
        let d = plan[index]
        let isExam = d.dayOffset == 0
        let date = dayDate(exam, d.dayOffset)
        let next: ExamDayPlan? = plan.indices.contains(index + 1) ? plan[index + 1] : nil
        let (tagText, tagAccent) = tag(for: d, exam: exam)
        let need = model.tonightNeed.total

        let aLabel: String
        let aValue: String
        let bLabel: String
        let bValue: String
        var sleep: Int? = nil
        var note: String
        if isExam {
            aLabel = "Up"
            aValue = Clock.format(d.wake)
            bLabel = exam.kind
            bValue = Clock.format(exam.start)
            note = "Smart alarm window \(d.alarmWindow.label). \(exam.start - d.wake) minutes from waking to the \(exam.kind.lowercased())."
        } else if let next {
            aLabel = "Bed"
            aValue = Clock.format(next.bedtimeBefore)
            bLabel = "Up \(weekdayName(dayDate(exam, next.dayOffset)))"
            bValue = Clock.format(next.wake)
            let asleep = next.asleep
            sleep = asleep
            // The plan never goes below her need (Park 2).
            note = next.endsCycle
                ? "\(asleep / max(cycle, 1)) full sleep cycles of about \(cycle) minutes, covering your need."
                : "Your full need. No cycle ends close enough to it, and more sleep beats finishing a cycle."
            if next.bedtimeBefore < store.data.bedtime - 60 {
                note += " That's well before your usual bedtime, so start winding down early."
            }
        } else {
            aLabel = "Bed"
            aValue = Clock.format(store.data.bedtime)
            bLabel = "Up"
            bValue = Clock.format(d.wake)
            note = "Your usual night."
        }

        let rows = planRows(exam, day: d, next: next)
        let boxAccent: Accent = isExam ? .yellow : .purple
        let sleepMinutes: Int? = sleep
        let sleepFraction: Double = sleep.map { min(Double($0) / Double(max(need, 1)), 1) } ?? 0
        let noteText: String = note
        let p = Palette(scheme: scheme)
        let tagForeground: Color
        let tagBackground: Color
        if let a = tagAccent {
            tagForeground = a == .yellow ? Color(hex: 0x1A1400) : a.ink(scheme)
            tagBackground = a == .yellow ? a.fill(scheme) : a.tint(scheme)
        } else {
            tagForeground = p.secondary
            tagBackground = p.chip
        }
        return Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(date.formatted(.dateTime.weekday(.wide))).font(.cardTitle)
                    Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.secondary).secondaryText()
                }
                Spacer()
                Text(tagText)
                    .font(.secondary).fontWeight(.bold)
                    .foregroundStyle(tagForeground)
                    .padding(.horizontal, 10)
                    .frame(minHeight: Font.scaledSize(26))
                    .background(tagBackground, in: Capsule())
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 24) {
                    ExamLabeledValue(label: aLabel, value: aValue)
                    ExamLabeledValue(label: bLabel, value: bValue)
                }
                if let sleep = sleepMinutes {
                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette(scheme: scheme).track)
                                Capsule().fill(Accent.purple.fill(scheme))
                                    .frame(width: geo.size.width * CGFloat(sleepFraction))
                            }
                        }
                        .frame(height: 8)
                        Text("\(Clock.duration(sleep)) of \(Clock.duration(need))")
                            .font(.secondary).fontWeight(.bold)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Clock.duration(sleep)) asleep against a need of \(Clock.duration(need))")
                }
                Text(noteText).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(boxAccent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            ForEach(rows) { r in ExamPlanRowView(row: r) }
        }
    }

    private func planRows(_ exam: UpcomingExam, day d: ExamDayPlan, next: ExamDayPlan?) -> [ExamPlanRow] {
        var rows: [ExamPlanRow] = []
        let energy = model.energyToday
        if d.dayOffset == 0 {
            rows.append(ExamPlanRow(id: 0, kind: .exam, time: "\(Clock.format(exam.start)) · \(exam.title)",
                                note: "Grogginess (the foggy just-woke-up feeling) usually passes within about \(grogginess) minutes, so by about \(Clock.format(d.wake + grogginess)); up to an hour after deep sleep.", topic: .grogginess))
            rows.append(ExamPlanRow(id: 1, kind: .caffeine, time: "Coffee around \(Clock.format(d.caffeineBy))",
                                note: "So it's working by \(Clock.format(exam.start)). " + examCoffeeNote(d), topic: .caffeineCutoff))
            if let dip = energy.zone(.afternoonDip)?.range {
                rows.append(ExamPlanRow(id: 2, kind: .after, time: "\(dip.label) dip",
                                    note: "A 20-minute nap is fine, early in the dip. Turn exam mode off once the \(exam.kind.lowercased()) is done.", topic: .afternoonDip))
            }
            return rows
        }

        let isToday = d.dayOffset == -exam.daysUntil
        let bed = next?.bedtimeBefore ?? model.tonightBedtime
        let stop = bed - 90
        let peak = energy.zone(.morningPeak)?.range
        var allPassed = true
        // Sick: rest first, no study blocks (Moreno F8).
        let blocks = model.unwellTonight ? [] : d.studyBlocks
        if model.unwellTonight {
            rows.append(ExamPlanRow(id: 9, kind: .stop, time: "Rest today",
                                note: "No study blocks while you may be sick. Light review only if you feel up to it."))
        }
        for (j, block) in blocks.enumerated() {
            let passed = isToday && block.end <= model.now
            if !passed { allPassed = false }
            let isMorning = block == peak
            let note: String
            if passed {
                note = isMorning
                    ? "Your morning peak has passed for today. Those hours move to tomorrow."
                    : "Your second wind has passed for today."
            } else {
                note = isMorning
                    ? "Morning peak. Hardest \(exam.course) topics first."
                    : "Second wind. Review mistakes and do one timed practice \(exam.kind.lowercased())."
            }
            rows.append(ExamPlanRow(id: 10 + j, kind: passed ? .passed : .study, time: block.label, note: note,
                                    topic: isMorning ? .morningPeak : .secondWind))
        }
        if isToday && allPassed && !model.unwellTonight {
            rows.append(ExamPlanRow(id: 20, kind: .study, time: "Tonight, until \(Clock.format(stop))",
                                note: "Light review only: flashcards and notes. No new material this late."))
        }
        // When the cutoff for a typical drink falls before she's up (the pill
        // makes caffeine last about one and a half times as long), there's no clock time to print.
        let cutoffBeforeWake = model.caffeineCutoffBeforeWake
        if isToday && model.caffeineMgToday > 0 {
            let after = cutoffBeforeWake ? "No more today." : "Nothing after \(Clock.format(d.caffeineBy))."
            rows.append(ExamPlanRow(id: 30, kind: .caffeine, time: "\(model.caffeineMgToday) mg so far",
                                note: "About \(model.caffeineAtBedtime) mg left by bedtime. \(after)", topic: .caffeineLeft))
        } else if cutoffBeforeWake {
            rows.append(ExamPlanRow(id: 30, kind: .caffeine, time: model.caffeineNoCutoffShort,
                                note: model.caffeineEarlyOnlyText, topic: .caffeineCutoff))
        } else {
            rows.append(ExamPlanRow(id: 30, kind: .caffeine, time: "Nothing after \(Clock.format(d.caffeineBy))",
                                note: "So it's cleared by bedtime.", topic: .caffeineCutoff))
        }
        rows.append(ExamPlanRow(id: 40, kind: .stop, time: "Stop studying \(Clock.format(stop))",
                            note: "Sleep is when today's review sticks. One more hour awake costs more than it adds."))
        return rows
    }

    // MARK: Why

    @ViewBuilder
    private var whyRows: some View {
        let need = model.tonightNeed.total
        let lastNight = model.lastNight.asleep
        let scale = Double(max(need, lastNight, 1))
        ExamWhyRow(systemImage: "brain.head.profile", accent: .purple, title: "Short nights cost recall",
               detail: "After a short night, memory and focus drop. Sleep is when what you studied gets stored, so an all-nighter takes back more than it gives.",
               topic: .rem)
        ExamWhyRow(systemImage: "car.fill", accent: .orange, title: "Up all night? Don't drive",
               detail: "After an all-nighter or a very short night, driving is about as risky as driving drunk. Get a ride or take the bus.",
               topic: .lateNight)
        ExamWhyRow(systemImage: "moon.zzz.fill", accent: .coral, title: "Sleep debt: \(Clock.duration(model.sleepDebt))",
               detail: "Sleep you've missed over the last two weeks. Paying some back before the exam is worth more than one more hour of review. Exam mode protects your bedtime first.",
               topic: .sleepDebt)
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                SectionLabel(text: "Tonight's need vs. last night")
                InfoButton(topic: .tonightNeed).padding(.vertical, -12)
            }
            BarRow(label: "Tonight's need", fraction: Double(need) / scale, valueText: Clock.duration(need), accent: .purple)
            BarRow(label: "Last night", fraction: Double(lastNight) / scale, valueText: Clock.duration(lastNight), accent: .coral)
        }
    }

    // MARK: Helpers

    /// The exam-day coffee checked against that night's bedtime (Shah F1):
    /// the biggest drink at the coffee time that still clears, and a plain
    /// plain word when a bigger one may make that night's sleep lighter.
    private func examCoffeeNote(_ d: ExamDayPlan) -> String {
        let bed = 1440 + store.data.bedtime
        let largest = CaffeineModel.largestDose(at: d.caffeineBy, bedtime: bed, halfLifeHours: model.caffeineHalfLifeHours, wake: d.wake)
        let longer = model.caffeineLastsLonger ? " On your birth control caffeine lasts \(model.caffeineLongerPhrase)." : ""
        if largest >= 150 {
            return "Up to about \(largest) mg then still clears by bedtime."
        }
        if largest >= 25 {
            return "Up to about \(largest) mg then clears by bedtime; a bigger one may make tonight\u{2019}s sleep a little lighter. Before an exam that can be worth it." + longer
        }
        return "Coffee then may make tonight\u{2019}s sleep a little lighter. Before an exam that can be worth it; keep it to one regular cup." + longer
    }

    private func dayDate(_ exam: UpcomingExam, _ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: exam.date) ?? exam.date
    }

    private func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func weekdayName(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated))
    }
}

// MARK: - Exam morning

/// Exam morning: when she's up and clear-headed, the smart alarm window to
/// drag along, and the button that sends it to her Watch. Pushed from
/// exam-week mode.
private struct ExamMorningView: View {
    var exam: UpcomingExam
    var day: ExamDayPlan
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var alarmSet = false
    /// The selected time, snapped to 5 minutes.
    @State private var selection: Int? = nil

    private let grogginess = ExamPlanner.grogginessMinutes

    var body: some View {
        let d = day
        let window = d.alarmWindow
        let sentEarlier: Bool = model.activeAlarmOverride.map {
            Calendar.current.isDate($0.wakeDay, inSameDayAs: exam.date) && $0.start == window.start && $0.end == window.end
        } ?? false
        let isSet = alarmSet || sentEarlier
        let date = exam.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        Screen(title: "Exam morning", accent: .orange) {
            SummaryHeader(eyebrow: "Exam morning \u{00B7} \(date)", value: Clock.format(d.wake), unit: "up",
                          line: "Clear-headed by \(Clock.format(d.wake + grogginess)), well before \(Clock.format(exam.start)).",
                          pairs: [StatPair(label: "Smart alarm", value: window.label),
                                  StatPair(label: exam.kind, value: Clock.format(exam.start))],
                          accent: .orange, info: Topic.smartAlarm.explanation)
            Card {
                Text("Your smart alarm wakes you when you start stirring between \(Clock.format(window.start)) and \(Clock.format(window.end)). Grogginess usually fades within about \(grogginess) minutes (up to an hour after deep sleep), well before \(Clock.format(exam.start)).")
                    .font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                readout
                ExamMorningChart(window: window, wake: d.wake, groggyEnd: d.wake + grogginess, examStart: exam.start,
                                 selected: selection,
                                 selection: $selection.snapping { Int((Double($0) / 5).rounded()) * 5 },
                                 summary: "Exam morning: smart alarm window \(window.label), wake at \(Clock.format(d.wake)), grogginess for about \(grogginess) minutes, \(exam.title) at \(Clock.format(exam.start))")
                    .frame(height: 90)
                ScrubHint(each: "moment")
                FlowLayout(spacing: 14, lineSpacing: 6) {
                    swatch(Accent.orange.fill(scheme).opacity(0.55), "Smart alarm window")
                    swatch(Accent.indigo.fill(scheme).opacity(0.45), "Grogginess")
                    swatch(Accent.yellow.fill(scheme), exam.kind)
                }
            }
            if exam.isExample {
                Text("This is an example exam. Add your own to send its window to your Watch.")
                    .font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            } else if Calendar.current.isDate(exam.date, inSameDayAs: model.nextWakeDay) {
                PrimaryButton(title: isSet ? "Sent to your Watch: \(window.label)" : "Use this window on my Watch tonight",
                              accent: .orange, done: isSet) {
                    guard !isSet else { return }
                    alarmSet = true
                    store.data.smartAlarmEnabled = true
                    model.pushToWatch(alarm: window, wakeDay: exam.date)
                }
            } else {
                Text("You can send this window to your Watch's smart alarm the night before.")
                    .font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What each part of the morning means, as (value, note, accent).
    private func moment(at t: Int) -> (value: String, detail: String, accent: Accent) {
        let d = day
        let window = d.alarmWindow
        if t < window.start {
            return ("Still asleep", "Your smart alarm can start waking you from \(Clock.format(window.start)), as soon as you start stirring.", .purple)
        }
        if t < d.wake {
            return ("Smart alarm window", "If you start stirring now, the alarm wakes you here instead of later. Stirring often means lighter sleep, which can feel a bit easier to wake from.", .orange)
        }
        if t < d.wake + grogginess {
            return (t == d.wake ? "Up" : "Grogginess", "Your brain usually takes about \(grogginess) minutes to fully switch on (up to an hour after deep sleep). Get daylight and water; skip last-minute cramming.", .indigo)
        }
        if t < exam.start {
            return ("Clear-headed", "Grogginess has passed. Coffee around \(Clock.format(d.caffeineBy)) so it's working by the \(exam.kind.lowercased()).", .mint)
        }
        return ("\(exam.kind) starts", "\(exam.start - d.wake) minutes after waking: well past grogginess.", .yellow)
    }

    private var readout: ChartReadout {
        let d = day
        let t = selection ?? d.wake
        let m = moment(at: t)
        // One note per part of the morning, so the readout keeps one height.
        let slots = [d.alarmWindow.start - 5, d.alarmWindow.start, d.wake, d.wake + grogginess, exam.start].map { moment(at: $0).detail }
        return ChartReadout(title: Clock.format(t), value: m.value, detail: m.detail, accent: m.accent,
                            onClear: selection == nil ? nil : { selection = nil }, detailSlots: slots)
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.secondary).secondaryText().lineLimit(1)
        }
    }
}

// MARK: - Rows

private struct ExamPlanRow: Identifiable {
    enum Kind { case study, passed, caffeine, stop, exam, after }
    let id: Int
    let kind: Kind
    let time: String
    let note: String
    var topic: Topic? = nil
}

private struct ExamPlanRowView: View {
    var row: ExamPlanRow
    @Environment(\.colorScheme) private var scheme

    private var label: String {
        switch row.kind {
        case .study: return "Study"
        case .passed: return "Peak passed"
        case .caffeine: return "Caffeine"
        case .stop: return "No all-nighter"
        case .exam: return "Exam"
        case .after: return "After"
        }
    }

    private var color: Color {
        let p = Palette(scheme: scheme)
        switch row.kind {
        case .study: return Accent.mint.ink(scheme)
        case .passed: return p.tertiary
        case .caffeine, .exam: return Accent.yellow.ink(scheme)
        case .stop: return Accent.coral.ink(scheme)
        case .after: return Accent.purple.ink(scheme)
        }
    }

    var body: some View {
        let passed = row.kind == .passed
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(passed ? Palette(scheme: scheme).track : color)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label.uppercased())
                        .font(.small).fontWeight(.bold)
                        .tracking(0.4)
                        .foregroundStyle(color)
                    Text(row.time)
                        .font(.bodyEmphasis)
                        .strikethrough(passed)
                        .foregroundStyle(passed ? Palette(scheme: scheme).tertiary : Palette(scheme: scheme).primary)
                }
                Text(row.note).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let topic = row.topic {
                InfoButton(topic: topic).padding(.top, -10)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Subviews

private struct ExamMorningChart: View {
    var window: TimeRange
    var wake: Minutes
    var groggyEnd: Minutes
    var examStart: Minutes
    var selected: Int?
    @Binding var selection: Int?
    var summary: String
    @Environment(\.colorScheme) private var scheme

    private var lo: Int { min(window.start, wake) - 20 }
    private var hi: Int { max(examStart, groggyEnd) + 15 }

    var body: some View {
        let p = Palette(scheme: scheme)
        Chart {
            RectangleMark(xStart: .value("From", window.start), xEnd: .value("To", window.end),
                          yStart: .value("Bottom", 0.0), yEnd: .value("Top", 1.0))
                .foregroundStyle(Accent.orange.fill(scheme).opacity(0.32))
                .cornerRadius(8)
            RectangleMark(xStart: .value("From", wake), xEnd: .value("To", groggyEnd),
                          yStart: .value("Bottom", 0.3), yEnd: .value("Top", 0.7))
                .foregroundStyle(Accent.indigo.fill(scheme).opacity(0.45))
            RuleMark(x: .value("Wake", wake))
                .foregroundStyle(p.primary)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            RuleMark(x: .value("Exam", examStart))
                .foregroundStyle(Accent.yellow.fill(scheme))
                .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round))
            if let selected {
                RuleMark(x: .value("Selected", min(max(selected, lo), hi)))
                    .foregroundStyle(p.primary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                PointMark(x: .value("Selected", min(max(selected, lo), hi)), y: .value("Mid", 0.5))
                    .symbolSize(90)
                    .foregroundStyle(p.primary)
            }
        }
        .chartScrub($selection, snapped: selected, feedbackKey: { $0 / 15 })
        .transaction(value: selected) { $0.animation = nil }
        .chartXScale(domain: lo...hi)
        .chartYScale(domain: 0.0...1.0)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: [lo, wake, examStart]) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(Clock.format(m, suffix: false)).font(.chartLabel(size: 11, weight: .semibold)).foregroundStyle(p.secondary)
                    }
                }
            }
        }
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(ClockChartDescriptor(
            title: "Exam morning", seriesName: "Morning", yTitle: "Step",
            points: [(window.start, 0), (wake, 1), (groggyEnd, 2), (examStart, 3)],
            yLabel: { ["Smart alarm window opens", "Up", "Clear-headed", "Exam starts"][min(max(Int($0.rounded()), 0), 3)] }))
    }
}

private struct ExamOption: View {
    var course: String
    var kind: String
    var when: String
    var selected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(course).font(.bodyEmphasis)
                Text(kind).font(.secondary).fontWeight(.semibold)
                    .foregroundStyle(selected ? Accent.yellow.ink(scheme) : p.secondary)
                Text(when).font(.secondary).foregroundStyle(p.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(selected ? Accent.yellow.tint(scheme) : p.chip, in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
                .strokeBorder(selected ? Accent.yellow.fill(scheme) : p.cardBorder, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ExamDayTab: View {
    var day: String
    var date: String
    var key: String
    var isExam: Bool
    var selected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        let accent: Accent = isExam ? .yellow : .purple
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day).font(.bodyEmphasis)
                Text(date).font(.secondary).foregroundStyle(p.secondary)
                Text(key).font(.secondary).fontWeight(.bold).foregroundStyle(accent.ink(scheme))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(selected ? accent.tint(scheme) : p.chip, in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
                .strokeBorder(selected ? accent.fill(scheme) : p.cardBorder, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ExamLabeledValue: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.secondary).secondaryText()
            Text(value).font(.numberM)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ExamWhyRow: View {
    var systemImage: String
    var accent: Accent
    var title: String
    var detail: String
    var topic: Topic
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.bodyEmphasis)
                .foregroundStyle(accent.ink(scheme))
                .frame(width: Sizes.icon, height: Sizes.icon)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(title).font(.bodyEmphasis)
                    InfoButton(topic: topic).padding(.vertical, -12)
                }
                Text(detail).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
