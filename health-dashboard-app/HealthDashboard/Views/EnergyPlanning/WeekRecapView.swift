import SwiftUI
import Charts
import HealthCore

/// Your week: the week's average energy first, the 7 days as bars, then the
/// details one tap down: a day up close, what the best days shared, what
/// the lowest day had, one goal for this week, and streaks.
struct WeekRecapView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    private var usualScore: Int { model.energyUsual }
    /// A bedtime at or after this counts as late (her usual + 90 min, or 2am).
    private var lateBedtime: Minutes { model.lateBedtimeThreshold }

    @State private var selectedIndex: Int? = nil
    @State private var chartSelection: String? = nil

    /// The one "met her need" rule used everywhere (within 15 minutes).
    private func met(_ asleep: Int, _ need: Int) -> Bool { SleepNeedEstimator.metNeed(asleep: asleep, need: need) }

    /// Caffeine that day was more than the night could clear: after her
    /// cutoff, or (when the cutoff falls before she's up) more than one small
    /// early drink.
    private func caffeineTooLate(_ d: DaySummary) -> Bool {
        if let cutoff = model.caffeineCutoffShown { return (d.lastCaffeine ?? 0) > cutoff }
        return d.caffeineMg > model.caffeineLargestDoseAtWake
    }

    var body: some View {
        Screen(title: "Your week", accent: .indigo) {
            SampleDataBanner()
            if let recap = model.weekRecap, !model.lastWeek.isEmpty {
                let days = model.lastWeek.sorted { $0.date < $1.date }
                let need = model.sleepNeed.minutes
                let bestIndex = days.firstIndex(of: recap.best) ?? 0
                let selected = min(max(selectedIndex ?? bestIndex, 0), days.count - 1)
                summary(recap, days: days)
                daysCard(recap, days: days, need: need, selected: selected)
                RowCard {
                    if days.indices.contains(selected) {
                        dayRow(days[selected], recap: recap, need: need)
                        RowDivider()
                    }
                    bestRow(recap, days: days)
                    RowDivider()
                    worstRow(recap)
                    RowDivider()
                    goalRow(recap, need: need)
                    RowDivider()
                    streaksRow
                }
                Card(density: .compact) {
                    LearnMoreRow("Learn more about energy", article: .energyThroughTheDay, accent: .indigo)
                }
            } else {
                emptyCard
            }
        }
    }

    // MARK: Summary

    private func summary(_ recap: WeekRecap, days: [DaySummary]) -> some View {
        let avg = recap.averageEnergy
        let diff = avg - usualScore
        let usual = model.energyUsualIsPersonal ? "your \(usualScore)" : "\(usualScore)"
        let status: SummaryStatus
        // A lower week is information, not a warning: blue, not coral.
        if diff <= -2 { status = SummaryStatus(text: "\(-diff) below \(usual)", accent: .blue) }
        else if diff >= 2 { status = SummaryStatus(text: "\(diff) above \(usual)", accent: .mint) }
        else { status = SummaryStatus(text: "Around \(usual)", accent: .indigo) }
        let avgBed = Clock.circularMean(days.map(\.bedtime)).map { Clock.format($0) } ?? "\u{2013}"
        let nights = model.usingSampleData ? "example week" : "\(model.weekRecapDays) of 7 nights"
        return SummaryHeader(eyebrow: "\(weekRange(days)) \u{00B7} \(nights)", value: "\(avg)", unit: "week average", status: status,
                             line: "\(weekday(recap.best.date, .wide)) was your best day, \(weekday(recap.worst.date, .wide)) your lowest.",
                             pairs: [StatPair(label: "Avg sleep", value: Clock.duration(recap.averageAsleep)),
                                     StatPair(label: "Avg bedtime", value: avgBed)],
                             accent: .indigo, info: Topic.energyScore.explanation)
    }

    /// "Oct 21–27"
    private func weekRange(_ days: [DaySummary]) -> String {
        let first = days.first?.date ?? .now
        let last = days.last?.date ?? .now
        let sameMonth = Calendar.current.isDate(first, equalTo: last, toGranularity: .month)
        let end = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(end)"
    }

    // MARK: Energy by day

    private func daysCard(_ recap: WeekRecap, days: [DaySummary], need: Int, selected: Int) -> some View {
        let bars: [RecapDayBar] = days.indices.map { i in
            let d = days[i]
            return RecapDayBar(id: i, label: weekday(d.date, .abbreviated), energy: d.energy,
                          color: barColor(d, recap: recap, selected: i == selected), dimmed: i != selected)
        }
        let labels = bars.map(\.label)
        return Card {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Energy by day").font(.cardTitle)
                Text("Estimated from your sleep each night, not measured.")
                    .font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if days.indices.contains(selected) {
                dayReadout(days[selected], recap: recap, need: need,
                           slots: days.map { dayDetail($0, recap: recap, need: need) })
            }
            VStack(spacing: 0) {
                WeekEnergyChart(bars: bars, selection: $chartSelection,
                                summary: "Energy score by day, estimated from sleep: " + bars.map { "\($0.label) \($0.energy)" }.joined(separator: ", "))
                    .frame(height: 130)
                    .accessibilityChartDescriptor(DateChartDescriptor(
                        title: "Energy score by day, estimated from sleep", seriesName: "Energy score", yTitle: "Energy score",
                        points: days.map { ($0.date, Double($0.energy)) }, yLabel: { "\(Int($0.rounded())) of 100" },
                        isContinuous: false))
                    .onChange(of: chartSelection) {
                        if let s = chartSelection, let i = labels.firstIndex(of: s) { selectedIndex = i }
                    }
                HStack(spacing: 0) {
                    ForEach(bars) { b in
                        let d = days[b.id]
                        let tag: String = d == recap.best ? ", best day" : (d == recap.worst ? ", lowest day" : "")
                        Button { selectedIndex = b.id } label: {
                            Text(b.label)
                                .font(.secondary).fontWeight(b.id == selected ? .bold : .semibold)
                                .foregroundStyle(b.id == selected ? Palette(scheme: scheme).primary : Palette(scheme: scheme).secondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(weekday(d.date, .wide)), energy \(d.energy)\(tag)")
                        .accessibilityAddTraits(b.id == selected ? .isSelected : [])
                    }
                }
            }
            ScrubHint(each: "day")
            FlowLayout(spacing: 14, lineSpacing: 6) {
                legend(Accent.mint.fill(scheme), "Best day")
                legend(Accent.coral.fill(scheme), "Lowest day")
                legend(otherDay, "Other days")
            }
        }
    }

    /// The readout's note for a day: against the week's average, then the
    /// night before.
    private func dayDetail(_ d: DaySummary, recap: WeekRecap, need: Int) -> String {
        let diff = d.energy - recap.averageEnergy
        let vsAvg = diff == 0 ? "right on your week's average" : "\(abs(diff)) \(diff > 0 ? "above" : "below") your week's average"
        let sleep = met(d.asleep, need) ? "a full night (\(Clock.duration(d.asleep)))" : "\(Clock.duration(d.asleep)) of sleep, \(Clock.duration(need - d.asleep)) short of your need"
        let wake = d.wokeFromLightSleep ? "woke in light sleep" : "woke from deep sleep, which feels groggier"
        return "\(vsAvg.prefix(1).uppercased() + vsAvg.dropFirst()). After \(sleep); \(wake)."
    }

    private func dayReadout(_ d: DaySummary, recap: WeekRecap, need: Int, slots: [String]) -> ChartReadout {
        let tag: String = d == recap.best ? "Best day · " : (d == recap.worst ? "Lowest day · " : "")
        let accent: Accent = d == recap.best ? .mint : (d == recap.worst ? .coral : .indigo)
        return ChartReadout(title: tag + d.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " \u{00B7} energy score",
                            value: "\(d.energy)",
                            detail: dayDetail(d, recap: recap, need: need),
                            accent: accent, detailSlots: slots)
    }

    private func barColor(_ d: DaySummary, recap: WeekRecap, selected: Bool) -> Color {
        if d == recap.best { return Accent.mint.fill(scheme) }
        if d == recap.worst { return Accent.coral.fill(scheme) }
        return selected ? Accent.indigo.ink(scheme) : otherDay
    }

    /// Other days: a solid mid indigo that passes 3:1 in both modes, not a
    /// see-through fill (Tanaka F7).
    private var otherDay: Color { Color(hex: scheme == .dark ? 0x6670B8 : 0x7A84D9) }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.secondary).secondaryText()
        }
    }

    // MARK: Rows

    /// The day picked on the chart, up close: six facts and a sentence.
    private func dayRow(_ d: DaySummary, recap: WeekRecap, need: Int) -> some View {
        let isBest = d == recap.best
        let isWorst = d == recap.worst
        let accent: Accent = isBest ? .mint : (isWorst ? .coral : .indigo)
        let tag = isBest ? "Best day of the week" : (isWorst ? "Lowest day of the week" : "Energy \(d.energy)")
        return ExpandRow(title: "\(d.date.formatted(.dateTime.weekday(.wide))) up close", summary: tag,
                         systemImage: "calendar", accent: accent) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(facts(for: d, need: need)) { f in RecapFactTile(fact: f) }
            }
            Text(note(for: d, recap: recap, need: need)).font(.bodyText)
                .foregroundStyle(Palette(scheme: scheme).primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func facts(for d: DaySummary, need: Int) -> [RecapDayFact] {
        let window = model.wakeHistory.bestWindow
        let caffeineSub = d.lastCaffeine.map { "last at \(Clock.format($0))" } ?? "none"
        return [
            RecapDayFact(label: "Sleep", value: Clock.duration(d.asleep), sub: "need \(Clock.duration(need))", ok: met(d.asleep, need)),
            RecapDayFact(label: "Bedtime", value: Clock.format(d.bedtime), sub: "\(weekday(dayBefore(d.date), .abbreviated)) night",
                    ok: d.bedtime < lateBedtime ? nil : false),
            RecapDayFact(label: "Woke at", value: Clock.format(d.wake), sub: window.map { "best \($0.label)" } ?? "",
                    ok: window.map { $0.contains(d.wake) }),
            RecapDayFact(label: "Woke in", value: d.wokeFromLightSleep ? "Light sleep" : "Deep sleep",
                    sub: d.wokeFromLightSleep ? "at a cycle end" : "mid-cycle", ok: d.wokeFromLightSleep),
            RecapDayFact(label: "Daylight", value: "\(d.daylightMinutes) min", sub: "aim for 20+", ok: d.daylightMinutes >= 20),
            RecapDayFact(label: "Caffeine", value: "\(d.caffeineMg) mg", sub: caffeineSub, ok: !caffeineTooLate(d)),
        ]
    }

    private func note(for d: DaySummary, recap: WeekRecap, need: Int) -> String {
        if d == recap.best {
            let n = recap.bestDayHabits.count
            if n == 0 { return "Your best day of the week." }
            return n == 1
                ? "Your best day of the week, with the habit your good days shared."
                : "Your best day of the week, with the \(n) habits your good days shared."
        }
        if d == recap.worst {
            if recap.worstDayIssues.isEmpty { return "Your lowest day, without one obvious cause." }
            return "Your lowest day. " + recap.worstDayIssues.joined(separator: ". ") + "."
        }
        var good: [String] = []
        var bad: [String] = []
        if met(d.asleep, need) { good.append("a full night") } else { bad.append("\(Clock.duration(need - d.asleep)) short of your need") }
        if d.wokeFromLightSleep { good.append("a light-sleep wake") } else { bad.append("an alarm that hit deep sleep") }
        if d.daylightMinutes >= 20 { good.append("\(d.daylightMinutes) min of daylight") } else { bad.append("only \(d.daylightMinutes) min of daylight") }
        if let last = d.lastCaffeine, caffeineTooLate(d) {
            bad.append(model.caffeineCutoffShown == nil ? "\(d.caffeineMg) mg of caffeine" : "caffeine at \(Clock.format(last))")
        }
        if d.bedtime >= lateBedtime { bad.append("a \(Clock.format(d.bedtime)) bedtime") }
        if bad.isEmpty { return "Back on rhythm: " + listJoin(good) + "." }
        if good.isEmpty { return "A harder day: " + listJoin(bad) + "." }
        return capitalizedFirst(listJoin(good)) + ", but held back by " + listJoin(bad) + "."
    }

    private func bestRow(_ recap: WeekRecap, days: [DaySummary]) -> some View {
        let top = Array(days.sorted { $0.energy > $1.energy }.prefix(max(days.count / 2, 1)))
        let topSorted = top.sorted { $0.date < $1.date }
        let names = listJoin(topSorted.map { weekday($0.date, .abbreviated) })
        let lo = top.map(\.energy).min() ?? 0
        let hi = top.map(\.energy).max() ?? 0
        return ExpandRow(title: "What your best days had in common", summary: "\(names) · energy \(lo) to \(hi)",
                         systemImage: "checkmark.circle.fill", accent: .mint) {
            Text(recap.habitsFromCheckIns
                 ? "Best days picked by how you said you felt at your check-ins."
                 : "Based on your sleep only. Check in each morning and this also uses how you felt.")
                .font(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(recap.betterDays) better days vs \(recap.lowerDays) lower days" + (recap.enoughForPattern ? "." : ": too few to call it a pattern (that takes \(HabitEffect.minimumNights)+ of each), so treat these as hints."))
                .font(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if recap.bestDayHabits.isEmpty {
                Text("No single habit set your better days apart this week.")
            } else {
                ForEach(recap.bestDayHabits, id: \.self) { h in RecapHabitRow(ok: true, text: h) }
            }
            HowWeGotThisLink(title: "Your best days",
                             method: recap.habitsFromCheckIns
                                ? "We split last week into the days you rated higher at your morning check-in and the days you rated lower, then list the habits most of your better days had and your lower days didn't."
                                : "We split last week into your higher and lower energy-score days, then list the sleep habits most of your better days had and your lower days didn't. The energy score is estimated from sleep, so only sleep habits are compared; caffeine and daylight are left out until you have 3 or more check-ins.")
        }
    }

    private func worstRow(_ recap: WeekRecap) -> some View {
        let w = recap.worst
        let date = w.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return ExpandRow(title: "What your lowest day had", summary: "\(date) · energy \(w.energy)",
                         systemImage: "exclamationmark.circle.fill", accent: .coral) {
            if w.bedtime >= lateBedtime || w.asleep < model.sleepNeed.minutes - 30 {
                // One night can explain one day; it isn't a pattern (round 3, N6).
                let late = w.bedtime >= lateBedtime
                Text("\(weekday(dayBefore(w.date), .wide)) night was " + (late ? "a late one" : "short") + ", which likely played a part.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if recap.worstDayIssues.isEmpty {
                Text("Nothing obvious stood out. Sometimes a day is just a day.")
            } else {
                ForEach(recap.worstDayIssues, id: \.self) { issue in RecapHabitRow(ok: false, text: issue) }
            }
        }
    }

    private var streaksRow: some View {
        let going = model.streaks.filter { $0.current > 0 }.count
        let earned = model.badges.filter(\.earned).count
        return MetricRow(title: "Streaks and badges",
                         note: "\(going) of \(model.streaks.count) streaks going \u{00B7} \(earned) \(earned == 1 ? "badge" : "badges")",
                         systemImage: "flame.fill", accent: .yellow) { AchievementsView() }
    }

    // MARK: Goal

    private struct Goal {
        var title: String
        var detail: String
    }

    private func goal(_ recap: WeekRecap, need: Int) -> Goal {
        let w = recap.worst
        let night = weekday(dayBefore(w.date), .wide)
        let day = weekday(w.date, .wide)
        if w.bedtime >= lateBedtime {
            let target = max(store.data.bedtime, ((w.bedtime - 60) / 30) * 30)
            return Goal(title: "Keep \(night) bedtime before \(Clock.format(target))",
                        detail: "Last \(night) night it was \(Clock.format(w.bedtime)). In bed by \(Clock.format(target)), you get more of your sleep need before your alarm, and more of the deep sleep that comes early in the night.")
        }
        if let last = w.lastCaffeine, caffeineTooLate(w) {
            guard let cutoffTime = model.caffeineCutoffShown else {
                return Goal(title: model.caffeineNoCutoffShort,
                            detail: "On \(day) you had \(w.caffeineMg) mg. " + model.caffeineEarlyOnlyText)
            }
            let cutoff = Clock.format(cutoffTime)
            return Goal(title: "Last caffeine before \(cutoff)",
                        detail: "On \(day) your last drink was at \(Clock.format(last)). Caffeine after \(cutoff) is still in your system at bedtime and makes sleep lighter.")
        }
        if !w.wokeFromLightSleep {
            return Goal(title: "Try the smart alarm on your Watch",
                        detail: "On \(day) you woke from deep sleep. The smart alarm wakes you when you start stirring in the 25 minutes before your latest wake time, which can feel a bit easier.")
        }
        if w.asleep < need - 30 {
            return Goal(title: "Get \(Clock.duration(need)) on \(night) night",
                        detail: "Last \(night) night you slept \(Clock.duration(w.asleep)), \(Clock.duration(need - w.asleep)) short of your need.")
        }
        return Goal(title: "20 minutes of daylight before noon",
                    detail: "Your days averaged \(recap.averageDaylight) min. Morning light is the strongest signal your body clock gets.")
    }

    private func goalRow(_ recap: WeekRecap, need: Int) -> some View {
        let g = goal(recap, need: need)
        let current = store.data.weeklyGoal
        let isOn = current == g.title
        let worstLabel = "Last \(weekday(recap.worst.date, .abbreviated))"
        return ExpandRow(title: "One thing for this week", summary: g.title, systemImage: "target", accent: .indigo) {
            Text(g.title).font(.cardTitle).foregroundStyle(Palette(scheme: scheme).primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(g.detail)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                BarRow(label: worstLabel, fraction: Double(recap.worst.energy) / 100, valueText: "\(recap.worst.energy)", accent: .coral)
                BarRow(label: "Week average", fraction: Double(recap.averageEnergy) / 100, valueText: "\(recap.averageEnergy)", accent: .indigo)
            }
            if let current, !isOn {
                Text("Replaces your current goal: \(current)").font(.secondary)
            }
            PrimaryButton(title: isOn ? "Your goal this week" : "Make it my goal", accent: .indigo, done: isOn) {
                store.data.weeklyGoal = isOn ? nil : g.title
            }
            .accessibilityAddTraits(isOn ? .isSelected : [])
            if isOn {
                Text("Saved as your goal. It stays here until you change it.").font(.secondary)
            }
        }
    }

    // MARK: Empty

    private var emptyCard: some View {
        Card(accent: .indigo) {
            Image(systemName: "calendar.badge.clock")
                .font(.detailTitle)
                .foregroundStyle(Accent.indigo.ink(scheme))
                .accessibilityHidden(true)
            Text("Not enough days yet").font(.section)
            Text("Your recap compares the last 7 days to find what your best ones have in common. It needs at least 3 days with a recorded night; so far there \(model.lastWeek.count == 1 ? "is" : "are") \(model.lastWeek.count). Keep wearing your Watch to bed and check in each morning.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "Check in for today", systemImage: "checkmark.circle.fill", accent: .indigo) { CheckInView() }
        }
    }

    // MARK: Helpers

    private func weekday(_ date: Date, _ style: Date.FormatStyle.Symbol.Weekday) -> String {
        date.formatted(.dateTime.weekday(style))
    }

    private func dayBefore(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
    }

    private func listJoin(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }

    private func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}

// MARK: - Subviews

private struct RecapDayBar: Identifiable {
    let id: Int
    let label: String
    let energy: Int
    let color: Color
    let dimmed: Bool
}

private struct WeekEnergyChart: View {
    var bars: [RecapDayBar]
    @Binding var selection: String?
    var summary: String

    var body: some View {
        Chart(bars) { b in
            BarMark(x: .value("Day", b.label), y: .value("Energy", b.energy), width: .ratio(0.5))
                .foregroundStyle(b.color)
                .cornerRadius(Radius.mark * 2)
                .annotation(position: .top, spacing: 4) {
                    Text("\(b.energy)").font(.chartLabel(size: 12, weight: .bold)).monospacedDigit()
                }
        }
        .chartXScale(domain: bars.map(\.label))
        // Headroom above 100, so a 95 bar's label stays on the plot (Weber C7).
        .chartYScale(domain: 0...115)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartScrub($selection, snapped: selection, steps: bars.map(\.label))
        .accessibilityLabel(summary)
    }
}

private struct RecapDayFact: Identifiable {
    var id: String { label }
    var label: String
    var value: String
    var sub: String
    /// true = good, false = worth fixing, nil = neutral.
    var ok: Bool?
}

private struct RecapFactTile: View {
    var fact: RecapDayFact
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        let color: Color
        switch fact.ok {
        case .some(true): color = Accent.mint.ink(scheme)
        case .some(false): color = Accent.coral.ink(scheme)
        case .none: color = p.primary
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(fact.label).font(.secondary).foregroundStyle(p.secondary)
            Text(fact.value).font(.numberM).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            if !fact.sub.isEmpty {
                Text(fact.sub).font(.secondary).foregroundStyle(p.secondary).lineLimit(2)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RecapHabitRow: View {
    var ok: Bool
    var text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent: Accent = ok ? .mint : .coral
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark" : "exclamationmark")
                .font(.secondary).fontWeight(.bold)
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 26, height: 26)
                .background(accent.tint(scheme), in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .accessibilityElement(children: .combine)
    }
}
