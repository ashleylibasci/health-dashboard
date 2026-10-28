import SwiftUI
import Charts
import HealthCore

/// Tomorrow's best wake time, why it was picked, and what past mornings say.
struct WakePlanView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    /// The up-by time the smart alarm was last set for from this screen.
    @State private var appliedUpBy: Minutes? = nil
    @State private var selectedWakeHours: Double? = nil

    /// Matches WakePlanner's default time to fall asleep.
    private let latency = 12

    var body: some View {
        let plan = model.wakePlan()
        Screen(title: "Best time to wake", accent: .orange) {
            SampleDataBanner()
            if let plan {
                heroCard(plan)
                reasonsCard(plan)
            } else {
                noPlanCard
            }
            timesCard
            if let plan {
                timelineCard(plan)
            }
            historyCard
            learnedCard
            windDownCard
            linksCard
        }
    }

    // MARK: Hero

    /// "Tomorrow, Wednesday"; after midnight "This morning, Wednesday".
    private var wakeDayTitle: String { "\(model.nextWakeDayLabel), \(model.nextWakeDayName)" }

    private var cycleSource: String {
        model.usingSampleData ? "a typical cycle length of \(model.sleepCycleLength) minutes (yours is measured once you have 14 nights)"
            : "your own cycle length of \(model.sleepCycleLength) minutes, measured from your nights"
    }

    private func isGood(_ plan: WakePlan) -> Bool { plan.cycles >= 5 || plan.shortfall <= 10 }

    private func why(_ plan: WakePlan) -> String {
        var text = "This time lands at the end of a sleep cycle, when you're in light sleep, so waking up feels easier."
        let cycle = model.sleepCycleLength
        if store.data.smartAlarmEnabled, let into = plan.currentAlarmMinutesIntoCycle, into >= 15, into <= cycle - 15 {
            text += " Your current alarm lands \(into) minutes into a sleep cycle, when you're more likely to be in deep sleep."
        }
        return text
    }

    private func heroCard(_ plan: WakePlan) -> some View {
        let p = Palette(scheme: scheme)
        let good = isGood(plan)
        let gradeAccent: Accent = good ? .mint : .coral
        return Card(accent: .orange) {
            HStack(spacing: 0) {
                SectionLabel(text: wakeDayTitle, accent: .orange)
                InfoButton(title: "Best time to wake",
                           meaning: "The wake-up time that fits your sleep cycles, your best wake window and tonight's sleep need, and is never later than when you need to be up.",
                           forYou: "Set your smart alarm to it. Waking at the end of a cycle means less grogginess.")
                    .padding(.vertical, -14)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Clock.format(plan.wake, suffix: false)).font(.scaledNumber(64)).minimumScaleFactor(0.6).lineLimit(1)
                Text(SleepText.meridiem(plan.wake)).font(.scaled(size: 22, weight: .bold)).foregroundStyle(p.secondary)
                Spacer()
                Text(good ? "Best" : "Short night")
                    .font(.scaled(size: 13, weight: .bold))
                    .foregroundStyle(gradeAccent.ink(scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(gradeAccent.fill(scheme).opacity(0.2), in: Capsule())
            }
            .accessibilityElement(children: .combine)
            Text(why(plan))
                .font(.scaled(size: 15))
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "alarm")
                    .font(.scaled(size: 14, weight: .semibold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .accessibilityHidden(true)
                Text("Smart alarm window \(plan.alarmWindow.label) \u{00B7} wakes you at the first light sleep")
                    .font(.scaled(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                InfoButton(topic: .smartAlarm).padding(.vertical, -14)
            }
            if let times = model.wakeTimesExplained {
                Text(times)
                    .font(.scaled(size: 13))
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HowWeGotThisLink(title: "Best time to wake",
                             method: "We count whole sleep cycles from about \(latency) minutes after your bedtime, using \(cycleSource). We pick the last cycle end before your up-by time, prefer one inside the wake window where your past mornings felt best, and check it against tonight's sleep need. The smart alarm window runs from \(AppModel.alarmWindowLead) minutes before that cycle ends to 3 minutes after.")
        }
    }

    private var noPlanCard: some View {
        Card(accent: .orange) {
            Text("No full sleep cycle fits").font(.scaled(size: 17, weight: .bold))
            Text("With bed at \(Clock.format(store.data.bedtime)), there isn't time for a whole sleep cycle before \(Clock.format(store.data.upBy)). Pick an earlier bedtime or a later up-by time below.")
                .font(.scaled(size: 14))
                .secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reasonsCard(_ plan: WakePlan) -> some View {
        Card {
            Text("Why this time").font(.scaled(size: 17, weight: .bold))
            ForEach(plan.reasons, id: \.self) { reason in
                ReasonRow(ok: reason.ok, title: reason.title, detail: reason.detail)
            }
        }
    }

    // MARK: Bedtime and up-by

    /// Up-by as a time today, for the picker (minutes after midnight).
    private var upByBinding: Binding<Date> {
        Binding(
            get: { AppDay.date(store.data.upBy, relativeTo: Calendar.current.startOfDay(for: .now)) },
            set: { store.data.upBy = Clock.minutesOfDay($0) })
    }

    /// Bedtime relative to the wake day, by the one shared rule
    /// (`AppDay.bedtime(fromClock:)`: noon or later is the evening before).
    private var bedtimeBinding: Binding<Date> {
        Binding(
            get: { AppDay.date(store.data.bedtime, relativeTo: Calendar.current.startOfDay(for: .now)) },
            set: { date in
                store.data.bedtime = AppDay.bedtime(fromClock: Clock.minutesOfDay(date))
            })
    }

    /// "That's 8h 30m in bed", or a warning when bedtime comes after up-by.
    @ViewBuilder
    private var timeInBedLine: some View {
        let inBed = AppDay.timeInBed(bedtime: store.data.bedtime, upBy: store.data.upBy)
        if inBed <= 0 {
            Label("Your bedtime is after your up-by time. Pick an earlier bedtime or a later up-by time.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.scaled(size: 14, weight: .semibold))
                .foregroundStyle(Accent.coral.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("That's \(Clock.duration(inBed)) in bed.")
                .font(.scaled(size: 14, weight: .semibold))
                .foregroundStyle((inBed < 6 * 60 ? Accent.coral : Accent.mint).ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timesCard: some View {
        let p = Palette(scheme: scheme)
        return Card {
            HStack(spacing: 0) {
                Text("Your times").font(.scaled(size: 17, weight: .bold))
                InfoButton(title: "Bedtime and up-by",
                           meaning: "Up-by is the latest you need to be up. Bedtime is when you plan to be in bed. The wake plan, your caffeine cutoff, your smart alarm and bedtime streaks all use them.",
                           forYou: "Set up-by to your earliest commitment, like a 9am class. Pick a bedtime you can keep most nights.")
                    .padding(.vertical, -12)
            }
            DatePicker(selection: upByBinding, displayedComponents: .hourAndMinute) {
                Label("I need to be up by", systemImage: "sunrise.fill")
                    .font(.scaled(size: 15, weight: .semibold))
            }
            .frame(minHeight: 44)
            DatePicker(selection: bedtimeBinding, displayedComponents: .hourAndMinute) {
                Label("Bedtime", systemImage: "moon.fill")
                    .font(.scaled(size: 15, weight: .semibold))
            }
            .frame(minHeight: 44)
            timeInBedLine
            Text("Asleep about \(latency) minutes after \(Clock.format(store.data.bedtime)). Changes reach your Watch right away.")
                .font(.scaled(size: 13))
                .foregroundStyle(p.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Cycle timeline

    private func timelineCard(_ plan: WakePlan) -> some View {
        let p = Palette(scheme: scheme)
        let onset = store.data.bedtime + latency
        let deadline = store.data.upBy
        let applied = appliedUpBy == store.data.upBy && store.data.smartAlarmEnabled
        let tip = tipText(plan)
        return Card {
            ExplainedTitle(text: "Your sleep cycles tonight", topic: .sleepCycle, size: 17)
            CycleTimeline(onset: onset, deadline: deadline, cycleLength: model.sleepCycleLength,
                          cycles: plan.cycles, window: plan.alarmWindow, wake: plan.wake)
            HStack(spacing: 14) {
                legendSwatch(color: Accent.indigo.fill(scheme).opacity(0.6), text: "Full sleep cycle")
                legendSwatch(color: Accent.orange.fill(scheme).opacity(0.5), text: "Smart alarm window")
            }
            if let tip {
                Text(tip)
                    .font(.scaled(size: 14))
                    .foregroundStyle(Accent.coral.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: applied ? "Smart alarm set: \(plan.alarmWindow.label)" : "Set smart alarm to \(Clock.format(plan.alarmWindow.end)) latest",
                          accent: .orange, done: applied) {
                model.setSmartAlarm(from: plan)
                appliedUpBy = store.data.upBy
            }
            Text("Your Watch wakes you at the first light sleep inside the window.")
                .font(.scaled(size: 12))
                .foregroundStyle(p.secondary)
        }
    }

    private func tipText(_ plan: WakePlan) -> String? {
        guard !isGood(plan) else { return nil }
        var text = "Only \(plan.cycles) full cycles fit."
        if let bed = model.tonightPlan.bedtimeToCoverNeed {
            text += " To cover tonight's \(model.tonightNeedText), go to bed by \(Clock.format(bed))."
        }
        return text
    }

    private func legendSwatch(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 10)
            Text(text).font(.scaled(size: 12, weight: .semibold)).secondaryText()
        }
    }

    // MARK: Past wake-ups

    private var morningDots: [MorningDot] {
        model.mornings.enumerated().map { pair in
            MorningDot(id: pair.offset, hours: Double(pair.element.wake) / 60,
                       outcome: pair.element.outcome, light: pair.element.wokeFromLightSleep)
        }
    }

    private var outcomeDomain: ClosedRange<Double> {
        let values = model.mornings.map(\.outcome)
        let lo = min(1.0, values.min() ?? 1.0)
        let hi = max(5.0, values.max() ?? 5.0)
        return lo...hi
    }

    private func bucketLabel(_ range: TimeRange) -> String {
        if range.start <= 0 { return "Before \(Clock.format(range.end, suffix: false))" }
        if range.end >= 1440 { return "After \(Clock.format(range.start, suffix: false))" }
        return "\(Clock.format(range.start, suffix: false))\u{2013}\(Clock.format(range.end, suffix: false))"
    }

    private func historyNote(_ history: WakeHistory) -> String {
        var parts: [String] = []
        if let best = history.bestWindow {
            parts.append("Your sweet spot is \(best.label).")
        }
        if let worst = history.buckets.min(by: { $0.mean < $1.mean }), history.buckets.count > 1 {
            parts.append("Waking \(bucketLabel(worst.range).lowercased()) went worst, at \(String(format: "%.1f", worst.mean)).")
        }
        if let advantage = history.lightSleepAdvantage, advantage > 0 {
            parts.append("Light-sleep wake-ups beat deep-sleep ones by about \(String(format: "%.1f", advantage)) points.")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var historyCard: some View {
        let history = model.wakeHistory
        let domain = outcomeDomain
        Card {
            HStack(alignment: .firstTextBaseline) {
                ExplainedTitle(text: "Your past wake-ups", topic: .bestWakeWindow, size: 17)
                Spacer()
                Text("last \(model.mornings.count) mornings").font(.scaled(size: 13)).secondaryText()
            }
            if model.mornings.isEmpty {
                Text("Check in for a few mornings and your best wake window will show up here.")
                    .font(.scaled(size: 14))
                    .secondaryText()
            } else {
                wakeReadout(history)
                WakeHistoryChart(dots: morningDots, bestWindow: history.bestWindow, yDomain: domain,
                                 selected: nearestDot, selection: $selectedWakeHours)
                    .frame(height: 180)
                ScrubHint()
                HStack(spacing: 14) {
                    legendDot(color: Accent.mint.fill(scheme), text: "Woke in light sleep")
                    legendDot(color: Accent.coral.fill(scheme), text: "Woke in deep or REM")
                }
                VStack(spacing: 8) {
                    ForEach(history.buckets, id: \.range) { bucket in
                        BucketRow(label: bucketLabel(bucket.range),
                                  fraction: (bucket.mean - domain.lowerBound) / max(domain.upperBound - domain.lowerBound, 0.001),
                                  value: String(format: "%.1f", bucket.mean),
                                  count: "\(bucket.count)x",
                                  isBest: history.bestWindow.map { bucket.range.contains(($0.start + $0.end) / 2) } ?? false)
                    }
                }
                Text(historyNote(history))
                    .font(.scaled(size: 14))
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nearestDot: MorningDot? {
        guard let selectedWakeHours else { return nil }
        return morningDots.min { abs($0.hours - selectedWakeHours) < abs($1.hours - selectedWakeHours) }
    }

    @ViewBuilder
    private func wakeReadout(_ history: WakeHistory) -> some View {
        if let dot = nearestDot {
            let minutes = Int((dot.hours * 60).rounded())
            let stage: String = dot.light == true ? "Woke in light sleep." : dot.light == false ? "Woke from deep or REM sleep, which feels groggier." : "Sleep stage not recorded."
            let inBest = history.bestWindow?.contains(minutes) ?? false
            ChartReadout(title: "Woke at \(Clock.format(minutes))",
                         value: "Felt " + String(format: "%.1f", dot.outcome) + " of 5",
                         detail: stage + (inBest ? " Inside your best wake window." : ""),
                         accent: dot.light == false ? .coral : .mint)
        } else if let best = history.bestWindow {
            ChartReadout(title: "Your best wake window", value: best.label,
                         detail: "Mornings you woke in this window, you felt best. Touch a dot to see one morning.", accent: .mint)
        } else {
            ChartReadout(title: "\(model.mornings.count) mornings", value: "Still learning",
                         detail: "Touch a dot to see one morning.", accent: .mint)
        }
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.scaled(size: 12, weight: .semibold)).secondaryText()
        }
    }

    // MARK: What the alarm learned

    private var learnedCard: some View {
        let p = Palette(scheme: scheme)
        let known = model.mornings.filter { $0.wokeFromLightSleep != nil }
        let light = known.filter { $0.wokeFromLightSleep == true }
        let deep = known.filter { $0.wokeFromLightSleep == false }
        let lightMean = light.map(\.outcome).mean
        let deepMean = deep.map(\.outcome).mean
        return Card {
            HStack(alignment: .firstTextBaseline) {
                ExplainedTitle(text: "What your smart alarm learned", topic: .smartAlarm, size: 17)
                Spacer()
                Text("last \(known.count) mornings").font(.scaled(size: 13)).foregroundStyle(p.secondary)
            }
            HStack(spacing: 8) {
                LearnedStat(value: "\(model.sleepCycleLength) min", caption: "your cycle length")
                LearnedStat(value: "\(light.count) of \(known.count)", caption: "woke in light sleep")
            }
            if let lightMean, let deepMean {
                HStack(spacing: 8) {
                    LearnedStat(value: String(format: "%.1f", lightMean), caption: "Light-sleep mornings", accent: .mint)
                    LearnedStat(value: String(format: "%.1f", deepMean), caption: "Deep-sleep mornings", accent: .coral)
                }
                Text("How awake you said you felt at your morning check-in, out of 5.")
                    .font(.scaled(size: 13))
                    .foregroundStyle(p.secondary)
            }
            NavigationLink {
                CheckInView()
            } label: {
                HStack(spacing: 6) {
                    Text("See the morning check-in").font(.scaled(size: 15, weight: .semibold))
                    Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .bold)).accessibilityHidden(true)
                }
                .foregroundStyle(Accent.orange.ink(scheme))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Wind-down

    private var lastCaffeineText: String {
        guard let last = model.caffeineDoses.max(by: { $0.time < $1.time }) else {
            if let cutoff = model.caffeineCutoffShown {
                return "None yet \u{00B7} cutoff \(Clock.format(cutoff))"
            }
            return "None yet \u{00B7} " + model.caffeineNoCutoffShort.lowercased()
        }
        return Clock.format(last.time) + (model.caffeineTooMuchAtBedtime ? ", \(model.caffeineAtBedtime) mg left at bed" : ", clears by bed")
    }

    private var windDownCard: some View {
        let bed = store.data.bedtime
        let melatonin = model.energyToday.zone(.melatonin)?.range
        let dimFrom = model.energyToday.zone(.windDown)?.range.start ?? (1440 + bed - 60)
        return Card {
            Text("Tonight's wind-down").font(.scaled(size: 17, weight: .bold))
            WindDownRow(systemImage: "cup.and.saucer.fill", accent: .yellow, title: "Last caffeine", value: lastCaffeineText,
                        note: model.caffeineCutoffShown == nil
                            ? model.caffeineEarlyOnlyText
                            : "Caffeine still in your body at bedtime makes sleep lighter, even if you fall asleep fine.",
                        topic: .caffeineCutoff)
            WindDownRow(systemImage: "lightbulb.fill", accent: .orange, title: "Dim lights, screens down", value: Clock.format(dimFrom),
                        note: "Bright light holds back your body's sleep signal.", topic: .windDown)
            if let melatonin {
                WindDownRow(systemImage: "moon.stars.fill", accent: .purple, title: "Melatonin rising", value: melatonin.label,
                            note: "Your body's own sleep signal, not a pill. Aim to be in bed in this window; you'll fall asleep fastest.",
                            topic: .melatonin)
            }
            WindDownRow(systemImage: "bed.double.fill", accent: .indigo, title: "In bed", value: Clock.format(bed))
        }
    }

    // MARK: Links

    private var linksCard: some View {
        let showClockChange = model.daysUntilFallBack <= 28
        return Card(padding: 12) {
            LinkRow(title: "Your sleep need",
                    subtitle: "\(Clock.duration(model.sleepNeed.minutes)) base, \(Clock.duration(model.tonightNeed.total)) tonight",
                    systemImage: "bed.double.fill", accent: .purple) {
                SleepNeedView()
            }
            Divider()
            LinkRow(title: "Your body clock",
                    subtitle: model.chronotype?.category.rawValue ?? "Still learning",
                    systemImage: "clock.fill", accent: .indigo) {
                ChronotypeView()
            }
            if showClockChange {
                Divider()
                LinkRow(title: "Clocks go back \(model.nextFallBack.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
                        subtitle: "Plan the extra hour",
                        systemImage: "clock.arrow.circlepath", accent: .orange) {
                    TimeChangeView()
                }
            }
            Divider()
            LinkRow(title: model.isAfterMidnight ? "See this morning's energy forecast" : "See tomorrow's energy peaks", subtitle: nil,
                    systemImage: "bolt.fill", accent: .mint) {
                EnergyView()
            }
        }
    }
}

// MARK: - Pieces

private struct MorningDot: Identifiable {
    let id: Int
    let hours: Double
    let outcome: Double
    let light: Bool?
}

/// Whole sleep cycles from sleep onset to the up-by time, with the alarm window.
private struct CycleTimeline: View {
    var onset: Minutes
    var deadline: Minutes
    var cycleLength: Int
    var cycles: Int
    var window: TimeRange
    var wake: Minutes
    @State private var selected: Minutes? = nil
    @Environment(\.colorScheme) private var scheme

    private var span: Double { Double(max(deadline - onset, 1)) }
    private func x(_ minutes: Minutes, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max(Double(minutes - onset) / span, 0), 1)) * width
    }

    private func minutes(atX x: CGFloat, _ width: CGFloat) -> Minutes {
        let f = Double(min(max(x / max(width, 1), 0), 1))
        return onset + Int((f * span).rounded())
    }

    /// Where in the night a time falls, in plain words.
    private func describe(_ m: Minutes) -> (title: String, value: String, detail: String, accent: Accent) {
        let time = Clock.format(m)
        let fullEnd = onset + cycles * cycleLength
        if window.contains(m) {
            return (time, "Smart alarm window",
                    "Your Watch wakes you at the first light sleep in here, by \(Clock.format(window.end)) at the latest.", .orange)
        }
        if m >= fullEnd {
            return (time, "Part of a cycle",
                    "Not enough time for another full cycle before \(Clock.format(deadline)). Waking here could catch you in deep sleep.", .coral)
        }
        let index = (m - onset) / max(cycleLength, 1)
        let into = (m - onset) % max(cycleLength, 1)
        let fraction = Double(into) / Double(max(cycleLength, 1))
        let detail: String
        if fraction < 0.35 {
            detail = "Early in a cycle: light sleep sliding into deep sleep, which is hard to wake from."
        } else if fraction < 0.8 {
            detail = "Middle of a cycle: deep sleep or REM. Waking here feels groggy."
        } else {
            detail = "End of a cycle: light sleep, the easiest time to wake up."
        }
        return ("\(time) \u{00B7} \(into) min in", "Sleep cycle \(index + 1) of \(cycles)", detail, .indigo)
    }

    @ViewBuilder
    private var readout: some View {
        if let selected {
            let d = describe(selected)
            ChartReadout(title: d.title, value: d.value, detail: d.detail, accent: d.accent)
        } else {
            ChartReadout(title: "Asleep about \(Clock.format(onset))", value: "Wake \(Clock.format(wake))",
                         detail: "\(cycles) full sleep cycles of about \(cycleLength) minutes. Touch the bar to see any time.",
                         accent: .orange)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            readout
            timeline
            ScrubHint(text: "Touch and drag along the cycles to see each part of the night")
        }
    }

    private var timeline: some View {
        let p = Palette(scheme: scheme)
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(0..<max(cycles, 0), id: \.self) { i in
                        let start = onset + i * cycleLength
                        let cellWidth = max(x(start + cycleLength, w) - x(start, w) - 2, 2)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Accent.indigo.fill(scheme).opacity(min(0.35 + Double(i) * 0.1, 0.9)))
                            .frame(width: cellWidth, height: 32)
                            .overlay(Text("\(i + 1)").font(.scaled(size: 12, weight: .bold)))
                            .offset(x: x(start, w) + 1, y: 6)
                    }
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Accent.orange.fill(scheme).opacity(0.32))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Accent.orange.fill(scheme), lineWidth: 1.5))
                        .frame(width: max(x(window.end, w) - x(window.start, w), 4), height: 44)
                        .offset(x: x(window.start, w))
                    Capsule()
                        .fill(p.primary)
                        .frame(width: 3, height: 52)
                        .offset(x: x(wake, w) - 1.5, y: -4)
                    if let selected {
                        Rectangle()
                            .fill(Accent.orange.ink(scheme))
                            .frame(width: 2, height: 56)
                            .offset(x: x(selected, w) - 1, y: -6)
                        Circle()
                            .fill(Accent.orange.ink(scheme))
                            .overlay(Circle().strokeBorder(p.primary, lineWidth: 2))
                            .frame(width: 14, height: 14)
                            .offset(x: x(selected, w) - 7, y: 15)
                    }
                }
                .frame(width: w, height: 44, alignment: .topLeading)
                .contentShape(Rectangle())
                .overlay(ScrubSurface { location in selected = minutes(atX: location.x, w) })
            }
            .frame(height: 44)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    Text(Clock.format(onset))
                        .position(x: min(30, w / 2), y: max(16, Font.scaledSize(16)) / 2)
                    Text(Clock.format(wake, suffix: false))
                        .fontWeight(.bold)
                        .foregroundStyle(p.primary)
                        .position(x: min(max(x(wake, w), 70), w - 70), y: max(16, Font.scaledSize(16)) / 2)
                    Text(Clock.format(deadline))
                        .position(x: max(w - 30, w / 2), y: max(16, Font.scaledSize(16)) / 2)
                }
                .font(.scaled(size: 12, weight: .semibold))
                .foregroundStyle(p.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .frame(height: max(16, Font.scaledSize(16)))
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cycles) full sleep cycles from \(Clock.format(onset)), waking at \(Clock.format(wake)) inside a smart alarm window of \(window.label), before \(Clock.format(deadline))")
    }
}

/// Past mornings by wake time, colored by the stage she woke from.
private struct WakeHistoryChart: View {
    let dots: [MorningDot]
    let bestWindow: TimeRange?
    let yDomain: ClosedRange<Double>
    let selected: MorningDot?
    @Binding var selection: Double?
    @Environment(\.colorScheme) private var scheme

    private var xDomain: ClosedRange<Double> {
        let hours = dots.map(\.hours)
        let lo = min(6.0, (hours.min() ?? 6.0) - 0.25)
        let hi = max(10.5, (hours.max() ?? 10.5) + 0.25)
        return lo...hi
    }

    private func color(_ light: Bool?) -> Color {
        switch light {
        case .some(true): return Accent.mint.fill(scheme)
        case .some(false): return Accent.coral.fill(scheme)
        case .none: return Palette(scheme: scheme).tertiary
        }
    }

    private var summary: String {
        var text = "How you felt by wake time over \(dots.count) mornings."
        if let bestWindow { text += " Best when waking \(bestWindow.label)." }
        return text
    }

    @ChartContentBuilder
    private var bandMark: some ChartContent {
        if let bestWindow {
            RectangleMark(xStart: .value("Wake time", Double(bestWindow.start) / 60),
                          xEnd: .value("Wake time", Double(bestWindow.end) / 60),
                          yStart: .value("Felt", yDomain.lowerBound),
                          yEnd: .value("Felt", yDomain.upperBound))
                .foregroundStyle(Accent.mint.fill(scheme).opacity(0.16))
                .annotation(position: .top, alignment: .center) {
                    Text("best for you")
                        .font(.chartLabel(size: 11, weight: .bold))
                        .foregroundStyle(Accent.mint.ink(scheme))
                }
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selected {
            RuleMark(x: .value("Wake time", selected.hours))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.3))
            PointMark(x: .value("Wake time", selected.hours), y: .value("Felt", selected.outcome))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .symbolSize(110)
        }
    }

    var body: some View {
        Chart {
            bandMark
            ForEach(dots) { dot in
                PointMark(x: .value("Wake time", dot.hours), y: .value("Felt", dot.outcome))
                    .symbolSize(34)
                    .foregroundStyle(color(dot.light).opacity(selected == nil ? 1 : 0.5))
            }
            selectionMarks
        }
        .chartScrub($selection)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: [6.0, 7.0, 8.0, 9.0, 10.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text(Clock.format(Int(h * 60)).replacingOccurrences(of: ":00", with: ""))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .accessibilityLabel(summary)
    }
}

/// One wake-time bucket: average outcome as a bar.
private struct BucketRow: View {
    var label: String
    var fraction: Double
    var value: String
    var count: String
    var isBest: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        HStack(spacing: 10) {
            Text(label)
                .font(.scaled(size: 13, weight: isBest ? .bold : .semibold))
                .frame(width: Font.scaledSize(92), alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule()
                        .fill(isBest ? Accent.mint.fill(scheme) : p.primary.opacity(0.35))
                        .frame(width: geo.size.width * CGFloat(max(0.02, min(fraction, 1))))
                }
            }
            .frame(height: 10)
            Text(value).font(.scaled(size: 13, weight: .bold)).frame(width: Font.scaledSize(30), alignment: .trailing)
            Text(count).font(.scaled(size: 12)).foregroundStyle(p.secondary).frame(width: Font.scaledSize(30), alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Waking \(label): average \(value) over \(count.dropLast()) mornings\(isBest ? ", your best" : "")")
    }
}

private struct LearnedStat: View {
    var value: String
    var caption: String
    var accent: Accent? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.scaledNumber(22)).foregroundStyle(accent?.ink(scheme) ?? p.primary)
            Text(caption).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct WindDownRow: View {
    var systemImage: String
    var accent: Accent
    var title: String
    var value: String
    var note: String? = nil
    var topic: Topic? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.scaled(size: 14, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 32, height: 32)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(title).font(.scaled(size: 14, weight: .semibold))
                    if let topic { InfoButton(topic: topic).padding(.vertical, -14).padding(.horizontal, -6) }
                    Spacer(minLength: 8)
                    Text(value).font(.scaled(size: 14, weight: .bold)).multilineTextAlignment(.trailing)
                }
                if let note {
                    Text(note)
                        .font(.scaled(size: 12))
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)
        }
        .accessibilityElement(children: .contain)
    }
}
