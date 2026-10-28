import SwiftUI
import Charts
import HealthCore

/// Exam-week mode: protects sleep before an exam, plans study into her peaks
/// and plans the exam morning.
struct ExamModeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var examID: String? = nil
    @State private var dayIndex = 0
    @State private var alarmSetFor: Set<String> = []
    @State private var morningSelection: Int? = nil

    /// ExamPlanner's cycle length (its default).
    private let cycle = 92
    /// Minutes from waking until grogginess clears after a light-sleep wake.
    private let grogginess = 40

    var body: some View {
        let all = model.examsToShow
        Screen(title: "Exam-week mode", accent: .yellow) {
            SampleDataBanner()
            if let exam = all.first(where: { $0.id == examID }) ?? all.first {
                let plan = ExamPlanner.plan(examStart: exam.start, daysUntil: min(exam.daysUntil, 2),
                                            usualBedtime: store.data.bedtime, need: model.tonightNeed.total,
                                            energyTemplate: model.energyToday, caffeineCutoff: model.caffeineCutoff)
                let index = min(max(dayIndex, 0), max(plan.count - 1, 0))
                modeCard(exam)
                if store.data.examModeOn {
                    examPicker(all, selected: exam)
                    countdownCard(exam, plan: plan)
                    planSection(exam, plan: plan, index: index)
                    if let examDay = plan.last {
                        morningCard(exam, day: examDay)
                    }
                } else {
                    offCard(all)
                }
            } else {
                noExamsCard
            }
            whyCard
            linksCard
        }
    }

    private var noExamsCard: some View {
        Card(accent: .yellow) {
            Text("No exams on your list").font(.scaled(size: 17, weight: .bold))
            Text("Add an exam and exam mode plans your sleep, study blocks and exam-morning alarm around it.")
                .font(.scaled(size: 14)).secondaryText()
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
                        .font(.scaled(size: 17, weight: .semibold))
                        .foregroundStyle(Accent.yellow.ink(scheme))
                        .frame(width: 40, height: 40)
                        .background(Accent.yellow.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exam mode").font(.scaled(size: 17, weight: .bold))
                        Text(on ? "On · planning for \(exam.course)" : "Off")
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(on ? Accent.yellow.ink(scheme) : Palette(scheme: scheme).secondary)
                    }
                }
            }
            .tint(Accent.yellow.fill(scheme))
            .frame(minHeight: 44)
            Text("Plans your sleep and study blocks around your exam, and can send a one-off smart alarm window for exam morning to your Watch.")
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if exam.isExample {
                HStack(spacing: 8) {
                    ExamExampleTag()
                    Text("Add your own exams to plan for them.").font(.scaled(size: 13)).secondaryText()
                }
            }
        }
    }

    private func offCard(_ all: [UpcomingExam]) -> some View {
        let list = all.map { "\($0.course) on \(shortDate($0.date))" }
        let joined = list.count > 1 ? list.dropLast().joined(separator: ", ") + " and " + (list.last ?? "") : (list.first ?? "")
        return Card {
            Text("Exam mode is off").font(.scaled(size: 17, weight: .bold))
            Text("\(joined) \(all.count == 1 ? "is" : "are") on your list. Turn exam mode on to plan sleep and study around \(all.count == 1 ? "it" : "them").")
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Exam picker + countdown

    private func examPicker(_ all: [UpcomingExam], selected: UpcomingExam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Upcoming exams".uppercased(), systemImage: "calendar")
                .font(.scaled(size: 12, weight: .bold))
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
            NavigationLink { ExamListView() } label: {
                Text(selected.isExample ? "Add your exams" : "Add or change exams")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func countdownCard(_ exam: UpcomingExam, plan: [ExamDayPlan]) -> some View {
        let days = exam.daysUntil
        let big: String = days == 0 ? "Today" : "\(days)"
        let unit: String
        if days == 0 { unit = "exam day" } else if days <= 7 { unit = days == 1 ? "night of sleep" : "nights of sleep" } else { unit = "days" }
        let tonight = plan.first { $0.dayOffset == -days + 1 }
        let bedTonight = tonight?.bedtimeBefore ?? store.data.bedtime
        let fallBack = model.nextFallBack
        let changeBeforeExam = fallBack > Calendar.current.startOfDay(for: .now) && fallBack <= exam.date
        let t1Value: String
        let t1Label: String
        let t2Value: String
        let t2Label: String
        if days <= 2 {
            let studyDays = plan.filter { $0.dayOffset < 0 && $0.dayOffset > -days }
            if studyDays.isEmpty {
                t1Value = "Today"
                t1Label = "your last study day"
            } else {
                let names = studyDays.map { weekdayName(dayDate(exam, $0.dayOffset)) }.joined(separator: " and ")
                let blocks = studyDays.map(\.studyBlocks.count).reduce(0, +)
                t1Value = studyDays.count == 1 ? "1 study day" : "\(studyDays.count) study days"
                t1Label = "\(names), \(blocks) peak \(blocks == 1 ? "block" : "blocks")"
            }
            t2Value = Clock.format(bedTonight)
            t2Label = "bed tonight"
        } else {
            t1Value = plan.first.map { shortDate(dayDate(exam, $0.dayOffset)) } ?? "–"
            t1Label = "\(plan.count)-day lead-up starts"
            if changeBeforeExam {
                t2Value = shortDate(fallBack)
                t2Label = "clocks fall back 1 hour"
            } else {
                t2Value = Clock.format(store.data.bedtime)
                t2Label = "bed tonight"
            }
        }
        return Card(accent: .yellow) {
            SectionLabel(text: "Countdown", accent: .yellow)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(big).font(.scaledNumber(48))
                Text(unit).font(.scaled(size: 17, weight: .bold)).foregroundStyle(Accent.yellow.ink(scheme))
            }
            .accessibilityElement(children: .combine)
            Text("Until your \(exam.title), \(shortDate(exam.date)) at \(Clock.format(exam.start)).")
                .font(.scaled(size: 14)).secondaryText()
            HStack(spacing: 10) {
                ExamCountTile(value: t1Value, label: t1Label)
                ExamCountTile(value: t2Value, label: t2Label)
            }
            .fixedSize(horizontal: false, vertical: true)
            if changeBeforeExam {
                LinkRow(title: "Clocks fall back \(shortDate(fallBack))",
                        subtitle: "Your body runs an hour ahead of the clock for a few days. Plan around it.",
                        systemImage: "clock.arrow.circlepath", accent: .indigo) { TimeChangeView() }
            } else {
                let upNext = tonight?.wake ?? model.wakePlan()?.wake ?? 502
                LinkRow(title: "Tonight: wind down from \(Clock.format(bedTonight - 60))",
                        subtitle: "Bed by \(Clock.format(bedTonight)), up at \(Clock.format(upNext)).",
                        systemImage: "moon.fill", accent: .orange) { WakePlanView() }
            }
        }
    }

    // MARK: Day plan

    private func planSection(_ exam: UpcomingExam, plan: [ExamDayPlan], index: Int) -> some View {
        let first = plan.first.map { shortDate(dayDate(exam, $0.dayOffset)) } ?? ""
        let last = plan.last.map { shortDate(dayDate(exam, $0.dayOffset)) } ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plan to exam day").font(.scaled(size: 20, weight: .bold))
                Spacer()
                Text(first == last ? first : "\(first) – \(last)").font(.scaled(size: 13)).secondaryText()
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
            let asleep = next.wake - next.bedtimeBefore - 12
            sleep = asleep
            let cycles = asleep / cycle
            let short = need - asleep
            note = short > 5
                ? "\(cycles) full cycles, \(Clock.duration(short)) under tonight's need."
                : "\(cycles) full cycles, enough to cover your need."
            if next.dayOffset == 0 {
                note += " Another cycle would end at \(Clock.format(next.wake + cycle)), too close to the \(exam.kind.lowercased())."
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
                    Text(date.formatted(.dateTime.weekday(.wide))).font(.scaled(size: 17, weight: .bold))
                    Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.scaled(size: 13)).secondaryText()
                }
                Spacer()
                Text(tagText)
                    .font(.scaled(size: 12, weight: .bold))
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
                            .font(.scaled(size: 13, weight: .bold))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Clock.duration(sleep)) asleep against a need of \(Clock.duration(need))")
                }
                Text(noteText).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(boxAccent.tint(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            ForEach(rows) { r in ExamPlanRowView(row: r) }
        }
    }

    private func planRows(_ exam: UpcomingExam, day d: ExamDayPlan, next: ExamDayPlan?) -> [ExamPlanRow] {
        var rows: [ExamPlanRow] = []
        let energy = model.energyToday
        if d.dayOffset == 0 {
            rows.append(ExamPlanRow(id: 0, kind: .exam, time: "\(Clock.format(exam.start)) · \(exam.title)",
                                note: "You're past grogginess (the foggy just-woke-up feeling) by about \(Clock.format(d.wake + grogginess)).", topic: .grogginess))
            let afterNote: String
            if let cutoff = model.caffeineCutoffShown {
                afterNote = "Nothing after \(Clock.format(cutoff))."
            } else {
                afterNote = "Keep it to one small drink (up to about \(model.caffeineLargestDoseAtWake) mg)"
                    + (model.caffeineLastsLonger ? ": on your birth control it lasts \(model.caffeineLongerPhrase)." : ".")
            }
            rows.append(ExamPlanRow(id: 1, kind: .caffeine, time: "Coffee around \(Clock.format(d.caffeineBy))",
                                note: "So it's working by \(Clock.format(exam.start)). \(afterNote)", topic: .caffeineCutoff))
            if let dip = energy.zone(.afternoonDip)?.range {
                rows.append(ExamPlanRow(id: 2, kind: .after, time: "\(dip.label) dip",
                                    note: "A 20-minute nap is fine, early in the dip. Turn exam mode off once the \(exam.kind.lowercased()) is done.", topic: .afternoonDip))
            }
            return rows
        }

        let isToday = d.dayOffset == -exam.daysUntil
        let bed = next?.bedtimeBefore ?? store.data.bedtime
        let stop = bed - 90
        let peak = energy.zone(.morningPeak)?.range
        var allPassed = true
        for (j, block) in d.studyBlocks.enumerated() {
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
        if isToday && allPassed {
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

    // MARK: Exam morning

    private func morningCard(_ exam: UpcomingExam, day d: ExamDayPlan) -> some View {
        let window = d.alarmWindow
        let cycles = max(1, (d.wake - d.bedtimeBefore - 12) / cycle)
        let sentEarlier: Bool = model.activeAlarmOverride.map {
            Calendar.current.isDate($0.wakeDay, inSameDayAs: exam.date) && $0.start == window.start && $0.end == window.end
        } ?? false
        let isSet = alarmSetFor.contains(exam.id) || sentEarlier
        let date = dayDate(exam, 0).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return Card(accent: .orange) {
            SectionLabel(text: "Exam morning · \(date)", accent: .orange)
            Text("Up \(Clock.format(d.wake)), clear-headed by \(Clock.format(d.wake + grogginess))")
                .font(.scaled(size: 20, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Your smart alarm wakes you in light sleep between \(Clock.format(window.start)) and \(Clock.format(window.end)), at the end of your \(ordinal(cycles)) cycle. Grogginess fades in about \(grogginess) minutes, well before \(Clock.format(exam.start)).")
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            morningReadout(exam, day: d)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            ExamMorningChart(window: window, wake: d.wake, groggyEnd: d.wake + grogginess, examStart: exam.start,
                             selected: morningSelection, selection: $morningSelection,
                             summary: "Exam morning: smart alarm window \(window.label), wake at \(Clock.format(d.wake)), grogginess for about \(grogginess) minutes, \(exam.title) at \(Clock.format(exam.start))")
                .frame(height: 90)
            ScrubHint()
            HStack(spacing: 0) {
                swatch(Accent.orange.fill(scheme).opacity(0.55), "Smart alarm window")
                InfoButton(topic: .smartAlarm)
                swatch(Accent.indigo.fill(scheme).opacity(0.45), "Grogginess")
                InfoButton(topic: .grogginess)
                swatch(Accent.yellow.fill(scheme), exam.kind)
            }
            if exam.isExample {
                Text("This is an example exam. Add your own to send its window to your Watch.")
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            } else if Calendar.current.isDate(exam.date, inSameDayAs: model.nextWakeDay) {
                PrimaryButton(title: isSet ? "Sent to your Watch: \(window.label)" : "Use this window on my Watch tonight",
                              accent: .orange, done: isSet) {
                    guard !isSet else { return }
                    alarmSetFor.insert(exam.id)
                    store.data.smartAlarmEnabled = true
                    model.pushToWatch(alarm: window, wakeDay: exam.date)
                }
            } else {
                Text("You can send this window to your Watch's smart alarm the night before.")
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            LinkRow(title: "How your wake window works", systemImage: "alarm.fill", accent: .orange) { WakePlanView() }
        }
    }

    private func morningReadout(_ exam: UpcomingExam, day d: ExamDayPlan) -> ChartReadout {
        let window = d.alarmWindow
        let groggyEnd = d.wake + grogginess
        let t = morningSelection.map { Int((Double($0) / 5).rounded()) * 5 } ?? d.wake
        let value: String
        let detail: String
        let accent: Accent
        if t < window.start {
            value = "Still asleep"
            detail = "Your smart alarm can start waking you from \(Clock.format(window.start)), as soon as you're in light sleep."
            accent = .purple
        } else if t < d.wake {
            value = "Smart alarm window"
            detail = "If you're in light sleep now, the alarm wakes you here instead of later. Waking from light sleep feels less groggy."
            accent = .orange
        } else if t < groggyEnd {
            value = t == d.wake ? "Up" : "Grogginess"
            detail = "Your brain takes about \(grogginess) minutes to fully switch on. Get daylight and water; skip last-minute cramming."
            accent = .indigo
        } else if t < exam.start {
            value = "Clear-headed"
            detail = "Grogginess has passed. Coffee around \(Clock.format(d.caffeineBy)) so it's working by the \(exam.kind.lowercased())."
            accent = .mint
        } else {
            value = "\(exam.kind) starts"
            detail = "\(exam.start - d.wake) minutes after waking: well past grogginess."
            accent = .yellow
        }
        return ChartReadout(title: Clock.format(t), value: value, detail: detail, accent: accent)
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.scaled(size: 12)).secondaryText().lineLimit(1)
        }
    }

    // MARK: Why + links

    private var whyCard: some View {
        let need = model.tonightNeed.total
        let lastNight = model.lastNight.asleep
        let scale = Double(max(need, lastNight, 1))
        return Card(accent: .purple) {
            Text("Why it matters").font(.scaled(size: 17, weight: .bold))
            ExamWhyRow(systemImage: "brain.head.profile", accent: .purple, title: "Short nights cost recall",
                   detail: "After a short night, memory and focus drop. Sleep is when what you studied gets stored, so an all-nighter takes back more than it gives.",
                   topic: .rem)
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
    }

    private var linksCard: some View {
        Card {
            LinkRow(title: "Where your peaks fall", subtitle: "Study blocks follow your morning peak and second wind.",
                    systemImage: "chart.xyaxis.line", accent: .mint) { EnergyView() }
            LinkRow(title: "Your wake plan", subtitle: "Tonight's best wake time and alarm window.",
                    systemImage: "alarm.fill", accent: .orange) { WakePlanView() }
            LinkRow(title: "Clock change", subtitle: "Clocks go back \(shortDate(model.nextFallBack)).",
                    systemImage: "clock.arrow.circlepath", accent: .indigo) { TimeChangeView() }
        }
    }

    // MARK: Helpers

    private func dayDate(_ exam: UpcomingExam, _ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: exam.date) ?? exam.date
    }

    private func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func weekdayName(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated))
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
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
                        .font(.scaled(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(color)
                    Text(row.time)
                        .font(.scaled(size: 15, weight: .bold))
                        .strikethrough(passed)
                        .foregroundStyle(passed ? Palette(scheme: scheme).tertiary : Palette(scheme: scheme).primary)
                }
                Text(row.note).font(.scaled(size: 13)).secondaryText()
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
        .chartScrub($selection)
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
                Text(course).font(.scaled(size: 16, weight: .bold))
                Text(kind).font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Accent.yellow.ink(scheme) : p.secondary)
                Text(when).font(.scaled(size: 12)).foregroundStyle(p.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(selected ? Accent.yellow.tint(scheme) : p.chip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                Text(day).font(.scaled(size: 15, weight: .bold))
                Text(date).font(.scaled(size: 12)).foregroundStyle(p.secondary)
                Text(key).font(.scaled(size: 12, weight: .bold)).foregroundStyle(accent.ink(scheme))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(selected ? accent.tint(scheme) : p.chip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? accent.fill(scheme) : p.cardBorder, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ExamCountTile: View {
    var value: String
    var label: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.scaled(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.scaled(size: 12)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ExamLabeledValue: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.scaled(size: 12)).secondaryText()
            Text(value).font(.scaledNumber(22))
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
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 36, height: 36)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(title).font(.scaled(size: 15, weight: .bold))
                    InfoButton(topic: topic).padding(.vertical, -12)
                }
                Text(detail).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
