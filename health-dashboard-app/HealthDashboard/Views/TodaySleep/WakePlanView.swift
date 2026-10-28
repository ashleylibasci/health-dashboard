import SwiftUI
import Charts
import HealthCore

/// The Sleep plan: tonight's bed-by and wake time from her best sleep times,
/// the smart alarm, HRV by bedtime from her own nights, and the details
/// (regularity, sleep cycles, past wake-ups, wind-down, her times) one tap
/// down. Opened from Today's Tonight card and the Sleep tab's best-times card.
struct WakePlanView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedWakeHours: Double? = nil
    @State private var selectedSlot: Minutes? = nil

    var body: some View {
        let best = model.bestTimes
        let tonight = model.tonightPlan
        Screen(title: "Sleep plan", accent: .purple) {
            SampleDataBanner()
            summary(best, tonight: tonight)
            controls(tonight)
            hrvCard(best)
            details(best, tonight: tonight)
            Card(density: .compact) {
                LearnMoreRow("Learn more about your best sleep times", article: .bestSleepTimes, accent: .purple)
            }
        }
        .sensoryFeedback(.success, trigger: store.data.smartAlarmEnabled) { old, new in !old && new }
    }

    // MARK: Summary

    private func summary(_ best: SleepTiming.Result, tonight: TonightPlan) -> some View {
        SummaryHeader(eyebrow: "Your best sleep times",
                      value: Clock.format(model.tonightBedtime), unit: "bed by",
                      status: BestTimesText.status(best),
                      line: BestTimesText.line(best),
                      pairs: [StatPair(label: "Up at", value: Clock.format(tonight.wake ?? tonight.upBy)),
                              StatPair(label: "Best window", value: best.bed.label)],
                      accent: .purple, info: explanation(best))
    }

    private func explanation(_ best: SleepTiming.Result) -> Explanation {
        let forYou = [best.confidenceText, best.clockNote, BestTimesText.earlierReason(model), model.usualBedtimeNote,
                      model.wakeTimesExplained].compactMap { $0 }
        return Explanation(id: "best-sleep-times", title: "Your best sleep times",
                           meaning: "Bed by is the latest bedtime that still covers your sleep need before your up-by time, or your body clock's bedtime when that's earlier. After 28 school nights of your own, the nights your body did best on can move it earlier, never later. Up at is your best wake time: the end of a sleep cycle just before up-by, or up-by itself.",
                           forYou: forYou.joined(separator: " "))
    }

    // MARK: Smart alarm and bedtime

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

    private func controls(_ tonight: TonightPlan) -> some View {
        let best = model.bestTimes.bed.end
        return RowCard {
            if let window = tonight.alarmWindow {
                ToggleRow(title: "Smart alarm",
                          note: store.data.smartAlarmEnabled ? "\(window.label) \u{00B7} on your Watch" : "Off \u{00B7} would be \(window.label)",
                          systemImage: "alarm.fill", accent: .orange, isOn: alarmBinding)
                if store.data.smartAlarmEnabled {
                    RowDivider()
                    ToggleRow(title: "Weekdays only", note: "No smart alarm on Saturday and Sunday mornings",
                              systemImage: "calendar", accent: .orange, isOn: $store.data.alarmWeekdaysOnly)
                        .motionTransition(.reveal, edge: .top)
                }
            } else {
                MetricRowLabel(title: "No full sleep cycle fits",
                               note: "Pick a later up-by time under Your times",
                               systemImage: "alarm", accent: .coral)
            }
            if !model.bedtimeMatchesBest {
                RowDivider()
                MetricRow(title: "Use \(Clock.format(best)) as your usual bedtime",
                          note: "Now \(Clock.format(store.data.bedtime)); your caffeine cutoff and energy use it",
                          systemImage: "moon.fill", accent: .purple,
                          action: { withMotion(.commit) { store.data.bedtime = best } })
            }
        }
    }

    // MARK: HRV by bedtime

    private var slots: [SleepTiming.Slot] { model.bestTimesSlots.filter { $0.hrvPct != nil } }

    private func slotLabel(_ start: Minutes) -> String { TimeRange(start, start + 30).label }

    private func slotDetail(_ slot: SleepTiming.Slot, best: SleepTiming.Result) -> String {
        let nights = "\(slot.nights) \(slot.nights == 1 ? "night" : "nights")"
        if let range = best.evidence?.bestOnsets, slot.start + 30 > range.start, slot.start <= range.end {
            return "\(nights) \u{00B7} in the group your body did best on"
        }
        return slot.nights < 3 ? "\(nights) \u{00B7} too few to read much into" : nights
    }

    private func overviewDetail(_ best: SleepTiming.Result) -> String {
        "\(best.nightsUsed) school nights so far. Nights after drinks, exams or being sick are left out."
    }

    @ViewBuilder
    private func hrvReadout(_ best: SleepTiming.Result) -> some View {
        let all = [overviewDetail(best)] + slots.map { slotDetail($0, best: best) }
        if let start = selectedSlot, let slot = slots.first(where: { $0.start == start }), let hrv = slot.hrvPct {
            ChartReadout(title: "Asleep \(slotLabel(slot.start)) \u{00B7} next-morning HRV",
                         value: SleepText.signed(hrv) + "% \u{00B7} vs your usual",
                         detail: slotDetail(slot, best: best), accent: hrv >= 0 ? .purple : .coral,
                         onClear: { selectedSlot = nil }, detailSlots: all)
        } else {
            ChartReadout(title: "Your HRV by bedtime", value: "\(best.nightsUsed) of \(best.nightsNeeded) \u{00B7} nights",
                         detail: overviewDetail(best), accent: .purple, detailSlots: all)
        }
    }

    private func hrvCard(_ best: SleepTiming.Result) -> some View {
        Card {
            if slots.isEmpty {
                Text("Your HRV by bedtime").font(.cardTitle)
                Text("Your own school nights show here as the Watch records them: \(best.nightsUsed) of \(best.nightsNeeded) so far.")
                    .font(.bodyText)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                hrvReadout(best)
                BedtimeHRVChart(slots: slots, best: best.evidence?.bestOnsets,
                                selected: selectedSlot,
                                selection: $selectedSlot.snapping { raw in
                                    slots.min { abs($0.start + 15 - raw) < abs($1.start + 15 - raw) }?.start
                                })
                    .frame(height: 170)
                HStack(spacing: Space.m) {
                    legendSwatch(color: Accent.purple.fill(scheme), text: best.evidence == nil ? "Your nights" : "Best group")
                    if best.evidence != nil {
                        legendSwatch(color: Palette(scheme: scheme).secondary.opacity(0.5), text: "Others")
                    }
                    Spacer(minLength: 0)
                    Text("0 = your usual").font(.secondary).secondaryText()
                }
            }
        }
    }

    // MARK: Details

    private func cycleSource() -> String {
        model.usingSampleData ? "a typical cycle length of \(model.sleepCycleLength) minutes (yours is measured once you have 14 nights)"
            : "your own cycle length of \(model.sleepCycleLength) minutes, measured from your nights"
    }

    private func wakeMethod(_ latency: Int) -> String {
        "We count sleep cycles from about \(latency) minutes after your bedtime, using \(cycleSource()). If the last cycle ends in the \(WakePlanner.maxCycleTrade) minutes before your up-by time (and still covers tonight's need when up-by would), that's your best wake; otherwise it's your up-by time, so you never lose more than about \(WakePlanner.maxCycleTrade) minutes of sleep to land on a cycle. The smart alarm window is the \(AppModel.alarmWindowLead + 3) minutes around it, never past up-by. Cycle timing varies from night to night, so this is a rough guide."
    }

    private func details(_ best: SleepTiming.Result, tonight: TonightPlan) -> some View {
        let plan = tonight.plan
        let history = model.wakeHistory
        return RowCard {
            if let regularity = BestTimesText.regularity(best) {
                ExpandRow(title: "How regular you are", summary: "\(best.regularityHits) of your last \(best.regularityOf) nights near this window",
                          systemImage: "metronome.fill", accent: .purple) {
                    Text(regularity).fixedSize(horizontal: false, vertical: true)
                }
                RowDivider()
            }
            if let plan {
                ExpandRow(title: "Your sleep cycles tonight", summary: plan.reasons.first?.title,
                          systemImage: "waveform.path.ecg", accent: .indigo) {
                    CycleTimeline(onset: model.tonightBedtime + best.latency, deadline: store.data.upBy,
                                  cycleLength: model.sleepCycleLength, cycles: plan.cycles, window: plan.alarmWindow, wake: plan.wake)
                    ForEach(plan.reasons, id: \.self) { reason in
                        ReasonRow(ok: reason.ok, title: reason.title, detail: reason.detail)
                    }
                    Text(wakeMethod(best.latency)).font(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                RowDivider()
            }
            ExpandRow(title: "Mornings you felt best", summary: historySummary(history),
                      systemImage: "sun.horizon.fill", accent: .mint) {
                pastWakeUps(history)
            }
            RowDivider()
            ExpandRow(title: "Tonight's wind-down", summary: "Dim lights \(Clock.format(dimFrom))",
                      systemImage: "lightbulb.fill", accent: .orange) {
                windDown
            }
            RowDivider()
            ExpandRow(title: "Your times", summary: "Up by \(Clock.format(store.data.upBy)) \u{00B7} usual bed \(Clock.format(store.data.bedtime))",
                      systemImage: "clock.fill", accent: .purple) {
                timesContent(latency: best.latency)
            }
        }
    }

    // MARK: Your times

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

    @ViewBuilder
    private func timesContent(latency: Int) -> some View {
        DatePicker(selection: upByBinding, displayedComponents: .hourAndMinute) {
            Label("I need to be up by", systemImage: "sunrise.fill").font(.bodyEmphasis)
        }
        .foregroundStyle(Palette(scheme: scheme).primary)
        .frame(minHeight: 44)
        DatePicker(selection: bedtimeBinding, displayedComponents: .hourAndMinute) {
            Label("Usual bedtime", systemImage: "moon.fill").font(.bodyEmphasis)
        }
        .foregroundStyle(Palette(scheme: scheme).primary)
        .frame(minHeight: 44)
        Text("Up-by is the latest you need to be up; your best times never go past it. Your usual bedtime sets your caffeine cutoff, energy curve and bedtime streaks. Asleep about \(latency) minutes after getting into bed. Changes reach your Watch right away.")
            .font(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

    private func historySummary(_ history: WakeHistory) -> String {
        if model.mornings.isEmpty { return "Check in for a few mornings" }
        if let best = history.bestWindow { return "Waking \(best.label)" }
        return model.mornings.count >= 10 ? "No clear best window yet" : "Still learning"
    }

    private func historyNote(_ history: WakeHistory) -> String {
        var parts: [String] = []
        if let best = history.bestWindow {
            parts.append("Your sweet spot is \(best.label).")
        } else if model.mornings.count >= 10 {
            // Liu 10: no window clearly beat the rest.
            parts.append("No clear best window yet: no wake time has clearly beaten the others.")
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
    private func pastWakeUps(_ history: WakeHistory) -> some View {
        let domain = outcomeDomain
        if model.mornings.isEmpty {
            Text("Check in for a few mornings and your best wake window will show up here.")
        } else {
            wakeReadout(history)
            WakeHistoryChart(dots: morningDots, bestWindow: history.bestWindow, yDomain: domain,
                             selected: nearestDot,
                             selection: $selectedWakeHours.snapping { raw in
                                 morningDots.min { abs($0.hours - raw) < abs($1.hours - raw) }?.hours
                             })
                .frame(height: 170)
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
            Text(historyNote(history)).fixedSize(horizontal: false, vertical: true)
            learned
        }
    }

    private var nearestDot: MorningDot? {
        guard let selectedWakeHours else { return nil }
        return morningDots.min { abs($0.hours - selectedWakeHours) < abs($1.hours - selectedWakeHours) }
    }

    private func dotDetail(_ dot: MorningDot, history: WakeHistory) -> String {
        let stage: String = dot.light == true ? "Woke in light sleep." : dot.light == false ? "Woke from deep or REM sleep, which feels groggier." : "Sleep stage not recorded."
        let inBest = history.bestWindow?.contains(Int((dot.hours * 60).rounded())) ?? false
        return stage + (inBest ? " Inside your best wake window." : "")
    }

    @ViewBuilder
    private func wakeReadout(_ history: WakeHistory) -> some View {
        let idle: (value: String, detail: String) = if let best = history.bestWindow {
            (best.label, "Mornings you woke in this window, you felt best.")
        } else if model.mornings.count >= 10 {
            ("No clear best window", "No wake time has clearly beaten the others so far.")
        } else {
            ("Still learning", "Check in for a few more mornings to see which wake times suit you.")
        }
        let slots = [idle.detail] + morningDots.map { dotDetail($0, history: history) }
        if let dot = nearestDot {
            ChartReadout(title: "Woke at \(Clock.format(Int((dot.hours * 60).rounded()))) \u{00B7} how awake you felt",
                         value: String(format: "%.1f", dot.outcome) + " of 5",
                         detail: dotDetail(dot, history: history),
                         accent: dot.light == false ? .coral : .mint,
                         onClear: { selectedWakeHours = nil }, detailSlots: slots)
        } else {
            ChartReadout(title: history.bestWindow == nil ? "\(model.mornings.count) mornings" : "Your best wake window",
                         value: idle.value, detail: idle.detail, accent: .mint, detailSlots: slots)
        }
    }

    private var learned: some View {
        let known = model.mornings.filter { $0.wokeFromLightSleep != nil }
        let light = known.filter { $0.wokeFromLightSleep == true }
        let deep = known.filter { $0.wokeFromLightSleep == false }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LearnedStat(value: "\(model.sleepCycleLength) min", caption: "your cycle length")
                LearnedStat(value: "\(light.count) of \(known.count)", caption: "woke in light sleep")
            }
            if let lightMean = light.map(\.outcome).mean, let deepMean = deep.map(\.outcome).mean {
                HStack(spacing: 8) {
                    LearnedStat(value: String(format: "%.1f", lightMean), caption: "Light-sleep mornings", accent: .mint)
                    LearnedStat(value: String(format: "%.1f", deepMean), caption: "Deep-sleep mornings", accent: .coral)
                }
                Text("How awake you said you felt at your morning check-in, out of 5.")
                    .font(.secondary)
            }
        }
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.secondary).fontWeight(.semibold).secondaryText()
        }
    }

    private func legendSwatch(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 10)
            Text(text).font(.secondary).fontWeight(.semibold).secondaryText()
        }
    }

    // MARK: Wind-down

    private var dimFrom: Minutes {
        model.energyToday.zone(.windDown)?.range.start ?? (1440 + model.tonightBedtime - 60)
    }

    private var lastCaffeineText: String {
        guard let last = model.caffeineDoses.max(by: { $0.time < $1.time }) else {
            if let cutoff = model.caffeineCutoffShown {
                return "None yet \u{00B7} cutoff \(Clock.format(cutoff))"
            }
            return "None yet \u{00B7} " + model.caffeineNoCutoffShort.lowercased()
        }
        return Clock.format(last.time) + (model.caffeineTooMuchAtBedtime ? ", \(model.caffeineAtBedtime) mg left at bed" : ", clears by bed")
    }

    @ViewBuilder
    private var windDown: some View {
        let melatonin = model.energyToday.zone(.melatonin)?.range
        WindDownRow(systemImage: "cup.and.saucer.fill", accent: .yellow, title: "Last caffeine", value: lastCaffeineText,
                    note: model.caffeineCutoffShown == nil
                        ? model.caffeineEarlyOnlyText
                        : "Caffeine still in your body at bedtime makes sleep lighter, even if you fall asleep fine.",
                    topic: .caffeineCutoff)
        WindDownRow(systemImage: "lightbulb.fill", accent: .orange, title: "Dim lights, screens down", value: Clock.format(dimFrom),
                    note: "About 2 hours before you usually fall asleep. Bright light holds back your body's sleep signal.", topic: .windDown)
        if let melatonin {
            WindDownRow(systemImage: "moon.stars.fill", accent: .purple, title: "Sleep window", value: melatonin.label,
                        note: "The hour before you usually fall asleep. Your body's own sleep hormone (not a pill) is up by now, so it's usually the easiest time to drift off.",
                        topic: .melatonin)
        }
        WindDownRow(systemImage: "bed.double.fill", accent: .indigo, title: "In bed", value: Clock.format(model.tonightBedtime))
    }
}

/// A row with a switch: icon tile, title and a one-line note, the toggle
/// trailing. The row's own height and padding match `MetricRow`.
private struct ToggleRow: View {
    var title: String
    var note: String
    var systemImage: String
    var accent: Accent
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: Space.m) {
                RowIcon(systemImage: systemImage, accent: accent)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(.bodyEmphasis)
                        .foregroundStyle(Palette(scheme: scheme).primary)
                    Text(note)
                        .font(.secondary)
                        .foregroundStyle(Palette(scheme: scheme).secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .tint(accent.fill(scheme))
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: Sizes.tallRow, alignment: .leading)
    }
}

/// Her next-morning HRV against her usual, by when she fell asleep, in
/// 30-minute slots. The best group (when there is one) in purple; zero is
/// her usual (named in the legend, not on the plot).
private struct BedtimeHRVChart: View {
    let slots: [SleepTiming.Slot]
    let best: TimeRange?
    let selected: Minutes?
    @Binding var selection: Minutes?
    @Environment(\.colorScheme) private var scheme

    private func inBest(_ slot: SleepTiming.Slot) -> Bool {
        guard let best else { return true }
        return slot.start + 30 > best.start && slot.start <= best.end
    }

    private func color(_ slot: SleepTiming.Slot) -> Color {
        let p = Palette(scheme: scheme)
        var c = inBest(slot) ? Accent.purple.fill(scheme) : p.secondary.opacity(0.5)
        if let selected, selected != slot.start { c = c.opacity(0.4) }
        return c
    }

    private var summary: String {
        "Next-morning HRV against your usual by when you fell asleep, \(slots.count) half-hour slots."
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("HRV", 0))
                .foregroundStyle(Palette(scheme: scheme).secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(slots, id: \.start) { slot in
                BarMark(x: .value("Asleep", slot.start + 15), y: .value("HRV", slot.hrvPct ?? 0), width: .ratio(0.7))
                    .foregroundStyle(color(slot))
                    .cornerRadius(3)
            }
        }
        .chartScrub($selection, snapped: selected, steps: slots.map(\.start))
        .transaction(value: selected) { $0.animation = nil }
        .chartXScale(domain: (slots.first.map { $0.start } ?? 0)...((slots.last.map { $0.start + 30 }) ?? 30))
        .chartXAxis {
            AxisMarks(values: slots.map(\.start).filter { $0 % 60 == 0 }) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let m = value.as(Int.self) { Text(Clock.format(m).replacingOccurrences(of: ":00", with: "")) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(SleepText.signed(v) + "%") }
                }
            }
        }
        .chartAxisTextCapped()
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(ValueChartDescriptor(
            title: "HRV by bedtime", seriesName: "Half-hour slots", xTitle: "Fell asleep", yTitle: "HRV against your usual",
            points: slots.map { (Double($0.start), $0.hrvPct ?? 0) },
            xLabel: { Clock.format(Int($0)) }, yLabel: { SleepText.signed($0) + "%" }))
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
                    "Your Watch wakes you when you start stirring in here, by \(Clock.format(window.end)) at the latest.", .orange)
        }
        if m >= fullEnd {
            return (time, "After your last full cycle",
                    "Not enough time for another full cycle before \(Clock.format(deadline)). Sleeping on is still worth more than waking early to finish one.", .indigo)
        }
        let index = (m - onset) / max(cycleLength, 1)
        let into = (m - onset) % max(cycleLength, 1)
        let fraction = Double(into) / Double(max(cycleLength, 1))
        let detail: String
        if fraction < 0.8 {
            detail = index < 2
                ? "Early in the night, when most deep sleep happens. Waking now would feel groggy."
                : "Middle of a cycle. Later in the night most of it is lighter sleep and REM."
        } else {
            detail = "Near the end of a cycle. Waking around here can feel a bit easier. Cycle timing varies, so it's a rough guide."
        }
        return ("\(time) \u{00B7} \(into) min in", "Sleep cycle \(index + 1) of \(cycles)", detail, .indigo)
    }

    /// Every note the readout can show, so it keeps one height.
    private var detailSlots: [String] {
        let notes = stride(from: onset, through: deadline, by: 5).map { describe($0).detail }
        return Array(Set(notes)).sorted() + [idleDetail]
    }

    private var idleDetail: String { "\(cycles) full sleep cycles of about \(cycleLength) minutes." }

    @ViewBuilder
    private var readout: some View {
        if let selected {
            let d = describe(selected)
            ChartReadout(title: d.title, value: d.value, detail: d.detail, accent: d.accent,
                         onClear: { self.selected = nil }, detailSlots: detailSlots)
        } else {
            ChartReadout(title: "Asleep about \(Clock.format(onset)) \u{00B7} wake", value: Clock.format(wake),
                         detail: idleDetail, accent: .orange, detailSlots: detailSlots)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            readout
            timeline
            ScrubHint(each: "part of the night")
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
                        RoundedRectangle(cornerRadius: Radius.mark * 2, style: .continuous)
                            .fill(Accent.purple.fill(scheme).opacity(min(0.45 + Double(i) * 0.1, 0.9)))
                            .frame(width: cellWidth, height: 32)
                            .overlay(Text("\(i + 1)").font(.secondary).fontWeight(.bold))
                            .offset(x: x(start, w) + 1, y: 6)
                    }
                    RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                        .fill(Accent.orange.fill(scheme).opacity(0.32))
                        .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
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
                // Snapped to 5 minutes; written only when it changes.
                .overlay(ScrubSurface { location in
                    let m = Int((Double(minutes(atX: location.x, w)) / 5).rounded()) * 5
                    if m != selected { selected = m }
                })
                .scrubFeedback(selected.map { describe($0).title })
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
                .font(.secondary).fontWeight(.semibold)
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
                .annotation(position: .top, alignment: .center,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
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
        .chartScrub($selection, snapped: selected?.hours, steps: Array(Set(dots.map(\.hours))).sorted())
        // Every dot's opacity changes on selection: no animation per drag step.
        .transaction(value: selected?.hours) { $0.animation = nil }
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
        .accessibilityChartDescriptor(ValueChartDescriptor(
            title: "How awake you felt by wake time", seriesName: "Mornings", xTitle: "Wake time", yTitle: "How awake, out of 5",
            points: dots.map { ($0.hours, $0.outcome) },
            xLabel: { Clock.format(Int(($0 * 60).rounded())) }, yLabel: { String(format: "%.1f", $0) }))
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let p = Palette(scheme: scheme)
        let bar = GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.track)
                Capsule()
                    .fill(isBest ? Accent.mint.fill(scheme) : p.secondary)
                    .frame(width: geo.size.width * CGFloat(max(0.02, min(fraction, 1))))
            }
        }
        .frame(height: 10)
        Group {
            if typeSize.isAccessibilitySize {
                // Label and numbers on one line, the bar full width below,
                // instead of fixed columns wider than the screen.
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(label).font(.secondary).fontWeight(isBest ? .bold : .semibold)
                        Spacer(minLength: Space.s)
                        Text("\(value) \u{00B7} \(count)").font(.secondary).fontWeight(.bold)
                    }
                    bar
                }
            } else {
                HStack(spacing: 10) {
                    Text(label)
                        .font(.secondary).fontWeight(isBest ? .bold : .semibold)
                        .frame(width: Font.scaledSize(92), alignment: .leading)
                    bar
                    Text(value).font(.secondary).fontWeight(.bold).frame(width: Font.scaledSize(30), alignment: .trailing)
                    Text(count).font(.secondary).foregroundStyle(p.secondary).frame(width: Font.scaledSize(30), alignment: .trailing)
                }
            }
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
            Text(value).font(.numberM).foregroundStyle(accent?.ink(scheme) ?? p.primary)
            Text(caption).font(.secondary).fontWeight(.semibold).foregroundStyle(p.secondary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
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
    @State private var explaining: Explanation? = nil

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
                    if let topic {
                        InfoButton(topic: topic).padding(.vertical, -14).padding(.horizontal, -6)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 8)
                    Text(value).font(.bodyEmphasis).multilineTextAlignment(.trailing)
                }
                if let note {
                    Text(note)
                        .font(.secondary)
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)
        }
        // One stop per row: title and time together, the ⓘ as an action
        // (Ortiz F8, F9).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, value.replacingOccurrences(of: "\u{2013}", with: " to "), note].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAction(named: "Explain") { explaining = topic?.explanation }
        .sheet(item: $explaining) { ExplanationSheet(explanation: $0) }
    }
}
