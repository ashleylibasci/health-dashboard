import SwiftUI
import HealthCore

/// The home screen: recovery, tonight's plan and the week at a glance.
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Screen(accent: .indigo) {
            header
            SampleDataBanner(prominent: true)
            PackCheckCard()
            chips
            if model.canCheckInNow && !model.checkInDoneToday {
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
            weekHeader
            tiles
            moreCard
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var name: String { (store.data.name ?? "").trimmingCharacters(in: .whitespaces) }

    /// By the real clock: "Good evening" at 9pm, "Still up" at 1am.
    private var greeting: String {
        let part = model.greetingPart
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var header: some View {
        let p = Palette(scheme: scheme)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(.scaled(size: 13, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(p.secondary)
                Text(greeting)
                    .font(.scaled(size: 30, weight: .bold))
                    .tracking(-0.4)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            NavigationLink {
                SettingsView()
            } label: {
                Group {
                    if let initial = name.first {
                        Text(String(initial).uppercased()).font(.scaled(size: 16, weight: .bold))
                    } else {
                        Image(systemName: "person.fill").font(.scaled(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 44, height: 44)
                .background(Accent.coral.fill(scheme).opacity(0.22), in: Circle())
                .overlay(Circle().strokeBorder(p.cardBorder))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile and settings")
        }
        .padding(.top, 12)
    }

    // MARK: Chips

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

    /// Side by side when they fit; stacked at large text sizes, so neither is cut off.
    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                examChip
                bedChip
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 0) {
                examChip
                bedChip
            }
        }
    }

    private var examChip: some View {
        NavigationLink {
            if nextExam != nil { ExamWeekView() } else { ExamListView() }
        } label: {
            InfoPill(systemImage: "calendar", iconColor: Accent.yellow.ink(scheme), text: examChipText, showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint(nextExam == nil ? "Add your exams" : "Opens your exam week plan")
    }

    private var bedChip: some View {
        InfoPill(systemImage: "moon.fill", iconColor: Accent.purple.ink(scheme),
                 text: "Bed by \(Clock.format(store.data.bedtime))", showsChevron: false)
    }

    // MARK: Check-in prompt

    private var checkInPrompt: some View {
        let p = Palette(scheme: scheme)
        return NavigationLink {
            CheckInView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon.fill")
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .frame(width: 36, height: 36)
                    .background(Accent.orange.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Morning check-in").font(.scaled(size: 15, weight: .bold))
                    Text("How awake do you feel? Takes 10 seconds.")
                        .font(.scaled(size: 13))
                        .foregroundStyle(p.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 13, weight: .bold))
                    .foregroundStyle(p.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Accent.orange.tint(scheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Accent.orange.fill(scheme).opacity(0.22)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Recovery

    private var recoveryValue: Int? { model.recoveryShown }

    private var recoveryNote: String {
        var note = model.recoveryUsualNote
        if model.recoveryIsExample {
            note += " Example: it uses example heart readings until your Watch has learned your usual."
        } else if !model.hasHeartData {
            note += " No HRV or resting heart rate yet, so this is from sleep alone."
        } else if !model.lastNightIsFresh {
            note += " From your heart readings only; no sleep was recorded."
        } else if model.hrvDeltaPct <= -3 {
            note += model.isLateLuteal ? " HRV dipped, which is normal late in your cycle." : " HRV dipped below your usual."
        } else if model.restingHRDelta >= 3 {
            note += " Resting heart rate is up a little."
        } else if (recoveryValue ?? 0) >= model.recoveryUsual + 5 {
            note += " HRV and resting heart rate both look strong."
        } else {
            note += " HRV and resting heart rate look normal."
        }
        return note
    }

    /// Last night against her need: "44m short", "on target", "1h 05m over".
    private var sleepVsNeedWord: String {
        guard model.lastNightIsFresh else { return "none" }
        let gap = model.lastNight.asleep - model.sleepNeed.minutes
        if gap < -15 { return "\(SleepText.compact(gap)) short" }
        if gap > 15 { return "\(SleepText.compact(gap)) over" }
        return "on target"
    }

    private var recoveryCard: some View {
        let p = Palette(scheme: scheme)
        let heart = model.hasHeartData
        let fresh = model.lastNightIsFresh
        return Card {
            HStack(spacing: 0) {
                SectionLabel(text: "Recovery today")
                InfoButton(topic: .recovery).padding(.vertical, -14)
                Spacer()
            }
            .padding(.bottom, -8)
            if let value = recoveryValue {
                NavigationLink {
                    RecoveryView()
                } label: {
                    // Ring above the words at large text sizes, so "Take it
                    // steady" isn't squeezed into a few letters per line.
                    AdaptiveStack(spacing: 16) {
                        Ring(value: Double(value) / 100, accent: .indigo, label: "\(value)", caption: "Recovery")
                        VStack(alignment: .leading, spacing: 4) {
                            AdaptiveStack(spacing: 8, alignment: .firstTextBaseline) {
                                Text(model.recoveryLabel(for: value)).font(.scaled(size: 22, weight: .bold))
                                    .fixedSize(horizontal: false, vertical: true)
                                if model.recoveryIsExample {
                                    ExampleTag()
                                }
                            }
                            Text(recoveryNote)
                                .font(.scaled(size: 14))
                                .foregroundStyle(p.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.scaled(size: 13, weight: .bold))
                            .foregroundStyle(p.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens recovery details")
            } else {
                Text("No recovery yet today").font(.scaled(size: 22, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("There's no sleep from last night and no HRV or resting heart rate yet. Wear your Watch to bed tonight.")
                    .font(.scaled(size: 14))
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AdaptiveStack(spacing: 6, alignment: .top) {
                MiniGauge(fraction: heart ? model.hrv / 80 : 0, accent: model.hrvDeltaPct < 0 ? .coral : .mint,
                          value: heart ? "\(Int(model.hrv.rounded()))" : "\u{2014}", title: "HRV",
                          note: heart ? SleepText.signed(model.hrvDeltaPct) + "%" : "no reading",
                          topic: .hrv)
                MiniGauge(fraction: heart ? model.restingHR / 120 : 0, accent: .pink,
                          value: heart ? "\(Int(model.restingHR.rounded()))" : "\u{2014}", title: "Resting HR",
                          note: heart ? SleepText.signed(model.restingHRDelta) : "no reading",
                          topic: .restingHR)
                MiniGauge(fraction: fresh ? Double(model.lastNight.asleep) / 540 : 0, accent: .mint,
                          value: fresh ? SleepText.hours(model.lastNight.asleep) : "\u{2014}", title: "Sleep",
                          note: sleepVsNeedWord, topic: .sleepNeed)
            }
            if !heart {
                Text("HRV and resting heart rate: no reading yet. Your Watch measures them while you're still, mostly overnight.")
                    .font(.scaled(size: 12))
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: No sleep recorded

    private var noSleepCard: some View {
        let p = Palette(scheme: scheme)
        return Card(accent: .purple) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.zzz")
                    .font(.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Accent.purple.ink(scheme))
                    .frame(width: 36, height: 36)
                    .background(Accent.purple.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No sleep recorded last night").font(.scaled(size: 16, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Wear your Watch to bed and turn on Sleep Focus so it records your night.")
                        .font(.scaled(size: 13))
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

    /// Only on real heart data: example numbers never say she's getting sick.
    private var showSickCard: Bool {
        !model.usingSampleData && model.hasHeartData
            && (model.illness.confidence == .medium || model.illness.confidence == .high)
    }

    private var sickTitle: String {
        model.illness.confidence == .high
            ? "Your body is likely fighting something"
            : "Your body may be fighting something"
    }

    private var sickDetail: String {
        let flagged = model.illness.factors.filter(\.flagged).map { $0.name.lowercased() }
        var detail = flagged.isEmpty
            ? "Several of your signals moved at once."
            : "Your " + joined(flagged) + (flagged.count == 1 ? " is" : " are") + " off your usual."
        if model.hardTrainingYesterday {
            detail += model.hidesEffortTargets
                ? " Yesterday's extra activity is already allowed for."
                : " Yesterday's hard training is already allowed for."
        }
        if model.illness.cyclePhaseUnknown {
            detail += " Your cycle can raise these too, and the app can't tell which phase you're in."
        } else if model.inLutealPhase {
            detail += " So is the late part of your cycle."
        }
        return detail + " Take it easy, drink water and get extra sleep tonight."
    }

    private var sickCard: some View {
        let p = Palette(scheme: scheme)
        return Card(accent: .coral) {
            HStack(spacing: 0) {
                SectionLabel(text: "Sick check \u{00B7} \(model.illness.confidence.rawValue)", accent: .coral)
                InfoButton(topic: .illness).padding(.vertical, -14)
                Spacer()
            }
            .padding(.bottom, -8)
            NavigationLink {
                SickView()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "thermometer.medium")
                        .font(.scaled(size: 16, weight: .semibold))
                        .foregroundStyle(Accent.coral.ink(scheme))
                        .frame(width: 36, height: 36)
                        .background(Accent.coral.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sickTitle).font(.scaled(size: 16, weight: .bold))
                        Text(sickDetail)
                            .font(.scaled(size: 13))
                            .foregroundStyle(p.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 13, weight: .bold))
                        .foregroundStyle(p.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
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
        Card(padding: 12) {
            LinkRow(title: "Why do I feel off?", subtitle: whyOffSubtitle,
                    systemImage: "questionmark.bubble.fill", accent: .coral) {
                WhyOffView()
            }
        }
    }

    // MARK: Tonight

    private var tonightCard: some View {
        let tonight = model.tonightPlan
        let plan = tonight.plan
        let bed = tonight.bedtime
        let wake = tonight.wake ?? tonight.upBy
        let alarmText: String
        let weekendMorning = Calendar.current.isDateInWeekend(model.nextWakeDay)
        if let plan {
            let state: String
            if !store.data.smartAlarmEnabled {
                state = "Off"
            } else if store.data.alarmWeekdaysOnly && weekendMorning && model.activeAlarmOverride == nil {
                state = "Off for the weekend"
            } else {
                state = "On"
            }
            alarmText = "Smart alarm by \(Clock.format(plan.alarmWindow.end)) \u{00B7} " + state
        } else {
            alarmText = "Plan your wake time"
        }
        return Card(accent: .purple, padding: 14) {
            AdaptiveStack(spacing: 14) {
                SleepArcDial(start: bed, end: wake, size: 88, lineWidth: 10,
                             colors: [Accent.purple.fill(scheme), Accent.orange.fill(scheme)],
                             label: Clock.duration(tonight.expectedAsleep), labelSize: 20, caption: "asleep")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        SectionLabel(text: "Tonight", accent: .purple)
                        InfoButton(title: "Tonight's plan",
                                   meaning: "Your planned bedtime and the best time to wake tomorrow: the end of a sleep cycle that still lands before you need to be up. Tonight you need \(model.tonightNeedText).",
                                   forYou: (model.wakeTimesExplained.map { $0 + " " } ?? "") + "Tap the alarm chip to set the smart alarm on your Watch. Your phone's alarms are never changed.")
                            .padding(.vertical, -14)
                    }
                    Text(model.tonightBedUpLine)
                        .font(.scaled(size: 19, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let short = model.tonightShortNote {
                        Text(short)
                            .font(.scaled(size: 13))
                            .secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    NavigationLink {
                        WakePlanView()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "alarm")
                                .font(.scaled(size: 12, weight: .bold))
                                .foregroundStyle(Accent.orange.ink(scheme))
                                .accessibilityHidden(true)
                            Text(alarmText).font(.scaled(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: Font.scaledSize(30))
                        .background(Accent.orange.fill(scheme).opacity(0.2), in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: This week

    private var weekHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("This week").font(.scaled(size: 17, weight: .bold)).accessibilityAddTraits(.isHeader)
            Spacer()
            NavigationLink {
                WeekRecapView()
            } label: {
                Text("Weekly recap")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.indigo.ink(scheme))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
        .padding(.horizontal, 2)
    }

    // MARK: Tiles

    private var caffeineValue: String {
        let mg = model.todaysDrinks.map(\.mg).reduce(0, +)
        return model.todaysDrinks.isEmpty ? "None yet" : "\(mg) mg"
    }

    private var caffeineNote: String {
        let count = model.todaysDrinks.count
        if count == 0 { return "Tap to log a drink" }
        return (count == 1 ? "1 drink" : "\(count) drinks") + " \u{00B7} tap to edit"
    }

    private var stressValue: String {
        if let label = model.stressToday.label { return label.rawValue }
        if let felt = model.stressLoggedToday { return "Felt \(felt)/5" }
        return "No data yet"
    }

    private var stressNote: String {
        if let avg = model.stressToday.average {
            return "Level \(avg) of 100" + (model.stressLoggedToday.map { " \u{00B7} felt \($0)/5" } ?? "")
        }
        return model.restingHRBaselineKnown ? "Wear your Watch today" : "Learning your resting heart rate"
    }

    private var sleepTileValue: String {
        model.lastNightIsFresh ? Clock.duration(model.lastNight.asleep) : "None"
    }

    private var sleepTileNote: String {
        guard model.lastNightIsFresh else { return "No sleep recorded" }
        return model.sleepRegularityScore.map { "Regularity \($0)" } ?? "Last night"
    }

    /// Two columns, or one at accessibility text sizes so titles and
    /// values aren't cut off.
    @ViewBuilder
    private var tiles: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                sleepTile
                caffeineTile
                waterTile
                stressTile
            }
        } else {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
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

    private var sleepTile: some View {
                ZStack(alignment: .bottomTrailing) {
                    NavigationLink {
                        SleepView()
                    } label: {
                        MetricTile(title: "Sleep", value: sleepTileValue, note: sleepTileNote,
                                   accent: .purple, systemImage: "moon.fill")
                    }
                    .buttonStyle(.plain)
                    if model.lastNightIsFresh && model.sleepRegularityScore != nil {
                        InfoButton(topic: .regularity)
                    }
                }
    }

    private var caffeineTile: some View {
                NavigationLink {
                    CaffeineView()
                } label: {
                    MetricTile(title: "Caffeine", value: caffeineValue, note: caffeineNote,
                               accent: .yellow, systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens caffeine, where you can log drinks and change their times")
    }

    private var waterTile: some View {
                WaterTile(todayML: model.waterTodayML, goalML: store.data.waterGoalML,
                          bottleML: store.data.bottleSizeML) {
                    model.addWater()
                }
    }

    private var stressTile: some View {
                ZStack(alignment: .topTrailing) {
                    NavigationLink {
                        StressView()
                    } label: {
                        MetricTile(title: "Stress", value: stressValue, note: stressNote, accent: .coral)
                    }
                    .buttonStyle(.plain)
                    InfoButton(topic: .stress)
                }
    }

    // MARK: More

    private var moreCard: some View {
        Card(padding: 12) {
            SectionLabel(text: "More").padding(.horizontal, 4)
            if !showWhyOffUpTop {
                LinkRow(title: "Why do I feel off?", subtitle: "Check what might be behind a rough day",
                        systemImage: "questionmark.bubble.fill", accent: .coral) {
                    WhyOffView()
                }
                Divider()
            }
            LinkRow(title: "Streaks & achievements", subtitle: streakSubtitle,
                    systemImage: "flame.fill", accent: .orange) {
                AchievementsView()
            }
            Divider()
            LinkRow(title: "Getting accurate numbers", subtitle: "Simple ways to help your Watch",
                    systemImage: "checklist", accent: .indigo) {
                AccuracyTipsView()
            }
        }
    }

    private var streakSubtitle: String {
        if let best = model.streaks.max(by: { $0.current < $1.current }), best.current > 0 {
            return "\(best.title): \(best.current) \(best.unit) in a row"
        }
        return "Start a streak tonight"
    }
}

/// Water today in ounces, with a quick "+1 bottle" button.
private struct WaterTile: View {
    var todayML: Double
    var goalML: Double
    var bottleML: Double
    var add: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var bottlesNote: String {
        guard bottleML > 0 else { return "" }
        let had = todayML / bottleML
        let goal = goalML / bottleML
        return "\(LogFormat.bottles(had)) of \(LogFormat.bottlesPhrase(goal))"
    }

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink {
                WaterView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Water").font(.scaled(size: 14, weight: .bold))
                        Spacer()
                        Image(systemName: "drop.fill").foregroundStyle(Accent.blue.ink(scheme)).accessibilityHidden(true)
                    }
                    Text("\(LogFormat.ozNumber(todayML)) of \(LogFormat.oz(goalML))")
                        .font(.scaledNumber(24)).minimumScaleFactor(0.6).lineLimit(1)
                    Text(bottlesNote).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Water: \(LogFormat.oz(todayML)) of \(LogFormat.oz(goalML)), \(bottlesNote)")
            .accessibilityHint("Opens water, where you can change your bottle size and goal")
            Button(action: add) {
                Label("1 bottle", systemImage: "plus")
                    .font(.scaled(size: 13, weight: .bold))
                    .foregroundStyle(Accent.blue.ink(scheme))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Accent.blue.fill(scheme).opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add one bottle of water, \(LogFormat.oz(bottleML))")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Accent.blue.tint(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A small rounded pill with an icon, used for the header chips.
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
                    .font(.scaled(size: 10, weight: .bold))
                    .foregroundStyle(p.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Font.scaledSize(32))
        .background(p.chip, in: Capsule())
        .overlay(Capsule().strokeBorder(p.cardBorder))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A 270-degree gauge with a number inside, for the recovery inputs, with
/// an ⓘ next to its name.
private struct MiniGauge: View {
    var fraction: Double
    var accent: Accent
    var value: String
    var title: String
    var note: String
    var topic: Topic
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        // The dial grows with the text size (up to 90pt) so the number fits.
        let dial = min(max(56, Font.scaledSize(56)), 90)
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(p.track, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * max(0.02, min(fraction, 1)))
                    .stroke(accent.fill(scheme), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .opacity(fraction > 0 ? 1 : 0)
                Text(value)
                    .font(.scaledNumber(value.count > 3 ? 15 : 17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 8)
            }
            .frame(width: dial, height: dial)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) \(value), \(note)")
            HStack(spacing: 0) {
                Text(title).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                InfoButton(topic: topic).padding(.vertical, -12).padding(.horizontal, -10)
            }
            Text(note).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(accent.ink(scheme))
                .lineLimit(2).minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}
