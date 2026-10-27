import SwiftUI
import Charts
import HealthCore

/// Your week: last week's energy by day, what the best days shared, what the
/// worst day had, and one goal for this week.
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
                weekHeader(days)
                averageCard(recap)
                daysCard(recap, days: days, need: need)
                bestCard(recap, days: days, need: need)
                worstCard(recap)
                glance(recap, days: days, need: need)
                goalCard(recap, need: need)
                linksCard
            } else {
                emptyCard
                linksCard
            }
        }
    }

    // MARK: Header + average

    private func weekHeader(_ days: [DaySummary]) -> some View {
        let first = days.first?.date ?? .now
        let last = days.last?.date ?? .now
        let sameMonth = Calendar.current.isDate(first, equalTo: last, toGranularity: .month)
        let end = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        let range = "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(end)"
        return Card {
            VStack(spacing: 2) {
                Text(range).font(.scaled(size: 17, weight: .bold))
                Text("The last 7 days \u{00B7} \(days.count) of 7 with a recorded night")
                    .font(.scaled(size: 13)).secondaryText()
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func averageCard(_ recap: WeekRecap) -> some View {
        let avg = recap.averageEnergy
        let diff = avg - usualScore
        let headline: String
        let usual = model.energyUsualPhrase
        if diff <= -2 { headline = "\(-diff) below \(usual)" }
        else if diff >= 2 { headline = "\(diff) above \(usual)" }
        else { headline = "Right around \(usual)" }
        var sub = "\(weekday(recap.best.date, .wide)) was your best day, \(weekday(recap.worst.date, .wide)) your lowest."
        if recap.worst.bedtime >= lateBedtime || recap.worst.asleep < model.sleepNeed.minutes - 30 {
            sub += " Most of the drop traces back to \(weekday(dayBefore(recap.worst.date), .wide)) night."
        }
        return Card(accent: .indigo) {
            HStack(spacing: 18) {
                Ring(value: Double(avg) / 100, accent: .indigo, label: "\(avg)", caption: "Week avg", size: 120,
                     accessibilityText: "Week energy average \(avg) out of 100, estimated from your sleep")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        SectionLabel(text: "Energy score", accent: .indigo)
                        InfoButton(topic: .energyScore).padding(.vertical, -12)
                    }
                    Text(headline).font(.scaled(size: 20, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sub).font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Energy by day

    private func daysCard(_ recap: WeekRecap, days: [DaySummary], need: Int) -> some View {
        let bestIndex = days.firstIndex(of: recap.best) ?? 0
        let selected = min(max(selectedIndex ?? bestIndex, 0), days.count - 1)
        let bars: [RecapDayBar] = days.indices.map { i in
            let d = days[i]
            return RecapDayBar(id: i, label: weekday(d.date, .abbreviated), energy: d.energy,
                          color: barColor(d, recap: recap, selected: i == selected), dimmed: i != selected)
        }
        let labels = bars.map(\.label)
        return Card {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Energy by day").font(.scaled(size: 17, weight: .bold))
                InfoButton(topic: .energyScore).padding(.vertical, -12)
                Spacer()
            }
            Text("Estimated from your sleep each night, not measured.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            if days.indices.contains(selected) {
                dayReadout(days[selected], recap: recap, need: need)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            }
            VStack(spacing: 0) {
                WeekEnergyChart(bars: bars, selection: $chartSelection,
                                summary: "Energy score by day, estimated from sleep: " + bars.map { "\($0.label) \($0.energy)" }.joined(separator: ", "))
                    .frame(height: 150)
                    .onChange(of: chartSelection) {
                        if let s = chartSelection, let i = labels.firstIndex(of: s) { selectedIndex = i }
                    }
                HStack(spacing: 0) {
                    ForEach(bars) { b in
                        let d = days[b.id]
                        let tag: String = d == recap.best ? ", best day" : (d == recap.worst ? ", lowest day" : "")
                        Button { selectedIndex = b.id } label: {
                            Text(b.label)
                                .font(.scaled(size: 12, weight: b.id == selected ? .bold : .semibold))
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
            ScrubHint(text: "Touch and drag across the bars, or tap a day")
            HStack(spacing: 14) {
                legend(Accent.mint.fill(scheme), "Best day")
                legend(Accent.coral.fill(scheme), "Lowest day")
                legend(Accent.indigo.fill(scheme).opacity(0.55), "Other days")
            }
            if days.indices.contains(selected) {
                dayPanel(days[selected], recap: recap, need: need)
            }
        }
    }

    private func dayReadout(_ d: DaySummary, recap: WeekRecap, need: Int) -> ChartReadout {
        let tag: String = d == recap.best ? "Best day · " : (d == recap.worst ? "Lowest day · " : "")
        let diff = d.energy - recap.averageEnergy
        let vsAvg = diff == 0 ? "right on your week's average" : "\(abs(diff)) \(diff > 0 ? "above" : "below") your week's average"
        let sleep = met(d.asleep, need) ? "a full night (\(Clock.duration(d.asleep)))" : "\(Clock.duration(d.asleep)) of sleep, \(Clock.duration(need - d.asleep)) short of your need"
        let wake = d.wokeFromLightSleep ? "woke in light sleep" : "woke from deep sleep, which feels groggier"
        let accent: Accent = d == recap.best ? .mint : (d == recap.worst ? .coral : .indigo)
        return ChartReadout(title: tag + d.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                            value: "Energy score \(d.energy)",
                            detail: "\(vsAvg.prefix(1).uppercased() + vsAvg.dropFirst()). After \(sleep); \(wake).",
                            accent: accent)
    }

    private func barColor(_ d: DaySummary, recap: WeekRecap, selected: Bool) -> Color {
        if d == recap.best { return Accent.mint.fill(scheme) }
        if d == recap.worst { return Accent.coral.fill(scheme) }
        return selected ? Accent.indigo.ink(scheme) : Accent.indigo.fill(scheme).opacity(0.55)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.scaled(size: 12)).secondaryText()
        }
    }

    private func dayPanel(_ d: DaySummary, recap: WeekRecap, need: Int) -> some View {
        let isBest = d == recap.best
        let isWorst = d == recap.worst
        let accent: Accent = isBest ? .mint : (isWorst ? .coral : .indigo)
        let tag: String? = isBest ? "Best day of the week" : (isWorst ? "Lowest day of the week" : nil)
        let title = d.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let facts = facts(for: d, need: need)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.scaled(size: 17, weight: .bold))
                    if let tag {
                        Text(tag).font(.scaled(size: 13, weight: .bold)).foregroundStyle(accent.ink(scheme))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Energy").font(.scaled(size: 12)).secondaryText()
                    Text("\(d.energy)").font(.scaledNumber(30))
                        .foregroundStyle(isBest || isWorst ? accent.ink(scheme) : Palette(scheme: scheme).primary)
                }
                .accessibilityElement(children: .combine)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(facts) { f in RecapFactTile(fact: f) }
            }
            Text(note(for: d, recap: recap, need: need)).font(.scaled(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent.fill(scheme).opacity(0.3)))
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

    // MARK: Best / worst

    private func bestCard(_ recap: WeekRecap, days: [DaySummary], need: Int) -> some View {
        let top = Array(days.sorted { $0.energy > $1.energy }.prefix(max(days.count / 2, 1)))
        let topSorted = top.sorted { $0.date < $1.date }
        let names = listJoin(topSorted.map { weekday($0.date, .abbreviated) })
        let lo = top.map(\.energy).min() ?? 0
        let hi = top.map(\.energy).max() ?? 0
        return Card(accent: .mint) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What your best days had in common").font(.scaled(size: 17, weight: .bold))
                Text("\(names) · energy \(lo) to \(hi)").font(.scaled(size: 13)).secondaryText()
                Text(recap.habitsFromCheckIns
                     ? "Best days picked by how you said you felt at your check-ins."
                     : "Based on your sleep only. Check in each morning and this also uses how you felt.")
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if recap.bestDayHabits.isEmpty {
                Text("No single habit set your better days apart this week.")
                    .font(.scaled(size: 14)).secondaryText()
            } else {
                ForEach(recap.bestDayHabits, id: \.self) { h in RecapHabitRow(ok: true, text: h) }
            }
            LinkRow(title: "Why \(Clock.duration(need)) is your number", systemImage: "moon.zzz.fill", accent: .mint) {
                SleepNeedView()
            }
            HowWeGotThisLink(title: "Your best days",
                             method: recap.habitsFromCheckIns
                                ? "We split last week into the days you rated higher at your morning check-in and the days you rated lower, then list the habits most of your better days had and your lower days didn't."
                                : "We split last week into your higher and lower energy-score days, then list the sleep habits most of your better days had and your lower days didn't. The energy score is estimated from sleep, so only sleep habits are compared; caffeine and daylight are left out until you have 3 or more check-ins.")
        }
    }

    private func worstCard(_ recap: WeekRecap) -> some View {
        let w = recap.worst
        let date = w.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return Card(accent: .coral) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What your worst day had").font(.scaled(size: 17, weight: .bold))
                Text("\(date) · energy \(w.energy)").font(.scaled(size: 13)).secondaryText()
            }
            if recap.worstDayIssues.isEmpty {
                Text("Nothing obvious stood out. Sometimes a day is just a day.")
                    .font(.scaled(size: 14)).secondaryText()
            } else {
                ForEach(recap.worstDayIssues, id: \.self) { issue in RecapHabitRow(ok: false, text: issue) }
            }
        }
    }

    // MARK: Week at a glance

    private func glance(_ recap: WeekRecap, days: [DaySummary], need: Int) -> some View {
        let short = need - recap.averageAsleep
        let sleepNote = met(recap.averageAsleep, need) ? "Need \(Clock.duration(need)) · covered" : "Need \(Clock.duration(need)) · \(Clock.duration(short)) short"
        let deepDays = days.filter { !$0.wokeFromLightSleep }.map { weekday($0.date, .abbreviated) }
        let wakeNote = deepDays.isEmpty ? "Every wake at a cycle end" : "\(listJoin(deepDays)) hit deep sleep"
        let bedtimes = days.map(\.bedtime)
        let avgBed = Clock.circularMean(bedtimes).map { Clock.format($0) } ?? "–"
        let latest = bedtimes.max().map { Clock.format($0) } ?? "–"
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Week at a glance").font(.scaled(size: 20, weight: .bold))
                .padding(.top, 6)
            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink { SleepNeedView() } label: {
                    RecapTile(title: "Avg sleep", topic: .sleepNeed, value: Clock.duration(recap.averageAsleep), note: sleepNote, accent: .purple, systemImage: "moon.fill")
                }
                .buttonStyle(.plain)
                RecapTile(title: "Avg bedtime", topic: .regularity, value: avgBed, note: "Latest \(latest)", accent: .indigo, systemImage: "bed.double.fill")
                NavigationLink { WakePlanView() } label: {
                    RecapTile(title: "Light-sleep wakes", topic: .sleepCycle, value: "\(recap.lightSleepWakes) of \(days.count)", note: wakeNote, accent: .orange, systemImage: "sunrise.fill")
                }
                .buttonStyle(.plain)
                RecapTile(title: "Daylight", topic: .daylight, value: "\(recap.averageDaylight) min", note: "Daily avg · aim for 20+", accent: .yellow, systemImage: "sun.max.fill")
                NavigationLink { CaffeineView() } label: {
                    RecapTile(title: "Caffeine", topic: .caffeineCutoff, value: "\(recap.averageCaffeine) mg", note: "Daily avg · limit 400 mg", accent: .coral, systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.plain)
                RecapTile(title: "Best day", topic: nil, value: weekday(recap.best.date, .wide), note: "Energy score \(recap.best.energy)", accent: .mint, systemImage: "star.fill")
            }
        }
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
                        detail: "Last \(night) night it was \(Clock.format(w.bedtime)). In bed by \(Clock.format(target)), you finish full sleep cycles and wake in light sleep, not halfway through deep sleep.")
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
            return Goal(title: "Wake at the end of a sleep cycle every day",
                        detail: "On \(day) you woke from deep sleep. The smart alarm on your Watch wakes you in light sleep in the half hour before your latest wake time.")
        }
        if w.asleep < need - 30 {
            return Goal(title: "Get \(Clock.duration(need)) on \(night) night",
                        detail: "Last \(night) night you slept \(Clock.duration(w.asleep)), \(Clock.duration(need - w.asleep)) short of your need.")
        }
        return Goal(title: "20 minutes of daylight before noon",
                    detail: "Your days averaged \(recap.averageDaylight) min. Morning light is the strongest signal your body clock gets.")
    }

    private func goalCard(_ recap: WeekRecap, need: Int) -> some View {
        let g = goal(recap, need: need)
        let current = store.data.weeklyGoal
        let isOn = current == g.title
        let worstLabel = "Last \(weekday(recap.worst.date, .abbreviated))"
        return Card(accent: .indigo) {
            SectionLabel(text: "One thing for this week", accent: .indigo)
            Text(g.title).font(.scaled(size: 20, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(g.detail).font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                BarRow(label: worstLabel, fraction: Double(recap.worst.energy) / 100, valueText: "\(recap.worst.energy)", accent: .coral)
                BarRow(label: "Week average", fraction: Double(recap.averageEnergy) / 100, valueText: "\(recap.averageEnergy)", accent: .indigo)
            }
            if let current, !isOn {
                Text("Replaces your current goal: \(current)").font(.scaled(size: 13)).secondaryText()
            }
            PrimaryButton(title: isOn ? "Your goal this week" : "Make it my goal", accent: .indigo, done: isOn) {
                store.data.weeklyGoal = isOn ? nil : g.title
            }
            .accessibilityAddTraits(isOn ? .isSelected : [])
            if isOn {
                Text("Saved as your goal. It stays here until you change it.")
                    .font(.scaled(size: 13)).secondaryText()
            }
        }
    }

    // MARK: Links + empty

    private var linksCard: some View {
        let plan = model.wakePlan()
        let wakeSubtitle = plan.map { "\(model.nextWakeDayLabel) \(Clock.format($0.wake)), end of your \(ordinal($0.cycles)) cycle" } ?? "See your wake plan"
        return Card {
            LinkRow(title: "Today's energy", subtitle: "\(model.energyToday.score) so far, with your peaks and dips",
                    systemImage: "bolt.fill", accent: .mint) { EnergyView() }
            LinkRow(title: "Your sleep need",
                    subtitle: "\(Clock.duration(model.sleepNeed.minutes)) base, \(Clock.duration(model.tonightNeed.total)) tonight",
                    systemImage: "moon.zzz.fill", accent: .purple) { SleepNeedView() }
            LinkRow(title: "Best time to wake", subtitle: wakeSubtitle, systemImage: "alarm.fill", accent: .orange) { WakePlanView() }
        }
    }

    private var emptyCard: some View {
        Card(accent: .indigo) {
            Image(systemName: "calendar.badge.clock")
                .font(.scaled(size: 28, weight: .semibold))
                .foregroundStyle(Accent.indigo.ink(scheme))
                .accessibilityHidden(true)
            Text("Not enough days yet").font(.scaled(size: 20, weight: .bold))
            Text("Your recap compares the last 7 days to find what your best ones have in common. It needs at least 3 days with a recorded night; so far there \(model.lastWeek.count == 1 ? "is" : "are") \(model.lastWeek.count). Keep wearing your Watch to bed and check in each morning.")
                .font(.scaled(size: 14)).secondaryText()
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

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
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
                .opacity(b.dimmed ? 0.45 : 1)
                .cornerRadius(8)
                .annotation(position: .top, spacing: 4) {
                    Text("\(b.energy)").font(.scaledNumber(13))
                }
        }
        .chartXScale(domain: bars.map(\.label))
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartScrub($selection)
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
            Text(fact.label).font(.scaled(size: 12)).foregroundStyle(p.secondary)
            Text(fact.value).font(.scaledNumber(18)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            if !fact.sub.isEmpty {
                Text(fact.sub).font(.scaled(size: 12)).foregroundStyle(p.secondary).lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .font(.scaled(size: 12, weight: .heavy))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 26, height: 26)
                .background(accent.tint(scheme), in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.scaled(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A week-at-a-glance tile whose title carries an ⓘ.
private struct RecapTile: View {
    var title: String
    var topic: Topic?
    var value: String
    var note: String
    var accent: Accent
    var systemImage: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(title).font(.scaled(size: 14, weight: .bold))
                if let topic { InfoButton(topic: topic).padding(.vertical, -12) }
                Spacer(minLength: 0)
                Image(systemName: systemImage).foregroundStyle(accent.ink(scheme)).accessibilityHidden(true)
            }
            Text(value).font(.scaledNumber(24)).minimumScaleFactor(0.6).lineLimit(1)
            Text(note).font(.scaled(size: 12, weight: .semibold)).secondaryText()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
