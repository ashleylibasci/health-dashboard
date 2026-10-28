import SwiftUI
import UIKit
import HealthCore

/// The home screen: recovery (Today owns it), tonight's plan and today at a
/// glance. One ⓘ per card; the details live on the screens each card opens.
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openTab) private var openTab

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

    var body: some View {
        Screen(accent: .indigo) {
            TabHeader(greeting)
            SampleDataBanner(prominent: true)
            PackCheckCard()
            examChip
            if showsCheckIn {
                checkInPrompt
            }
            if showSickCard {
                sickCard
            }
            if !model.lastNightIsFresh {
                noSleepCard
            }
            recoveryCard
            if showWhyOffUpTop {
                whyOffLink
            }
            tonightCard
            glanceHeader
            tiles
            moreCard
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
        let part = model.greetingPart
        return name.isEmpty ? part : "\(part), \(name)"
    }

    // MARK: Exam chip

    /// Her next exam (only exams she added; never examples).
    private var nextExam: UpcomingExam? { model.upcomingExams.first }

    private var examChipText: String {
        guard let exam = nextExam else { return "Add an exam" }
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
            if nextExam != nil { ExamWeekView() } else { ExamListView() }
        } label: {
            InfoPill(systemImage: "calendar", iconColor: Accent.yellow.ink(scheme), text: examChipText, showsChevron: true)
        }
        .buttonStyle(.pressable)
        .accessibilityHint(nextExam == nil ? "Add your exams" : "Opens your exam week plan")
    }

    // MARK: Check-in prompt

    /// From waking until noon (or two hours after a late wake), and only
    /// here on Today (Whitfield F11). The Log tab keeps its own check-in.
    private var showsCheckIn: Bool {
        guard model.canCheckInNow, !model.checkInDoneToday else { return false }
        let wake = model.lastNightIsFresh ? model.lastNight.wake : 0
        return model.now < max(12 * 60, wake + 120)
    }

    private var checkInPrompt: some View {
        let p = Palette(scheme: scheme)
        return NavigationLink {
            CheckInView()
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "sun.horizon.fill")
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(Accent.orange.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Morning check-in").font(.bodyEmphasis)
                    Text("How awake do you feel? Takes 10 seconds.")
                        .font(.secondary)
                        .foregroundStyle(p.secondary)
                }
                Spacer(minLength: Space.xs)
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(p.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(Space.m)
            .frame(minHeight: Sizes.tallRow)
            .tileSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: Recovery

    private var recoveryValue: Int? { model.recoveryShown }

    /// The longer note: what the score is compared with, and what moved it.
    /// Behind the card's ⓘ (Whitfield F6), not on the card.
    private var recoveryNote: String {
        var note = model.recoveryUsualNote
        if model.recoveryIsExample {
            note += " Example: it uses example heart readings until your Watch has learned your usual."
        } else if !model.hasHeartData {
            note += " No HRV or resting heart rate yet, so this is from sleep alone."
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

    /// One line under the label: "Below your usual of 78" (Valtonen F1).
    private var recoveryLine: String {
        guard let value = recoveryValue else { return "" }
        let usual = model.recoveryUsual
        let what = model.recoveryUsualIsPersonal ? "your usual of \(usual)" : "the starting point of \(usual)"
        if value <= usual - 5 { return "Below \(what)" }
        if value >= usual + 5 { return "Above \(what)" }
        return "Around \(what)"
    }

    private var recoveryExplanation: Explanation {
        let base = Topic.recovery.explanation
        return Explanation(id: "recovery-today", title: base.title, meaning: base.meaning,
                           forYou: recoveryNote + " " + base.forYou, howWeGotIt: base.howWeGotIt)
    }

    private var recoveryCard: some View {
        let p = Palette(scheme: scheme)
        let heart = model.hasHeartData
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
                        Ring(value: Double(value) / 100, accent: .indigo, label: "\(value)", caption: "Recovery", size: 120)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(model.recoveryLabel(for: value)).font(.heading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(recoveryLine)
                                .font(.secondary)
                                .foregroundStyle(p.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            // Below the title, so it never breaks the label
                            // ("Take it / steady") (Brennan F10).
                            if model.recoveryIsExample {
                                ExampleTag()
                            }
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
            if !heart {
                Text("HRV and resting heart rate: no reading yet. Your Watch measures HRV while you're still, often overnight, and resting heart rate from still moments during the day.")
                    .font(.secondary)
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Recovery drivers

    /// HRV, resting heart rate and sleep in their own colours (indigo, pink,
    /// purple), with the change in secondary text and a ▲/▼ that's coral
    /// only when it needs attention (Tanaka F2, Valtonen F4).
    private var gauges: some View {
        let heart = model.hasHeartData
        let fresh = model.lastNightIsFresh
        return AdaptiveStack(spacing: Space.s, alignment: .top) {
            MiniGauge(fraction: heart ? model.hrvGaugeFraction : 0, accent: .indigo,
                      value: heart ? "\(Int(model.hrv.rounded()))" : "\u{2014}", title: "HRV",
                      change: heart ? hrvChange : .none(text: "no reading"))
            MiniGauge(fraction: heart ? model.restingHRGaugeFraction : 0, accent: .pink,
                      value: heart ? "\(Int(model.restingHR.rounded()))" : "\u{2014}", title: "Resting HR",
                      change: heart ? restingHRChange : .none(text: "no reading"))
            MiniGauge(fraction: fresh ? Double(model.lastNight.asleep) / 540 : 0, accent: .purple,
                      // "7h 21m", as the Sleep screen says it (round 3).
                      value: fresh ? Clock.duration(model.lastNight.asleep) : "\u{2014}", title: "Sleep",
                      change: sleepChange)
        }
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

    // MARK: No sleep recorded

    private var noSleepCard: some View {
        let p = Palette(scheme: scheme)
        return Card {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: "moon.zzz")
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Accent.purple.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(Accent.purple.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("No sleep recorded last night").font(.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("Wear your Watch to bed and turn on Sleep Focus so it records your night.")
                        .font(.secondary)
                        .foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LinkRow(title: "How to get your sleep recorded", systemImage: "applewatch", accent: .purple) {
                AccuracyTipsView()
            }
        }
    }

    // MARK: Might be getting sick

    /// Whenever the sick check finds a couple of signs or several, so Today
    /// agrees with Body and "Why do I feel off?". On example data it says so.
    private var showSickCard: Bool { model.sickCheckFlagged }

    /// Counts signs; never "likely" (round 4, Liu 15).
    private var sickTitle: String {
        let title = model.illness.confidence == .high
            ? "Several signs your body may be fighting something"
            : "Your body may be fighting something"
        return model.usingSampleData ? "Example: " + title.prefix(1).lowercased() + title.dropFirst() : title
    }

    private var sickDetail: String {
        // Lowercase mid-sentence, but keep acronyms ("HRV", not "hrv").
        let flagged = model.illness.factors.filter(\.flagged).map { $0.name == $0.name.uppercased() ? $0.name : $0.name.lowercased() }
        var detail = flagged.isEmpty
            ? "Several of your signals moved at once."
            : "Your " + joined(flagged) + (flagged.count == 1 ? " is" : " are") + " off your usual."
        if model.hardTrainingYesterday {
            detail += model.hidesEffortTargets
                ? " Yesterday's extra activity is already allowed for."
                : " Yesterday's hard training is already allowed for."
        }
        if model.illness.cyclePhaseUnknown {
            detail += " The app can't tell which phase of your cycle you're in, so it didn't allow for one. Part of this could be your cycle."
        } else if model.inLutealPhase {
            detail += " The late part of your cycle is already allowed for."
        }
        return detail + " Take it easy, drink water and get extra sleep tonight."
    }

    private var sickCard: some View {
        let p = Palette(scheme: scheme)
        return Card(accent: .coral) {
            HStack(spacing: 0) {
                SectionLabel(text: "Sick check \u{00B7} \(model.illness.confidence.rawValue)", accent: .coral)
                Spacer(minLength: 0)
                InfoButton(topic: .illness).padding(.vertical, -14).padding(.trailing, -12)
            }
            .padding(.bottom, -Space.s)
            NavigationLink {
                SickView()
            } label: {
                HStack(alignment: .top, spacing: Space.m) {
                    Image(systemName: "thermometer.medium")
                        .font(.scaled(size: 16, weight: .semibold))
                        .foregroundStyle(Accent.coral.ink(scheme))
                        .frame(width: Sizes.icon, height: Sizes.icon)
                        .background(Accent.coral.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(sickTitle).font(.cardTitle)
                        Text(sickDetail)
                            .font(.secondary)
                            .foregroundStyle(p.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(p.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Sizes.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// "a", "a and b", "a, b and c".
    private func joined(_ xs: [String]) -> String {
        guard let last = xs.last else { return "" }
        if xs.count == 1 { return last }
        return xs.dropLast().joined(separator: ", ") + " and " + last
    }

    // MARK: Why do I feel off?

    private var showWhyOffUpTop: Bool {
        (recoveryValue.map { $0 < model.recoveryUsual } ?? false) || model.sleepDebt >= 60
    }

    private var whyOffSubtitle: String {
        if let top = model.whyOffReasons.first { return "Most likely: \(top.title.lowercased())" }
        return "The likeliest reasons, from your data"
    }

    private var whyOffLink: some View {
        Card(density: .compact) {
            LinkRow(title: "Why do I feel off?", subtitle: whyOffSubtitle,
                    systemImage: "questionmark.bubble.fill", accent: .coral) {
                WhyOffView()
            }
        }
    }

    // MARK: Tonight

    /// One recommendation, one bedtime and one wake time, and one line about
    /// the shortfall (Whitfield F1, Dubois 1, Valtonen F1). The full
    /// reasoning is behind the ⓘ and on the wake plan.
    private var tonightCard: some View {
        let tonight = model.tonightPlan
        let p = Palette(scheme: scheme)
        let bed = model.tonightAimBedtime
        let wake = tonight.wake ?? tonight.upBy
        return Card {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: "moon.stars.fill")
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Accent.purple.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(Accent.purple.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    CapsLabel("Tonight", color: Accent.purple.ink(scheme))
                    Text("Bed by \(Clock.format(bed))").font(.heading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Up at \(Clock.format(wake))").font(.bodyEmphasis)
                        .foregroundStyle(p.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                InfoButton(explanation: tonightExplanation).padding(.vertical, -10).padding(.trailing, -12)
            }
            Text(tonightLine)
                .font(.bodyText)
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    alarmChip(tonight)
                    Spacer(minLength: 0)
                    whyThisTimeLink
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    alarmChip(tonight)
                    whyThisTimeLink
                }
            }
        }
    }

    /// "You need 8h 25m tonight. Bed at your usual 12:30am gets you about
    /// 7h 40m, 45 min short." The one asleep figure on the card.
    private var tonightLine: String {
        let t = model.tonightPlan
        let usual = Clock.format(t.bedtime)
        var line = "You need \(Clock.duration(t.need)) tonight. "
        if t.coversNeed {
            line += "Bed at \(usual) gets you about \(Clock.duration(t.expectedAsleep))."
        } else {
            line += "Bed at your usual \(usual) gets you about \(Clock.duration(t.expectedAsleep)), \(Clock.duration(t.shortfall)) short."
        }
        return line
    }

    private var tonightExplanation: Explanation {
        var forYou: [String] = []
        if let short = model.tonightShortNote { forYou.append(short) }
        if let wakes = model.wakeTimesExplained { forYou.append(wakes) }
        forYou.append("Tap the smart alarm button to turn the alarm on your Watch on or off. Your phone's alarms are never changed.")
        return Explanation(id: "tonight", title: "Tonight's plan",
                           meaning: "The bedtime that covers tonight's sleep need and the best time to wake tomorrow: the end of a sleep cycle that still lands before your latest wake-up. Tonight you need \(model.tonightNeedText).",
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
    /// Without a plan it opens the wake plan instead.
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

    private var whyThisTimeLink: some View {
        NavigationLink { WakePlanView() } label: {
            Text("Why this time")
                .font(.scaled(size: 13, weight: .semibold))
                .foregroundStyle(Accent.indigo.ink(scheme))
                .textLinkHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your wake plan")
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

    private var sleepDebtNote: String {
        if let score = model.sleepRegularityScore, model.lastNightIsFresh { return "Regularity \(score)" }
        return "Over the last 2 weeks"
    }

    /// Two columns, or one at accessibility text sizes so titles and
    /// values aren't cut off.
    @ViewBuilder
    private var tiles: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: Space.m) {
                sleepTile
                caffeineTile
                waterTile
                stressTile
            }
        } else {
            Grid(horizontalSpacing: Space.m, verticalSpacing: Space.m) {
                GridRow {
                    sleepTile
                    caffeineTile
                }
                GridRow {
                    waterTile
                    stressTile
                }
            }
        }
    }

    /// Switches to the Sleep tab instead of pushing a second Sleep screen
    /// onto Today (Whitfield F5).
    private var sleepTile: some View {
        Button { openTab(.sleep) } label: {
            MetricTile(title: "Sleep debt", value: sleepDebtValue, note: sleepDebtNote,
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
        WaterTile(todayML: model.waterTodayML, goalML: store.data.waterGoalML,
                  bottleML: store.data.bottleSizeML, showsGoal: !model.hidesEffortTargets) {
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

    // MARK: More

    private var moreCard: some View {
        Card(density: .compact) {
            if !showWhyOffUpTop {
                LinkRow(title: "Why do I feel off?", subtitle: "Check what might be behind a rough day",
                        systemImage: "questionmark.bubble.fill", accent: .coral) {
                    WhyOffView()
                }
                Divider().overlay(Palette(scheme: scheme).cardBorder)
            }
            LinkRow(title: "Getting accurate numbers", subtitle: "Simple ways to help your Watch",
                    systemImage: "checklist", accent: .indigo) {
                AccuracyTipsView()
            }
        }
        .padding(.top, Space.s)
    }
}

/// Water today in ounces, with a round "+" that adds one bottle.
private struct WaterTile: View {
    var todayML: Double
    var goalML: Double
    var bottleML: Double
    /// False with an eating-disorder history: the total only, no goal.
    var showsGoal: Bool
    var add: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var added = 0

    private var bottlesNote: String {
        guard bottleML > 0 else { return "" }
        let had = todayML / bottleML
        guard showsGoal else { return "\(LogFormat.bottlesPhrase(had)) today" }
        let goal = goalML / bottleML
        return "\(LogFormat.bottles(had)) of \(LogFormat.bottlesPhrase(goal))"
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
                    Text(bottlesNote).font(.secondary).foregroundStyle(p.secondary)
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(showsGoal ? "Water: \(LogFormat.oz(todayML)) of \(LogFormat.oz(goalML)), \(bottlesNote)" : "Water: \(LogFormat.oz(todayML)), \(bottlesNote)")
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
