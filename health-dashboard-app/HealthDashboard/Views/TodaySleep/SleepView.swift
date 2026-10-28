import SwiftUI
import HealthCore

/// Last night, the smart alarm, stages and the weekend shift.
struct SleepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let plan = model.wakePlan()
        Screen(title: "Sleep", accent: .purple) {
            SampleDataBanner()
            if model.lastNightIsFresh {
                lastNightCard
            } else {
                noSleepCard
            }
            historyLink
            smartAlarmCard(plan)
            linksCard
            if model.lastNightIsFresh {
                stagesCard
            }
            weekendCard
            troubleSleepingCard
        }
    }

    // MARK: Trouble sleeping

    /// When it's more than a bad week (Park 13).
    private var troubleSleepingCard: some View {
        Card {
            Text("Trouble sleeping?").font(.cardTitle).accessibilityAddTraits(.isHeader)
            Text("Trouble falling or staying asleep 3 or more nights a week, for months? That's insomnia, and it's very treatable. CBT-I, a short program that changes sleep habits and thoughts, is the first-line treatment, and many campuses offer it. Ask your campus health or counseling center.")
                .font(.bodyText).lineSpacing(2).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Text("An urge to move your legs at night can be restless legs, which is linked to low iron. Sleep that gets much worse every month before your period is worth mentioning to a clinician too.")
                .font(.bodyText).lineSpacing(2).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Last night

    /// Dial beside the numbers when they fit; at large text sizes the numbers go under the dial.
    private var lastNightCard: some View {
        Card {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    lastNightDial
                    lastNightStats
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 14) {
                    lastNightDial.frame(maxWidth: .infinity)
                    lastNightStats
                }
            }
        }
    }

    private var lastNightDial: some View {
        let night = model.lastNight
        return SleepArcDial(start: night.onset, end: night.wake, size: 168, lineWidth: 14,
                            colors: [Accent.purple.ink(scheme), Accent.purple.fill(scheme)],
                            label: Clock.duration(night.asleep), labelSize: 24,
                            caption: "last night", showHours: true)
    }

    private var lastNightStats: some View {
        let night = model.lastNight
        return VStack(alignment: .leading, spacing: 14) {
            statBlock("Fell asleep", night.onset)
            statBlock("Woke up", night.wake)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    SectionLabel(text: "Regularity")
                    InfoButton(topic: .regularity).padding(.vertical, -14).padding(.horizontal, -8)
                }
                Text(model.sleepRegularityScore.map { "\($0)" } ?? "\u{2014}").font(.numberM)
            }
        }
    }

    private var noSleepCard: some View {
        Card {
            Text("No sleep recorded last night").font(.section)
                .accessibilityAddTraits(.isHeader)
            Text("Your Watch didn't record a night that ended this morning. Wear it to bed with at least 30% battery and turn on Sleep Focus.")
                .font(.bodyText).lineSpacing(2)
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "How to get your sleep recorded", systemImage: "applewatch", accent: .purple) {
                AccuracyTipsView()
            }
        }
    }

    private func statBlock(_ title: String, _ time: Minutes) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: title)
            ClockText(minutes: time, role: .numberM)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Week & month

    private var historyLink: some View {
        Card(density: .compact) {
            LinkRow(title: "Week & month", subtitle: "Every night, your averages and how steady your sleep is",
                    systemImage: "chart.bar.fill", accent: .purple) {
                SleepHistoryView()
            }
        }
    }

    // MARK: Smart alarm

    private var alarmBinding: Binding<Bool> {
        let binding = Binding<Bool>(
            get: { store.data.smartAlarmEnabled },
            set: { on in
                if on, let plan = model.wakePlan() {
                    model.setSmartAlarm(from: plan)
                } else {
                    store.data.smartAlarmEnabled = on
                    model.pushToWatch()
                }
            })
        return binding.animation(Motion.reveal.animation(reduceMotion: reduceMotion))
    }

    private func smartAlarmCard(_ plan: WakePlan?) -> some View {
        let p = Palette(scheme: scheme)
        let night = model.lastNight
        return Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    ExplainedTitle(text: "Smart alarm", topic: .smartAlarm, size: 17)
                    Text(store.data.smartAlarmEnabled ? "On your Watch" : "Off")
                        .font(.secondary).foregroundStyle(p.secondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                Toggle("Smart alarm", isOn: alarmBinding)
                    .labelsHidden()
                    .tint(Accent.purple.fill(scheme))
            }
            if let plan {
                // "8:00–8:25am", then the latest wake-up (Dubois 7). Dimmed
                // while the alarm is off (Valtonen F14).
                VStack(alignment: .leading, spacing: Space.xs) {
                    ClockText(minutes: plan.alarmWindow.end, role: .numberL, from: plan.alarmWindow.start)
                        .keepsOnOneLine()
                    Text("Never after \(Clock.format(store.data.upBy)), your latest wake-up.")
                        .font(.secondary)
                        .foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(store.data.smartAlarmEnabled ? 1 : 0.5)
                .accessibilityElement(children: .combine)
            }
            if model.lastNightIsFresh {
                HStack(spacing: 8) {
                    Image(systemName: night.wokeFromLight ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle((night.wokeFromLight ? Accent.mint : Accent.coral).ink(scheme))
                        .accessibilityHidden(true)
                    Text("This morning you woke at \(Clock.format(night.wake)), " + (night.wokeFromLight ? "in light sleep." : "from deep or REM sleep."))
                        .font(.bodyText)
                        .foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if store.data.smartAlarmEnabled {
                Toggle(isOn: $store.data.alarmWeekdaysOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekdays only").font(.bodyEmphasis)
                        Text("No smart alarm on Saturday and Sunday mornings.")
                            .font(.secondary).foregroundStyle(p.secondary)
                    }
                }
                .tint(Accent.purple.fill(scheme))
                .frame(minHeight: 44)
                .motionTransition(.reveal, edge: .top)
            }
            if let plan {
                NavigationLink {
                    WakePlanView()
                } label: {
                    HStack(spacing: 6) {
                        Text("Best time to wake \(model.nextWakeDayLabel.lowercased()): \(Clock.format(plan.wake))")
                            .font(.bodyEmphasis)
                        Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .bold)).accessibilityHidden(true)
                    }
                    .foregroundStyle(Accent.purple.ink(scheme))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.success, trigger: store.data.smartAlarmEnabled) { old, new in !old && new }
    }

    // MARK: Links

    private var linksCard: some View {
        let need = model.sleepNeed
        let showClockChange = model.daysUntilFallBack <= 28
        return Card {
            HStack(spacing: 0) {
                Text("Sleep debt").font(.bodyEmphasis)
                InfoButton(topic: .sleepDebt).padding(.vertical, -12)
                Spacer()
                Text(model.sleepDebt > 0 ? Clock.duration(model.sleepDebt) : "None")
                    .font(.bodyEmphasis)
                    .foregroundStyle((model.sleepDebt >= 60 ? Accent.coral : Accent.mint).ink(scheme))
            }
            .padding(.horizontal, 4)
            Divider()
            LinkRow(title: "Your sleep need: \(Clock.duration(need.minutes))",
                    subtitle: "Tonight \(model.tonightNeedText), " + SleepText.needSource(model),
                    systemImage: "bed.double.fill", accent: .purple) {
                SleepNeedView()
            }
            if showClockChange {
                Divider()
                LinkRow(title: "Clocks go back \(model.nextFallBack.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
                        subtitle: "What it means for your sleep",
                        systemImage: "clock.arrow.circlepath", accent: .orange) {
                    TimeChangeView()
                }
            }
        }
    }

    // MARK: Stages

    private var stagesCard: some View {
        let p = Palette(scheme: scheme)
        let night = model.lastNight
        return Card {
            HStack(alignment: .firstTextBaseline) {
                ExplainedTitle(text: "Last night", topic: .sleepStages, size: 17)
                Spacer()
                Text("\(Clock.format(night.onset)) \u{2013} \(Clock.format(night.wake))")
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundStyle(p.secondary)
            }
            let timeline = model.lastNightTimeline
            if timeline.isEmpty {
                StageStackBar(minutes: night.stageMinutes)
                Text("Stage-by-stage timing shows up once your Watch records a night in Apple Health.")
                    .font(.scaled(size: 13))
                    .secondaryText()
            } else {
                StageTimeline(segments: timeline)
            }
            StageLegendRow(minutes: night.stageMinutes)
            NavigationLink {
                SleepStagesView()
            } label: {
                HStack(spacing: 6) {
                    Text("See stage details").font(.scaled(size: 15, weight: .semibold))
                    Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .bold)).accessibilityHidden(true)
                }
                .foregroundStyle(Accent.purple.ink(scheme))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Weekend shift

    private static func average(_ nights: [Chronotype.Night]) -> TimeRange? {
        guard !nights.isEmpty else { return nil }
        let n = Double(nights.count)
        let onset = Double(nights.map(\.onset).reduce(0, +)) / n
        let wake = Double(nights.map(\.wake).reduce(0, +)) / n
        return TimeRange(Int(onset.rounded()), Int(wake.rounded()))
    }

    @ViewBuilder
    private var weekendCard: some View {
        if let work = Self.average(model.workNights), let free = Self.average(model.freeNights) {
            let shift = model.chronotype?.socialJetlag ?? abs((free.start + free.end) / 2 - (work.start + work.end) / 2)
            Card {
                HStack(alignment: .firstTextBaseline) {
                    ExplainedTitle(text: "Weekend shift", topic: .weekendShift)
                    Spacer()
                    Text("\(Clock.duration(shift)) later")
                        .font(.bodyEmphasis)
                        .foregroundStyle(shift >= 60 ? Accent.coral.ink(scheme) : Palette(scheme: scheme).secondary)
                }
                ShiftBar(title: "School nights", range: work, color: Accent.purple.fill(scheme))
                ShiftBar(title: "Free nights", range: free,
                         color: shift >= 60 ? Accent.coral.fill(scheme) : Accent.purple.ink(scheme).opacity(0.6))
                Text(shift >= 60
                     ? "Like flying a time zone west every weekend. Keeping free days within an hour of school days makes Mondays easier."
                     : "Under an hour, which is the goal. Your body clock stays steady through the week.")
                    .font(.bodyText).lineSpacing(2)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One sleep window on an 8pm-to-noon track.
private struct ShiftBar: View {
    var title: String
    var range: TimeRange
    var color: Color
    @Environment(\.colorScheme) private var scheme

    private let trackStart = -240   // 8pm the evening before
    private let trackLength = 960.0 // to noon

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                // With am/pm: "1:22" alone is ambiguous for a night owl (round 3).
                Text("\(Clock.format(range.start)) \u{2013} \(Clock.format(range.end))")
            }
            .font(.scaled(size: 12, weight: .semibold))
            .foregroundStyle(p.secondary)
            GeometryReader { geo in
                let w = geo.size.width
                let x = CGFloat(Double(range.start - trackStart) / trackLength) * w
                let width = CGFloat(Double(range.length) / trackLength) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule().fill(color)
                        .frame(width: max(8, min(width, w - max(x, 0))))
                        .offset(x: max(x, 0))
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(Clock.format(range.start)) to \(Clock.format(range.end))")
    }
}
