import SwiftUI
import HealthCore

/// Last night, the smart alarm, stages and the weekend shift.
struct SleepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

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
            statBlock("Fell asleep", Clock.format(night.onset))
            statBlock("Woke up", Clock.format(night.wake))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    SectionLabel(text: "Regularity")
                    InfoButton(topic: .regularity).padding(.vertical, -14).padding(.horizontal, -8)
                }
                Text(model.sleepRegularityScore.map { "\($0)" } ?? "\u{2014}").font(.scaledNumber(22))
            }
        }
    }

    private var noSleepCard: some View {
        Card {
            Text("No sleep recorded last night").font(.scaled(size: 20, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text("Your Watch didn't record a night that ended this morning. Wear it to bed with at least 30% battery and turn on Sleep Focus.")
                .font(.scaled(size: 14))
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "How to get your sleep recorded", systemImage: "applewatch", accent: .purple) {
                AccuracyTipsView()
            }
        }
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: title)
            Text(value).font(.scaledNumber(22))
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
        Binding(
            get: { store.data.smartAlarmEnabled },
            set: { on in
                if on, let plan = model.wakePlan() {
                    model.setSmartAlarm(from: plan)
                } else {
                    store.data.smartAlarmEnabled = on
                    model.pushToWatch()
                }
            })
    }

    private func smartAlarmCard(_ plan: WakePlan?) -> some View {
        let p = Palette(scheme: scheme)
        let night = model.lastNight
        return Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    ExplainedTitle(text: "Smart alarm", topic: .smartAlarm, size: 17)
                    Text("On your Watch").font(.scaled(size: 13)).foregroundStyle(p.secondary)
                }
                Spacer()
                Toggle("Smart alarm", isOn: alarmBinding)
                    .labelsHidden()
                    .tint(Accent.orange.fill(scheme))
            }
            if let plan {
                // Stacks at large sizes so the time never splits ("8:2 / 5").
                AdaptiveStack(spacing: 6, alignment: .firstTextBaseline) {
                    Text(Clock.format(plan.alarmWindow.end, suffix: false)).font(.scaledNumber(40)).keepsOnOneLine()
                    Text("\(SleepText.meridiem(plan.alarmWindow.end)) latest \u{00B7} listens from \(Clock.format(plan.alarmWindow.start)) \u{00B7} up by \(Clock.format(store.data.upBy))")
                        .font(.scaled(size: 14, weight: .semibold))
                        .foregroundStyle(p.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if model.lastNightIsFresh {
                HStack(spacing: 8) {
                    Image(systemName: night.wokeFromLight ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle((night.wokeFromLight ? Accent.mint : Accent.coral).ink(scheme))
                        .accessibilityHidden(true)
                    Text("This morning you woke at \(Clock.format(night.wake)), " + (night.wokeFromLight ? "in light sleep." : "from deep or REM sleep."))
                        .font(.scaled(size: 14))
                        .foregroundStyle(p.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if store.data.smartAlarmEnabled {
                Toggle(isOn: $store.data.alarmWeekdaysOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekdays only").font(.scaled(size: 15, weight: .semibold))
                        Text("No smart alarm on Saturday and Sunday mornings.")
                            .font(.scaled(size: 13)).foregroundStyle(p.secondary)
                    }
                }
                .tint(Accent.orange.fill(scheme))
                .frame(minHeight: 44)
            }
            if let plan {
                NavigationLink {
                    WakePlanView()
                } label: {
                    HStack(spacing: 6) {
                        Text("Best time to wake \(model.nextWakeDayLabel.lowercased()): \(Clock.format(plan.wake))")
                            .font(.scaled(size: 15, weight: .bold))
                        Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .bold)).accessibilityHidden(true)
                    }
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Links

    private var linksCard: some View {
        let need = model.sleepNeed
        let showClockChange = model.daysUntilFallBack <= 28
        return Card {
            HStack(spacing: 0) {
                Text("Sleep debt").font(.scaled(size: 15, weight: .bold))
                InfoButton(topic: .sleepDebt).padding(.vertical, -12)
                Spacer()
                Text(model.sleepDebt > 0 ? Clock.duration(model.sleepDebt) : "None")
                    .font(.scaled(size: 15, weight: .bold))
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
                        .font(.scaled(size: 15, weight: .bold))
                        .foregroundStyle(Accent.coral.ink(scheme))
                }
                ShiftBar(title: "School nights", range: work, color: Accent.purple.fill(scheme))
                ShiftBar(title: "Free nights", range: free, color: Accent.coral.fill(scheme))
                Text(shift >= 60
                     ? "Like flying a time zone west every weekend. Keeping free days within an hour of school days makes Mondays easier."
                     : "Under an hour, which is the goal. Your body clock stays steady through the week.")
                    .font(.scaled(size: 13))
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
