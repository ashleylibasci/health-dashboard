import SwiftUI
import UIKit
import Charts
import HealthCore

/// The home screen, summary first: at most one line that needs her, then
/// recovery (Today owns it), tonight's plan and today at a glance, led by
/// whichever answers the question she has at this hour (D-T1). One ⓘ per
/// card; the details live on the screens each card opens.
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @ObservedObject private var calendar = CalendarImport.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openTab) private var openTab
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The smart alarm toggled from the Tonight card, kept for Undo.
    private struct AlarmUndo: Equatable {
        var enabled: Bool
        var override: AppData.AlarmOverride?
        var message: String
    }
    @State private var alarmUndo: AlarmUndo?
    @State private var toastTask: Task<Void, Never>?
    @State private var alarmTurnedOn = 0
    @State private var alarmUndone = 0
    /// The page the alert line opened.
    @State private var opened: Alert?
    /// The part of the day Today is laid out for. Set when the app opens,
    /// never while she's looking at it.
    @State private var moment: Moment?
    /// The app day the morning reveal last played (D-M2).
    @AppStorage("todayRevealDay") private var revealDay = ""
    /// True while the recovery ring waits, empty, for the reveal.
    @State private var revealing = false
    @State private var revealed = 0

    var body: some View {
        Screen(accent: .indigo, searches: true) {
            TabHeader(greeting)
            HelloCard()
            SampleDataBanner(prominent: true)
            if showsExamChip {
                examChip
            }
            alertSlot
            // Same cards, different order: the hero follows the clock, and
            // the pill sits under whichever card leads.
            switch shownMoment {
            case .morning:
                recoveryCard
                pillRow
                tonightCard
                glanceHeader
                tiles
            case .afternoon:
                glanceHeader
                tiles
                pillRow
                recoveryCard
                tonightCard
            case .evening:
                tonightCard
                pillRow
                recoveryCard
                glanceHeader
                tiles
            }
        }
        .onAppear {
            if moment == nil { moment = momentNow }
            revealIfFirstOpen()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            moment = momentNow
            revealIfFirstOpen()
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: revealed)
        .navigationDestination(item: $opened) { alert in
            switch alert {
            case .sick: SickView()
            case .calendar: ExamListView()
            case .noSleep: AccuracyTipsView()
            case .checkIn: CheckInView()
            }
        }
        .overlay(alignment: .bottom) {
            if let alarmUndo {
                undoToast(alarmUndo)
                    .motionTransition(.undo)
            }
        }
        .sensoryFeedback(.success, trigger: alarmTurnedOn)
        .sensoryFeedback(.impact(weight: .light), trigger: alarmUndone)
    }

    // MARK: Header

    private var name: String { (store.data.name ?? "").trimmingCharacters(in: .whitespaces) }

    /// By the real clock: "Good evening" at 9pm, "Still up" at 1am.
    private var greeting: String {
        let part = DemoMode.clock.map { AppModel.greetingPart(hour: $0 / 60 % 24) } ?? model.greetingPart
        return name.isEmpty ? part : "\(part), \(name)"
    }

    /// Now, in app-day minutes (`model.now`), or the `-demoClock` time.
    private var clock: Minutes { DemoMode.clock ?? model.now }

    // MARK: Following the clock

    /// Morning leads with how she slept and recovered; afternoon with
    /// energy now and the caffeine cutoff; evening with tonight.
    private enum Moment { case morning, afternoon, evening }

    /// Morning runs to noon, or two hours after a late wake (as the
    /// check-in does); evening from 7pm.
    private var momentNow: Moment {
        let wake = model.lastNightIsFresh ? model.lastNight.wake : 0
        if clock < max(12 * 60, wake + 120) { return .morning }
        return clock < 19 * 60 ? .afternoon : .evening
    }

    private var shownMoment: Moment { moment ?? momentNow }

    // MARK: Exam chip

    /// Her next exam (only exams she added; never examples).
    private var nextExam: UpcomingExam? { model.upcomingExams.first }

    /// Only for an exam in the next two weeks. Adding one lives with the
    /// exam list and the calendar in Settings, not on the home screen.
    private var showsExamChip: Bool { (nextExam?.daysUntil ?? .max) <= 14 }

    private var examChipText: String {
        guard let exam = nextExam else { return "" }
        let day: String
        switch exam.daysUntil {
        case 0: day = "today"
        case 1: day = "tomorrow"
        default: day = exam.date.formatted(.dateTime.weekday(.abbreviated))
        }
        return "\(exam.title) \u{00B7} \(day)"
    }

    /// The one chip left in the header row. Tonight's bedtime lives on the
    /// Tonight card only (Whitfield F6), so there's one bedtime on Today.
    private var examChip: some View {
        NavigationLink {
            ExamWeekView()
        } label: {
            InfoPill(systemImage: "calendar", iconColor: Accent.yellow.ink(scheme), text: examChipText, showsChevron: true)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens your exam week plan")
    }

    // MARK: The one alert line

    /// What the alert line can open.
    private enum Alert: Hashable, Identifiable {
        case sick, calendar, noSleep, checkIn
        var id: Self { self }
    }

    /// The pill pack question is the one thing that needs her.
    private var showsPackCheck: Bool {
        (model.packNeedsCheck && model.packCheckNewPackDate != nil)
            || (model.packBleedOutsideBreak && model.packBleedOutsideBreakDate != nil)
    }

    /// From waking until noon (or two hours after a late wake), and only
    /// here on Today (Whitfield F11). The Log tab keeps its own check-in.
    private var showsCheckIn: Bool {
        guard model.canCheckInNow, !model.checkInDoneToday else { return false }
        let wake = model.lastNightIsFresh ? model.lastNight.wake : 0
        return model.now < max(12 * 60, wake + 120)
    }

    /// The most pressing line, or nil: the sick check flagged something,
    /// then Google Calendar signed out, then no sleep from Apple Health,
    /// then the morning check-in. Only one shows at a time.
    private var alert: (Alert, text: String, systemImage: String, accent: Accent)? {
        if model.sickCheckFlagged { return (.sick, sickTitle, "thermometer.medium", .coral) }
        if calendar.needsSignIn { return (.calendar, "Google Calendar signed out \u{00B7} sign in again", "calendar.badge.exclamationmark", .yellow) }
        if !model.lastNightIsFresh { return (.noSleep, "No sleep recorded last night", "moon.zzz", .purple) }
        if showsCheckIn { return (.checkIn, "Morning check-in \u{00B7} takes 10 seconds", "sun.horizon.fill", .orange) }
        return nil
    }

    @ViewBuilder
    private var alertSlot: some View {
        if let alert, alert.0 == .sick {
            alertBar(alert)
        } else if model.morningAfterClear != nil {
            MorningAfterCallout()
        } else if showsPackCheck {
            PackCheckCard()
        } else if let alert {
            alertBar(alert)
        }
    }

    private func alertBar(_ alert: (Alert, text: String, systemImage: String, accent: Accent)) -> some View {
        CalloutBar(text: alert.text, systemImage: alert.systemImage, accent: alert.accent) { opened = alert.0 }
    }

    /// Counts signs; never "likely" (round 4, Liu 15).
    private var sickTitle: String {
        let title = model.illness.confidence == .high
            ? "Several signs your body may be fighting something"
            : "Your body may be fighting something"
        return model.usingSampleData ? "Example: " + title.prefix(1).lowercased() + title.dropFirst() : title
    }

    // MARK: Recovery

    private var recoveryValue: Int? { model.recoveryShown }

    /// The longer note: what the score is compared with, and what moved it.
    /// Behind the card's ⓘ (Whitfield F6), not on the card.
    private var recoveryNote: String {
        var note = recoveryUsualNote
        if model.recoveryIsExample {
            note += " Example: it uses example heart readings until your Watch has learned your usual."
        } else if !model.hasHeartData {
            note += " No HRV or resting heart rate yet, so this is from sleep alone. Your Watch measures HRV while you're still, often overnight, and resting heart rate from still moments during the day."
        } else if !model.lastNightIsFresh {
            note += " From your heart readings only; no sleep was recorded."
        } else if model.hrvLevel == .wellBelow || model.hrvLevel == .below {
            note += model.cycleHeartShift == .luteal ? " HRV dipped, which is normal in this part of your cycle and allowed for." : " HRV dipped below your usual."
        } else if model.restingHRLevel == .above {
            note += model.cycleHeartShift == .luteal
                ? " Resting heart rate is up a little, partly from this part of your cycle (allowed for)."
                : " Resting heart rate is up a little."
        } else if (recoveryValue ?? 0) >= model.recoveryUsual + 5 {
            note += " HRV and resting heart rate both look strong."
        } else {
            note += " HRV and resting heart rate look normal."
        }
        return note
    }

    /// How far she is toward her own usual, or nil on pure example data
    /// (the banner already says so). Her usual needs 14 nights of sleep
    /// before the app leaves example data, then 7 days of heart readings.
    private var learningUsual: String? {
        if model.usingSampleData {
            return model.realNightCount > 0 ? "\(min(model.realNightCount, AppModel.nightsNeeded - 1)) of \(AppModel.nightsNeeded) nights" : nil
        }
        return "\(min(model.recoveryDaysLearned, 6)) of 7 days"
    }

    /// Until she has her own usual: "a typical day", never "the starting
    /// point" (F8).
    private var recoveryUsualNote: String {
        guard !model.recoveryUsualIsPersonal else { return model.recoveryUsualNote }
        let learning = learningUsual.map { " (\($0) so far)" } ?? ""
        return "Compared with a typical day (\(model.recoveryUsual)) until your Watch learns your usual\(learning)."
    }

    /// The day in one plain sentence under the label (D-T4), joined from
    /// what Today already knows: "Short night, pill day 18. Bed by
    /// 11:50pm." How the score compares with her usual is in the ⓘ.
    private var daySentence: String {
        var facts: [String] = []
        if !model.lastNightIsFresh {
            facts.append("no sleep recorded")
        } else if model.lastNight.asleep - model.sleepNeed.minutes < -15 {
            facts.append("short night")
        } else {
            facts.append("full night")
        }
        if let pill = model.pillToday {
            facts.append(!pill.isPillDay ? model.packBreakName.lowercased()
                         : pill.isNewPack ? "new pack today" : "pill day \(pill.packDay)")
        }
        if nextExam?.daysUntil == 0 { facts.append("exam today") }
        let first = facts.joined(separator: ", ")
        let bed = 1440 + model.tonightBedtime
        let plan = clock < bed ? "Bed\u{00A0}by\u{00A0}\(Clock.format(bed))." : "Past your \(Clock.format(bed)) bedtime."
        return first.prefix(1).uppercased() + first.dropFirst() + ". " + plan
    }

    // MARK: Morning reveal

    /// The first open of the morning after a recorded night: the ring
    /// fills and the number counts up, with one soft tap (D-M2). Once per
    /// app day; with Reduce Motion the ring fades in instead.
    private func revealIfFirstOpen() {
        let day = model.appDayDate.formatted(.iso8601.year().month().day())
        guard shownMoment == .morning, model.lastNightIsFresh, recoveryValue != nil, revealDay != day else { return }
        revealDay = day
        revealing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .easeOut(duration: 0.9)) { revealing = false }
            revealed += 1
        }
    }

    private var recoveryExplanation: Explanation {
        let base = Topic.recovery.explanation
        return Explanation(id: "recovery-today", title: base.title, meaning: base.meaning,
                           forYou: recoveryNote + " " + base.forYou, howWeGotIt: base.howWeGotIt)
    }

    private var recoveryCard: some View {
        let p = Palette(scheme: scheme)
        return Card {
            HStack(spacing: 0) {
                SectionLabel(text: "Recovery today")
                Spacer(minLength: 0)
                InfoButton(explanation: recoveryExplanation).padding(.vertical, -14).padding(.trailing, -12)
            }
            .padding(.bottom, -Space.s)
            if let value = recoveryValue {
                NavigationLink {
                    RecoveryView()
                } label: {
                    AdaptiveStack(spacing: Space.l) {
                        let empty = revealing && !reduceMotion
                        Ring(value: empty ? 0 : Double(value) / 100, accent: .indigo, label: empty ? "0" : "\(value)",
                             caption: "Recovery", size: 104, accessibilityText: "Recovery: \(value)")
                            .opacity(revealing && reduceMotion ? 0 : 1)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(model.recoveryLabel(for: value)).font(.heading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(daySentence)
                                .font(.secondary)
                                .foregroundStyle(p.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if !typeSize.isAccessibilitySize {
                            Image(systemName: "chevron.right")
                                .font(.scaled(size: 13, weight: .semibold))
                                .foregroundStyle(p.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens recovery details")
            } else {
                Text("No recovery yet today").font(.heading)
                    .accessibilityAddTraits(.isHeader)
                Text("There's no sleep from last night and no HRV or resting heart rate yet. Wear your Watch to bed tonight.")
                    .font(.secondary)
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            gauges
            Divider().overlay(p.cardBorder)
            LinkRow(title: "Why do I feel off?", subtitle: whyOffSubtitle,
                    systemImage: "questionmark.bubble.fill", accent: .coral) {
                WhyOffView()
            }
        }
    }

    private var whyOffSubtitle: String {
        if let top = model.whyOffReasons.first { return "Most likely: \(top.title.lowercased())" }
        return "The likeliest reasons, from your data"
    }

    // MARK: Recovery drivers

    /// HRV, resting heart rate and sleep in their own colours (indigo, pink,
    /// purple), with the change in secondary text and a ▲/▼ that's coral
    /// only when it needs attention (Tanaka F2, Valtonen F4). Each opens
    /// its own screen; Sleep switches to the Sleep tab. At accessibility
    /// text sizes the dials stacked into a screen of rings, so they're
    /// rows there (F10).
    @ViewBuilder
    private var gauges: some View {
        if typeSize.isAccessibilitySize {
            gaugeRows
        } else {
            dials
        }
    }

    private var dials: some View {
        let heart = model.hasHeartData
        let fresh = model.lastNightIsFresh
        return AdaptiveStack(spacing: Space.s, alignment: .top) {
            NavigationLink {
                HeartMetricView(metric: .hrv)
            } label: {
                MiniGauge(fraction: heart ? model.hrvGaugeFraction : 0, accent: .indigo,
                          value: heart ? "\(Int(model.hrv.rounded()))" : "\u{2014}", title: "HRV",
                          change: heart ? hrvChange : .none(text: "no reading"))
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Opens HRV")
            NavigationLink {
                HeartMetricView(metric: .restingHR)
            } label: {
                MiniGauge(fraction: heart ? model.restingHRGaugeFraction : 0, accent: .pink,
                          value: heart ? "\(Int(model.restingHR.rounded()))" : "\u{2014}", title: "Resting HR",
                          change: heart ? restingHRChange : .none(text: "no reading"))
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Opens resting heart rate")
            Button { openTab(.sleep) } label: {
                MiniGauge(fraction: fresh ? Double(model.lastNight.asleep) / 540 : 0, accent: .purple,
                          // "7h 21m", as the Sleep screen says it (round 3).
                          value: fresh ? Clock.duration(model.lastNight.asleep) : "\u{2014}", title: "Sleep",
                          change: sleepChange)
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Opens the Sleep tab")
        }
    }

    private var gaugeRows: some View {
        let heart = model.hasHeartData
        let fresh = model.lastNightIsFresh
        let hrv = heart ? hrvChange : .none(text: "No reading")
        let resting = heart ? restingHRChange : .none(text: "No reading")
        let sleep = sleepChange
        return VStack(spacing: 0) {
            MetricRow(title: "HRV", note: hrv.sentence, value: heart ? "\(Int(model.hrv.rounded())) ms" : nil,
                      trend: hrv.rowTrend, systemImage: "waveform.path.ecg", accent: .indigo) {
                HeartMetricView(metric: .hrv)
            }
            RowDivider()
            MetricRow(title: "Resting HR", note: resting.sentence, value: heart ? "\(Int(model.restingHR.rounded())) bpm" : nil,
                      trend: resting.rowTrend, systemImage: "heart.fill", accent: .pink) {
                HeartMetricView(metric: .restingHR)
            }
            RowDivider()
            MetricRow(title: "Sleep", note: sleep.sentence, value: fresh ? Clock.duration(model.lastNight.asleep) : nil,
                      trend: sleep.rowTrend, systemImage: "bed.double.fill", accent: .purple) {
                openTab(.sleep)
            }
        }
        .padding(.horizontal, -Space.l)
    }

    private var hrvChange: GaugeChange {
        let v = Int(model.hrvDeltaPct.rounded())
        let tone: GaugeChange.Tone = model.hrvLevel == .wellBelow ? .worse : model.hrvLevel == .above ? .better : .neutral
        if v == 0 { return .none(text: "your usual") }
        return GaugeChange(up: v > 0, text: "\(abs(v))%", spoken: "\(abs(v))% \(v > 0 ? "above" : "below") your usual", tone: tone)
    }

    private var restingHRChange: GaugeChange {
        let v = Int(model.restingHRDelta.rounded())
        let level = model.restingHRLevel
        let tone: GaugeChange.Tone = level == .above || level == .wellBelow ? .worse : level == .below ? .better : .neutral
        if v == 0 { return .none(text: "your usual") }
        return GaugeChange(up: v > 0, text: "\(abs(v)) bpm",
                           spoken: "\(abs(v)) beats \(v > 0 ? "above" : "below") your usual", tone: tone)
    }

    /// Last night against her need: "34 min short", "on target", "1h 05m over".
    private var sleepChange: GaugeChange {
        guard model.lastNightIsFresh else { return .none(text: "none recorded") }
        let gap = model.lastNight.asleep - model.sleepNeed.minutes
        if gap < -15 {
            return GaugeChange(up: false, text: "\(Clock.duration(gap)) short",
                               spoken: "\(Clock.duration(gap)) short of your need", tone: gap <= -45 ? .worse : .neutral)
        }
        if gap > 15 {
            return GaugeChange(up: true, text: "\(Clock.duration(gap)) over",
                               spoken: "\(Clock.duration(gap)) more than your need", tone: .neutral)
        }
        return .none(text: "on target")
    }

    // MARK: Pill

    /// Today's pill under the hero, with one-tap Taken (D-T2). Only on a
    /// pack she's set (combined pill).
    @ViewBuilder
    private var pillRow: some View {
        if model.pillToday != nil {
            RowCard { PillTodayRow() }
        }
    }

    // MARK: Tonight

    /// The one bedtime and wake time (her best sleep times, the same the
    /// Sleep tab, the Watch and the smart alarm use). The reasoning is
    /// behind the ⓘ; the card opens the Sleep plan.
    private var tonightCard: some View {
        let tonight = model.tonightPlan
        let p = Palette(scheme: scheme)
        let wake = tonight.wake ?? tonight.upBy
        return Card {
            HStack(alignment: .top, spacing: 0) {
                NavigationLink {
                    WakePlanView()
                } label: {
                    HStack(alignment: .top, spacing: Space.m) {
                        Image(systemName: "moon.stars.fill")
                            .font(.scaled(size: 16, weight: .semibold))
                            .foregroundStyle(Accent.purple.ink(scheme))
                            .frame(width: Sizes.icon, height: Sizes.icon)
                            .background(Accent.purple.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            CapsLabel("Tonight", color: Accent.purple.ink(scheme))
                            Text("Bed by \(Clock.format(model.tonightBedtime))")
                                .font(typeSize.isAccessibilitySize ? .cardTitle : .heading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(tonightLine(wake: wake)).font(.bodyEmphasis)
                                .foregroundStyle(p.secondary)
                        }
                        Spacer(minLength: Space.s)
                        Image(systemName: "chevron.right")
                            .font(.scaled(size: 13, weight: .semibold))
                            .foregroundStyle(p.tertiary)
                            .padding(.top, Space.l)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens your sleep plan")
                InfoButton(explanation: tonightExplanation).padding(.vertical, -10).padding(.trailing, -12)
            }
            alarmChip(tonight)
        }
    }

    /// "Up at 8:30am", and in the evening the countdown first: "Bed in
    /// 2h 40m · up at 8:30am".
    private func tonightLine(wake: Minutes) -> String {
        let left = 1440 + model.tonightBedtime - clock
        guard shownMoment == .evening, left > 0 else { return "Up at \(Clock.format(wake))" }
        return "Bed in \(Clock.duration(left)) \u{00B7} up\u{00A0}at\u{00A0}\(Clock.format(wake))"
    }

    private var tonightExplanation: Explanation {
        var forYou: [String] = []
        if let earlier = BestTimesText.earlierReason(model) { forYou.append(earlier) }
        if let usual = model.usualBedtimeNote { forYou.append(usual) }
        if let short = model.tonightShortNote { forYou.append(short) }
        if let wakes = model.wakeTimesExplained { forYou.append(wakes) }
        forYou.append("Tap the smart alarm button to turn the alarm on your Watch on or off. Your phone's alarms are never changed.")
        return Explanation(id: "tonight", title: "Tonight's plan",
                           meaning: "The bedtime from your best sleep times, which covers tonight's sleep need, and the best time to wake tomorrow: the end of a sleep cycle that still lands before your latest wake-up. Tonight you need \(model.tonightNeedText).",
                           forYou: forYou.joined(separator: " "))
    }

    private enum AlarmState { case on, offForWeekend, off }

    private var alarmState: AlarmState {
        guard store.data.smartAlarmEnabled else { return .off }
        if store.data.alarmWeekdaysOnly && Calendar.current.isDateInWeekend(model.nextWakeDay) && model.activeAlarmOverride == nil {
            return .offForWeekend
        }
        return .on
    }

    /// Turns the smart alarm on or off right here, with Undo (Whitfield F2).
    /// Without a plan it opens the sleep plan instead.
    @ViewBuilder
    private func alarmChip(_ tonight: TonightPlan) -> some View {
        let p = Palette(scheme: scheme)
        if let window = tonight.alarmWindow {
            let state = alarmState
            let on = state == .on
            let text: String = switch state {
            case .on: "Smart alarm on \u{00B7} by\u{00A0}\(Clock.format(window.end))"
            case .offForWeekend: "Smart alarm off for the weekend"
            case .off: "Smart alarm is off"
            }
            Button { toggleAlarm() } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: on ? "alarm.fill" : "alarm")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Accent.orange.onTint(scheme) : p.secondary)
                        .accessibilityHidden(true)
                    Text(text).font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Accent.orange.onTint(scheme) : p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.m)
                .frame(minHeight: Font.scaledSize(32))
                .background(on ? Accent.orange.fill(scheme).opacity(0.2) : p.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.clear : p.cardBorder))
                .motion(.select, value: on)
                .frame(minHeight: Sizes.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Smart alarm")
            .accessibilityValue(state == .on ? "On, wakes you by \(Clock.format(window.end))" : state == .offForWeekend ? "Off for the weekend" : "Off")
            .accessibilityHint(store.data.smartAlarmEnabled ? "Turns the smart alarm off" : "Turns the smart alarm on")
        } else {
            NavigationLink { WakePlanView() } label: {
                Label("Plan your wake time", systemImage: "alarm")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.orange.onTint(scheme))
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: Font.scaledSize(32))
                    .background(Accent.orange.fill(scheme).opacity(0.2), in: Capsule())
                    .frame(minHeight: Sizes.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
    }

    private func toggleAlarm() {
        let before = (enabled: store.data.smartAlarmEnabled, override: store.data.alarmOverride)
        let message: String
        if store.data.smartAlarmEnabled {
            store.data.smartAlarmEnabled = false
            model.pushToWatch()
            message = "Smart alarm off"
        } else if let plan = model.wakePlan() {
            model.setSmartAlarm(from: plan)
            alarmTurnedOn += 1
            message = "Smart alarm on \u{00B7} wakes you by \(Clock.format(plan.alarmWindow.end))"
        } else {
            return
        }
        UIAccessibility.post(notification: .announcement, argument: message)
        showToast(AlarmUndo(enabled: before.enabled, override: before.override, message: message))
    }

    private func undoAlarm(_ undo: AlarmUndo) {
        store.data.alarmOverride = undo.override
        store.data.smartAlarmEnabled = undo.enabled
        model.pushToWatch()
        alarmUndone += 1
        toastTask?.cancel()
        withMotion(.undo) { alarmUndo = nil }
    }

    private func showToast(_ undo: AlarmUndo) {
        toastTask?.cancel()
        withMotion(.undo) { alarmUndo = undo }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withMotion(.undo) { alarmUndo = nil }
        }
    }

    private func undoToast(_ undo: AlarmUndo) -> some View {
        let p = Palette(scheme: scheme)
        return HStack(spacing: Space.m) {
            Image(systemName: "alarm.fill")
                .foregroundStyle(Accent.orange.ink(scheme))
                .accessibilityHidden(true)
            Text(undo.message).font(.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            Button("Undo") { undoAlarm(undo) }
                .font(.bodyEmphasis)
                .foregroundStyle(Accent.indigo.ink(scheme))
                .frame(minWidth: Sizes.minTap, minHeight: Sizes.minTap)
                .contentShape(Rectangle())
        }
        .padding(.leading, Space.l)
        .padding(.trailing, Space.s)
        .padding(.vertical, Space.xs)
        .background(scheme == .dark ? Color(hex: 0x24263A) : .white, in: Capsule())
        .overlay(Capsule().strokeBorder(p.cardBorder))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.m)
        .foregroundStyle(p.primary)
    }

    // MARK: At a glance

    private var glanceHeader: some View {
        // Last night's sleep and today's drinks, water and stress: not a
        // week (round 3). The week is behind "Your week".
        SectionHeading(text: "At a glance") {
            NavigationLink {
                WeekRecapView()
            } label: {
                Text("Your week")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .textLinkHitArea()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Tiles

    private var caffeineValue: String {
        let mg = model.todaysDrinks.map(\.mg).reduce(0, +)
        return model.todaysDrinks.isEmpty ? "None yet" : "\(mg) mg"
    }

    private var caffeineNote: String {
        let count = model.todaysDrinks.count
        if shownMoment == .afternoon, let cutoff = model.caffeineCutoffShown {
            let drinks = count == 0 ? "" : (count == 1 ? "1 drink" : "\(count) drinks") + " \u{00B7} "
            return drinks + (count == 0 ? "Cutoff" : "cutoff") + " \(Clock.format(cutoff))"
        }
        if count == 0 { return "Tap to log coffee or tea" }
        return (count == 1 ? "1 caffeine drink" : "\(count) caffeine drinks") + " \u{00B7} tap to edit"
    }

    /// How she said she feels comes first; the body signals second, as a
    /// band only (round 4, Laurent F2, Liu 9).
    private var stressValue: String {
        if let felt = model.stressLoggedToday { return "Felt \(felt)/5" }
        if let label = model.stressToday.label { return label.rawValue }
        return "No data yet"
    }

    private var stressNote: String {
        if let label = model.stressToday.label {
            return model.stressLoggedToday != nil ? "Body signals: \(label.rawValue.lowercased())" : "Body signals at rest"
        }
        if model.stressLoggedToday != nil { return "What you logged today" }
        return model.restingHRBaselineKnown ? "Wear your Watch today" : "Learning your resting heart rate"
    }

    /// Sleep debt, not last night again: the recovery card already shows
    /// last night's sleep (Whitfield F3).
    private var sleepDebtValue: String {
        model.sleepDebt >= 15 ? Clock.duration(model.sleepDebt) : "None"
    }

    /// Two columns, or one at accessibility text sizes so titles and
    /// values aren't cut off. In the afternoon energy now and caffeine
    /// come first.
    @ViewBuilder
    private var tiles: some View {
        let afternoon = shownMoment == .afternoon
        if typeSize.isAccessibilitySize {
            VStack(spacing: Space.m) {
                if afternoon {
                    fourthTile
                    caffeineTile
                    waterTile
                    sleepTile
                } else {
                    sleepTile
                    caffeineTile
                    waterTile
                    fourthTile
                }
            }
        } else {
            Grid(horizontalSpacing: Space.m, verticalSpacing: Space.m) {
                if afternoon {
                    GridRow {
                        fourthTile
                        caffeineTile
                    }
                    GridRow {
                        waterTile
                        sleepTile
                    }
                } else {
                    GridRow {
                        sleepTile
                        caffeineTile
                    }
                    GridRow {
                        waterTile
                        fourthTile
                    }
                }
            }
        }
    }

    /// Stress in the morning; from noon, energy now takes its slot (D-T3):
    /// the most "right now" number, otherwise two taps deep on Body.
    @ViewBuilder
    private var fourthTile: some View {
        if clock >= 12 * 60 {
            energyTile
        } else {
            stressTile
        }
    }

    private var energyTile: some View {
        NavigationLink {
            EnergyView()
        } label: {
            EnergyNowTile(energy: model.energyToday, now: clock, moment: model.energyMoment(at: clock, in: model.energyToday))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens your energy curve for today")
    }

    /// Switches to the Sleep tab instead of pushing a second Sleep screen
    /// onto Today (Whitfield F5).
    private var sleepTile: some View {
        Button { openTab(.sleep) } label: {
            MetricTile(title: "Sleep debt", value: sleepDebtValue, note: "Over the last 2 weeks",
                       accent: .purple, systemImage: "moon.zzz.fill")
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens the Sleep tab")
    }

    private var caffeineTile: some View {
        NavigationLink {
            CaffeineView()
        } label: {
            MetricTile(title: "Caffeine", value: caffeineValue, note: caffeineNote,
                       accent: .yellow, systemImage: "cup.and.saucer.fill")
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens caffeine, where you can log coffee or tea and change the times")
    }

    private var waterTile: some View {
        WaterTile(todayML: model.waterTodayML, goalML: model.waterGoalTodayML,
                  bottleML: store.data.bottleSizeML, paceML: model.waterPace(at: clock),
                  showsGoal: !model.hidesEffortTargets) {
            withMotion(.log) { model.addWater() }
        }
    }

    private var stressTile: some View {
        NavigationLink {
            StressView()
        } label: {
            MetricTile(title: "Stress", value: stressValue, note: stressNote,
                       accent: .orange, systemImage: "waveform.path")
        }
        .buttonStyle(.pressable)
    }
}

/// Water today in ounces, with a round "+" that adds one bottle.
private struct WaterTile: View {
    var todayML: Double
    var goalML: Double
    var bottleML: Double
    /// What a steady pace would have reached by now.
    var paceML: Double
    /// False with an eating-disorder history: the total only, no goal.
    var showsGoal: Bool
    var add: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var added = 0

    /// The steady pace by now (F7): the bottles line said the amount
    /// again. Nothing once the goal is reached, before waking, or without a
    /// goal.
    private var paceNote: String? {
        guard showsGoal, todayML < goalML, paceML >= LogFormat.mlPerOunce else { return nil }
        return "Pace: \(LogFormat.oz(paceML)) by now"
    }

    private var amount: String {
        showsGoal ? "\(LogFormat.ozNumber(todayML)) of \(LogFormat.oz(goalML))" : LogFormat.oz(todayML)
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                WaterView()
            } label: {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Water").font(.bodyEmphasis)
                        .padding(.trailing, Sizes.minTap)
                    Text(amount)
                        .font(.numberL).minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .motion(.fill, value: amount)
                    if let paceNote {
                        Text(paceNote).font(.secondary).foregroundStyle(p.secondary)
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(showsGoal ? "Water: \(LogFormat.oz(todayML)) of \(LogFormat.oz(goalML))" + (paceNote.map { ", \($0)" } ?? "") : "Water: \(LogFormat.oz(todayML))")
            .accessibilityHint(showsGoal ? "Opens water, where you can change your bottle size and goal" : "Opens water, where you can change your bottle size")
            Button {
                added += 1
                add()
            } label: {
                Image(systemName: "plus")
                    .font(.scaled(size: 15, weight: .bold))
                    .foregroundStyle(Accent.blue.onTint(scheme))
                    .frame(width: 32, height: 32)
                    .background(Accent.blue.fill(scheme).opacity(0.2), in: Circle())
                    .symbolEffect(.bounce, value: added)
                    .frame(width: Sizes.minTap, height: Sizes.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .sensoryFeedback(.increase, trigger: added)
            .padding(.top, Space.xs)
            .padding(.trailing, Space.xs)
            .accessibilityLabel("Add one bottle of water, \(LogFormat.oz(bottleML))")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tileSurface()
    }
}

/// Energy now as a tile (D-T3): the curve's level now, a 56pt curve of the
/// day with a "now" dot, and where she is ("Afternoon dip till 6:07pm").
/// The same "now" as the readout on Energy.
private struct EnergyNowTile: View {
    var energy: EnergyDay
    var now: Minutes
    var moment: AppModel.EnergyMoment
    @Environment(\.colorScheme) private var scheme

    private var start: Minutes { energy.curve.first?.time ?? 420 }
    private var end: Minutes { max(energy.curve.last?.time ?? 1560, start + 60) }
    private var nowTime: Minutes { min(max(now, start), end) }

    /// "Afternoon dip till 6:07pm" inside a zone, otherwise the moment's
    /// own name ("Climbing out of the dip").
    private var whereNow: String {
        guard let zone = AppModel.zone(at: moment.time, in: energy) else { return moment.title }
        return "\(AppModel.zoneTitle(zone)) till\u{00A0}\(Clock.format(zone.range.end))"
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        let line = Accent.mint.fill(scheme)
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("Energy now").font(.bodyEmphasis)
                Spacer(minLength: 0)
                Image(systemName: "bolt.fill")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.mint.ink(scheme))
                    .accessibilityHidden(true)
            }
            Text("\(moment.level)")
                .font(.numberL)
                .lineLimit(1)
            Chart {
                ForEach(energy.curve, id: \.time) { point in
                    AreaMark(x: .value("Time", point.time), y: .value("Energy", point.level))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [line.opacity(0.3), line.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                }
                ForEach(energy.curve, id: \.time) { point in
                    LineMark(x: .value("Time", point.time), y: .value("Energy", point.level))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(line)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                if let level = energy.level(at: nowTime) {
                    PointMark(x: .value("Now", nowTime), y: .value("Energy", level))
                        .symbolSize(60)
                        .foregroundStyle(p.primary)
                }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: -8.0...112.0)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 56)
            .accessibilityHidden(true)
            Text(whereNow).font(.secondary).foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tileSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Energy now: \(moment.level) of 100, \(whereNow)")
    }
}

/// A small rounded pill with an icon, used for the header chip.
private struct InfoPill: View {
    var systemImage: String
    var iconColor: Color
    var text: String
    var showsChevron: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.scaled(size: 12, weight: .bold))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(text).font(.scaled(size: 13, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 11, weight: .bold))
                    .foregroundStyle(p.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(minHeight: Font.scaledSize(32))
        .background(p.chip, in: Capsule())
        .overlay(Capsule().strokeBorder(p.cardBorder))
        .frame(minHeight: Sizes.minTap)
        .contentShape(Rectangle())
    }
}

/// How a recovery driver moved: an arrow, a short amount and what VoiceOver
/// says. The arrow is coral only when it needs attention, mint when it's
/// better than usual; the words stay secondary.
private struct GaugeChange {
    enum Tone { case worse, better, neutral }
    var up: Bool?
    var text: String
    var spoken: String
    var tone: Tone

    static func none(text: String) -> GaugeChange {
        GaugeChange(up: nil, text: text, spoken: text, tone: .neutral)
    }

    /// The row note at accessibility sizes: "6% below your usual".
    var sentence: String { spoken.prefix(1).uppercased() + spoken.dropFirst() }

    var rowTrend: RowTrend? {
        up.map { RowTrend(up: $0, tone: tone == .worse ? .worse : tone == .better ? .better : .neutral) }
    }
}

/// A 270-degree gauge with a number inside, for the recovery drivers. One
/// element for VoiceOver: "HRV 43, 6% below your usual".
private struct MiniGauge: View {
    var fraction: Double
    var accent: Accent
    var value: String
    var title: String
    var change: GaugeChange
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        // The dial grows with the text size (up to 90pt) so the number fits.
        let dial = min(max(56, Font.scaledSize(56)), 90)
        VStack(spacing: Space.xxs) {
            ZStack {
                Circle()
                    .inset(by: 3)
                    .trim(from: 0, to: 0.75)
                    .stroke(accent.track(scheme), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .inset(by: 3)
                    .trim(from: 0, to: 0.75 * max(0.02, min(fraction, 1)))
                    .stroke(accent.fill(scheme), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .opacity(fraction > 0 ? 1 : 0)
                    .motion(.fill, value: fraction)
                // One size for every dial's number (Brennan F10); a long
                // one shrinks to fit rather than switching sizes.
                Text(value)
                    .font(.scaledNumber(17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 9)
            }
            .frame(width: dial, height: dial)
            Text(title).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
                .lineLimit(2).minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            HStack(spacing: 3) {
                if let up = change.up {
                    Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.scaled(size: 8, weight: .bold))
                        .foregroundStyle(arrowColor(p))
                }
                Text(change.text).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value), \(change.spoken)")
    }

    private func arrowColor(_ p: Palette) -> Color {
        switch change.tone {
        case .worse: Accent.coral.ink(scheme)
        case .better: Accent.mint.ink(scheme)
        case .neutral: p.tertiary
        }
    }
}
