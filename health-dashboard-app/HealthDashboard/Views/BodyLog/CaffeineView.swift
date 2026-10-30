import SwiftUI
import Charts
import HealthCore

/// Caffeine today, summary first: how much, whether her usual drink still
/// fits before bed and until when, and one-tap logging (the Log tab's
/// card). Today's drinks open in place; the caffeine in her body, the best
/// time for caffeine and the cutoff test are a tap down (structure review,
/// Oct 28: the old page was four screens with a squeezed ring on top).
struct CaffeineView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var toast: UndoToast?
    @State private var editing: AppData.LoggedDrink?
    @State private var showsNotes = false

    /// The bar is a gauge against this, not a goal to fill.
    private let dailyLimit = CaffeineModel.dailyGuideMg
    private let bedtimeGoal = Int(CaffeineModel.bedtimeLimitMg)

    var body: some View {
        Screen(title: "Caffeine", accent: .yellow) {
            SampleDataBanner()
            if let note = dailyNotes.first {
                CalloutBar(text: note.short, systemImage: "info.circle.fill", accent: .orange) { showsNotes = true }
            }
            header
            CaffeineQuickLog(toast: $toast, compact: true)
            rows
            Card(density: .compact) {
                LearnMoreRow("Learn more about caffeine", section: "caffeineWater", accent: .yellow)
            }
        }
        .sheet(item: $editing) { entry in
            editor(entry)
        }
        .bottomSheet(isPresented: $showsNotes, title: "Today\u{2019}s caffeine") {
            ForEach(dailyNotes, id: \.self) { note in
                Text(note.full)
                    .font(.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .undoToast($toast)
    }

    // MARK: Summary

    /// Her usual drink (the first saved one), or a 12 oz drip coffee.
    private var usual: Drink { store.data.savedDrinks.first ?? AppModel.referenceCoffee }

    /// Whether her usual drink fits now: the chip says what to do, the line
    /// what it would leave at bedtime. Dose-aware, counting today's drinks.
    private var verdict: (status: SummaryStatus, line: String) {
        let drink = usual
        let t = model.now
        let name = LogFormat.midSentence(drink)
        let a = drink.isCustom ? "Your" : ("aeiou".contains(name.prefix(1)) ? "An" : "A")
        guard model.wouldBeTooMuchAtBedtime(mg: drink.caffeineMg, at: t) else {
            return (SummaryStatus(text: "Fits before bed", accent: .mint),
                    "\(a) \(name) (\(drink.caffeineMg) mg) now is fine: under \(bedtimeGoal) mg left by your \(Clock.format(model.bedtimeTonight)) bedtime.")
        }
        // The total at bedtime, with today's other drinks: say so, or "a
        // 130 mg latte would leave 140 mg" reads as wrong (round 3).
        let withOthers = model.caffeineDoses.isEmpty ? "" : ", counting what you\u{2019}ve had"
        let line = "\(a) \(name) now would leave about \(model.caffeineAtBedtime(adding: drink.caffeineMg, at: t)) mg at bedtime\(withOthers)."
        if let latest = model.latestTimeForCaffeine(mg: drink.caffeineMg), latest > t {
            return (SummaryStatus(text: "Have it by \(Clock.format(latest))", accent: .yellow), line)
        }
        // "More" only once she's had some today.
        let skip = model.caffeineDoses.isEmpty ? "Past today\u{2019}s cutoff" : "Skip more today"
        return (SummaryStatus(text: skip, accent: .orange), line)
    }

    /// The biggest drink that still fits now (mg, in 5s).
    private var roomNow: Int {
        CaffeineModel.largestDose(at: model.now, bedtime: model.bedtimeTonight, existing: model.caffeineDoses,
                                  halfLifeHours: model.caffeineHalfLifeHours, wake: model.caffeineWakeTime)
    }

    private var pairs: [StatPair] {
        let last = model.caffeineDoses.last.map { dose in
            "\(model.todaysDrinks.last?.name ?? "Caffeine") \u{00B7} \(Clock.format(dose.time))"
        }
        var out = [StatPair(label: "Last drink", value: last ?? "None yet")]
        // No clock time works for a full coffee today: "Early only", with
        // the reason in the summary's ⓘ (design review F24).
        out.append(StatPair(label: "Cutoff", value: model.caffeineCutoffShown.map { Clock.format($0) } ?? "Early only"))
        return out
    }

    /// The daily limit, led by why the cutoff is "Early only" when it is.
    private var headerInfo: Explanation {
        guard model.caffeineCutoffShown == nil else { return CaffeineWaterCopy.dailyLimit }
        let room = roomNow >= 5 ? " Right now, up to \(roomNow) mg still fits." : ""
        return Explanation(id: "caffeineEarlyOnly", title: "Cutoff: early only",
                           meaning: model.caffeineEarlyOnlyText + room,
                           forYou: CaffeineWaterCopy.dailyLimit.meaning + " " + CaffeineWaterCopy.dailyLimitForYou)
    }

    private var header: some View {
        let v = verdict
        let mg = model.caffeineMgToday
        return SummaryHeader(eyebrow: "Caffeine today", value: "\(mg)", unit: "mg", status: v.status, line: v.line,
                             pairs: pairs, accent: .yellow, info: headerInfo) {
            SummaryMeter(fraction: Double(mg) / Double(dailyLimit), accent: .yellow,
                         caption: "Up to \(dailyLimit) mg a day is generally fine")
        }
    }

    private struct Note: Hashable {
        var short: String
        var full: String
    }

    /// Gentle notes, no alarm: over 400 mg today, and a single drink over
    /// 200 mg (a big single dose). One line on the screen, the rest on tap.
    private var dailyNotes: [Note] {
        var notes: [Note] = []
        let total = model.caffeineMgToday
        if total > dailyLimit {
            notes.append(Note(short: "\(total) mg today, more than the \(dailyLimit) mg that\u{2019}s generally fine.",
                              full: "That\u{2019}s \(total) mg today, more than the \(dailyLimit) mg that\u{2019}s generally fine. Water or decaf for the rest of the day is easier on your heart and sleep. Feeling shaky or a racing heart? Stop there."))
        }
        if let big = model.todaysDrinks.last(where: { $0.mg > CaffeineModel.lowerGuideMg }) {
            notes.append(Note(short: "Your \(big.name) was \(big.mg) mg in one go.",
                              full: "Your \(big.name) was \(big.mg) mg in one go: a big single dose. Over \(CaffeineModel.lowerGuideMg) mg at once is more likely to make you jittery; a smaller size or splitting it up helps."))
        }
        if bleedingToday {
            // D5: polyphenols in coffee and tea cut non-heme iron absorption.
            notes.append(Note(short: "Bleeding today: coffee an hour away from meals helps your iron.",
                              full: "Coffee or tea an hour away from meals lets you absorb more iron from your food. It matters most on bleeding days, when you\u{2019}re losing some."))
        }
        return notes
    }

    /// Light, medium or heavy flow logged today (not spotting).
    private var bleedingToday: Bool {
        store.data.flowLog.contains { Calendar.current.isDateInToday($0.date) && [.light, .medium, .heavy].contains($0.flow) }
    }

    // MARK: Rows

    private var todaySummary: String {
        let n = model.todaysDrinks.count
        return n == 0 ? "None yet" : "\(n) drink\(n == 1 ? "" : "s") \u{00B7} \(model.caffeineMgToday) mg"
    }

    private var rows: some View {
        let test = model.cutoffTest
        return RowCard {
            ExpandRow(title: "Today\u{2019}s drinks", summary: todaySummary, systemImage: "list.bullet", accent: .yellow) {
                todayList
            }
            RowDivider()
            // "0 mg · About 0 mg at bedtime" said 0 twice (design review F23).
            MetricRow(title: "Caffeine in your body",
                      note: model.caffeineAtBedtime < 5 ? "Clears by bedtime" : "About \(model.caffeineAtBedtime) mg at bedtime",
                      value: "\(Int(model.caffeineInBody(at: model.now).rounded())) mg",
                      systemImage: "waveform.path.ecg", accent: .yellow) {
                CaffeineBodyView()
            }
            RowDivider()
            MetricRow(title: "Best time for caffeine", note: "Timed to your energy", systemImage: "clock.fill", accent: .mint) {
                CaffeineTimingView()
            }
            RowDivider()
            ExpandRow(title: "Your caffeine, your sleep", summary: caffeineSleepSummary, systemImage: "moon.zzz.fill", accent: .purple) {
                caffeineSleepDetail
            }
            RowDivider()
            MetricRow(title: "Find your caffeine limit", note: "\(min(test.nightsLogged, test.target)) of \(test.target) nights",
                      systemImage: "flask.fill", accent: .mint) {
                CutoffTestView()
            }
        }
    }

    /// "14 min longer to fall asleep", or "12 of 20 nights".
    private var caffeineSleepSummary: String {
        let c = model.caffeineSleep
        guard c.enoughData, let d = c.minutesLonger else {
            return "\(min(c.nights, CaffeineSleepComparison.nightsNeeded)) of \(CaffeineSleepComparison.nightsNeeded) nights"
        }
        if abs(d) < 5 { return "About the same either way" }
        return "\(abs(d)) min \(d > 0 ? "longer" : "quicker") to fall asleep"
    }

    /// Her own nights, with how many there are (E4).
    @ViewBuilder
    private var caffeineSleepDetail: some View {
        let c = model.caffeineSleep
        let limit = Int(CaffeineModel.bedtimeLimitMg)
        if c.enoughData, let d = c.minutesLonger {
            Text(abs(d) < 5
                 ? "On nights with more than \(limit) mg left at bedtime, you fell asleep about as quickly as on other nights."
                 : "On nights with more than \(limit) mg left at bedtime, you took \(abs(d)) minutes \(d > 0 ? "longer" : "less") to fall asleep.")
            Text("From your \(c.nights) logged nights: \(c.over) with more than \(limit) mg left, \(c.under) with less. A pattern in your own nights, not proof: other things change on those days too.")
                .font(.secondary)
        } else {
            Text("After \(CaffeineSleepComparison.nightsNeeded) nights of logging (at least \(CaffeineSleepComparison.nightsPerSide) with more than \(limit) mg left at bedtime and \(CaffeineSleepComparison.nightsPerSide) with less), this shows how your caffeine changes how fast you fall asleep. So far: \(c.nights) nights, \(c.over) over \(limit) mg.")
        }
    }

    @ViewBuilder
    private var todayList: some View {
        if model.todaysDrinks.isEmpty {
            Text("Nothing logged yet today.")
        } else {
            LogEntryList(items: model.todaysDrinks.reversed(), onTap: { editing = $0 },
                         onDelete: { model.deleteDrink($0.id) }) { entry in
                LogEntryRow(systemImage: symbol(for: entry), accent: .yellow, title: entry.name,
                            detail: "\(entry.mg) mg", time: Clock.format(Clock.minutesOfDay(entry.date)))
            }
            .foregroundStyle(Palette(scheme: scheme).primary)
            Text("Tap an entry to change its time or caffeine. Swipe left to delete.")
                .font(.secondary)
        }
    }

    private func symbol(for entry: AppData.LoggedDrink) -> String {
        let all = store.data.savedDrinks + Drink.common
        if let drink = all.first(where: { $0.id == entry.drinkID }) ?? all.first(where: { $0.name == entry.name }) {
            return BodyLogStyle.symbol(for: drink.icon)
        }
        return "cup.and.saucer.fill"
    }

    private func editor(_ entry: AppData.LoggedDrink) -> some View {
        LogEditSheet(title: entry.name, accent: .yellow, date: entry.date, amount: Double(entry.mg), unit: "mg",
                     step: 5, range: 0...600,
                     onSave: { date, mg in model.updateDrink(entry.id, date: date, mg: Int(mg.rounded())) },
                     onDelete: { model.deleteDrink(entry.id) })
            .environmentObject(model)
            .environmentObject(store)
    }
}

// MARK: - Caffeine in your body

/// Today's caffeine in her body, hour by hour: the falloff chart, what's
/// left at bedtime, and the cutoff. One tap down from Caffeine; a page,
/// not an expanding row, because a scrub chart shouldn't shift the page.
struct CaffeineBodyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedTime: Int?

    private let bedtimeGoal = Int(CaffeineModel.bedtimeLimitMg)

    var body: some View {
        let points = curve
        Screen(title: "Caffeine in your body", accent: .yellow) {
            SampleDataBanner()
            chartCard(points)
            RowCard {
                ExpandRow(title: "At bedtime",
                          summary: model.caffeineAtBedtime >= bedtimeGoal && model.caffeineCountedAtBedtime < bedtimeGoal
                              ? "About \(model.caffeineAtBedtime) mg \u{00B7} under the goal without your morning coffee"
                              : "About \(model.caffeineAtBedtime) mg \u{00B7} goal under \(bedtimeGoal) mg",
                          systemImage: "moon.zzz.fill", accent: .yellow) {
                    Text(bedtimeNote)
                }
                RowDivider()
                ExpandRow(title: "Cutoff", summary: cutoffSummary, systemImage: "clock.badge.exclamationmark", accent: .orange) {
                    if model.caffeineCutoffShown != nil {
                        Text("Your last caffeine of the day, so very little is left by your \(Clock.format(bedtime)) bedtime.")
                    } else {
                        Text(model.caffeineEarlyOnlyText)
                    }
                    HowWeGotThisLink(topic: .caffeineCutoff, label: "About the cutoff")
                }
            }
            Card(density: .compact) {
                HowWeGotThisLink(title: "Caffeine in your body",
                                 method: "Caffeine takes about 45 minutes to be fully absorbed, then about \(Int(model.caffeineHalfLifeHours)) hours for half of it to leave your body. That's 5 hours for most people (somewhere between 3 and 7), and about 7 (one and a half times as long) on the combined pill, which slows how fast the liver clears it, from one small study; the ring and patch probably do the same. The app uses the one that fits your birth control setting. We add up every drink you logged at the time you had it; drinks after midnight count toward the evening before, until \(Clock.format(AppDay.rolloverMinutes)). Your cutoff is the latest time a 12 oz drip coffee (140 mg) would drop below \(bedtimeGoal) mg by your bedtime, rounded down to the half hour. Your morning coffee or tea (up to \(CaffeineModel.lowerGuideMg) mg in the first \(Int(CaffeineModel.morningHours)) hours after you wake) never counts against you, so the cutoff is never earlier than that. Bigger drinks need to be earlier: the summary on the Caffeine screen checks your usual drink\u{2019}s real size.")
            }
        }
    }

    private var cutoffSummary: String {
        model.caffeineCutoffShown.map { "\(Clock.format($0)) \u{00B7} your last caffeine of the day" }
            ?? "Early only \u{00B7} right after you wake, or smaller"
    }

    private var bedtime: Minutes { 1440 + model.tonightBedtime }

    private var chartStart: Minutes {
        let first = model.caffeineDoses.map(\.time).min() ?? model.lastNight.wake
        return (min(first, model.lastNight.wake) / 60) * 60
    }

    private var chartEnd: Minutes { bedtime + 60 }

    private var curve: [CaffeinePoint] {
        stride(from: chartStart, through: chartEnd, by: 10).map { t in
            CaffeinePoint(time: t, mg: model.caffeineInBody(at: t))
        }
    }

    private func nearest(_ t: Int, in points: [CaffeinePoint]) -> CaffeinePoint? {
        points.min { abs($0.time - t) < abs($1.time - t) }
    }

    /// The readout for a point on the curve, or for now when nothing is
    /// selected. `cutoff` and `now` come in so the slots don't recompute them.
    private func readout(_ point: CaffeinePoint?, cutoff: Minutes?, now: Minutes) -> (title: String, value: String, detail: String) {
        guard let p = point else {
            let mg = model.caffeineInBody(at: now)
            return ("Now \u{00B7} \(Clock.format(now))", "\(Int(mg.rounded())) mg \u{00B7} in your body", AppModel.caffeineMeaning(mg: mg))
        }
        var title = Clock.format(p.time)
        var detail = AppModel.caffeineMeaning(mg: p.mg)
        if abs(p.time - bedtime) <= 10 {
            title += " \u{00B7} your bedtime"
            detail += p.mg < Double(bedtimeGoal) ? " Under the \(bedtimeGoal) mg goal, so it shouldn't get in the way of deep sleep."
                : model.caffeineCountedAtBedtime < bedtimeGoal ? " Under the \(bedtimeGoal) mg goal, not counting your morning coffee."
                : " Over \(bedtimeGoal) mg at bedtime can make sleep a little lighter, even if you fall asleep fine."
        } else if let cutoff, abs(p.time - cutoff) <= 10 {
            title += " \u{00B7} your cutoff"
            detail += " Caffeine after this is still in you at bedtime."
        } else if p.time > now {
            detail += " Predicted, if you have no more caffeine."
        }
        return (title, "\(Int(p.mg.rounded())) mg \u{00B7} in your body", detail)
    }

    private func chartCard(_ points: [CaffeinePoint]) -> some View {
        let selected = selectedTime.flatMap { nearest($0, in: points) }
        let cutoff = model.caffeineCutoffShown
        let now = model.now
        let r = readout(selected, cutoff: cutoff, now: now)
        return Card(accent: .yellow) {
            HStack(spacing: 0) {
                Text("Through the day").font(.bodyEmphasis).accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s)
                InfoButton(topic: .caffeineLeft).padding(.vertical, -12).padding(.trailing, -12)
            }
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .yellow,
                         onClear: selectedTime == nil ? nil : { selectedTime = nil },
                         detailSlots: [readout(nil, cutoff: cutoff, now: now).detail]
                            + points.map { readout($0, cutoff: cutoff, now: now).detail })
            CaffeineFalloffChart(points: points, start: chartStart, end: chartEnd, cutoff: cutoff,
                                 bedtime: bedtime, now: now, goal: bedtimeGoal,
                                 selected: selected,
                                 selection: $selectedTime.snapping { t in nearest(t, in: points)?.time })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartSummary(points))
                .accessibilityChartDescriptor(ClockChartDescriptor(
                    title: "Caffeine in your body", seriesName: "Caffeine", yTitle: "Milligrams",
                    points: points.map { ($0.time, $0.mg) },
                    yLabel: { "\(Int($0.rounded())) mg" }))
            ScrubHint(each: "hour")
        }
    }

    private var bedtimeNote: String {
        if model.caffeineAtBedtime < bedtimeGoal { return "Under the \(bedtimeGoal) mg goal. Good for deep sleep." }
        if model.caffeineCountedAtBedtime < bedtimeGoal { return "Under the \(bedtimeGoal) mg goal, not counting your morning coffee." }
        if let cutoff = model.caffeineCutoffShown {
            return "Above the \(bedtimeGoal) mg goal. Next time, finish caffeine by \(Clock.format(cutoff))."
        }
        return "Above the \(bedtimeGoal) mg goal. Next time, keep it to one small drink soon after you wake (up to about \(model.caffeineLargestDoseAtWake) mg)."
    }

    private func chartSummary(_ points: [CaffeinePoint]) -> String {
        let peak = points.max { $0.mg < $1.mg }
        let peakText = peak.map { "peaks near \(Int($0.mg.rounded())) mg at \(Clock.format($0.time))" } ?? "stays at zero"
        let cutoffText = model.caffeineCutoffShown.map { "cutoff \(Clock.format($0))" } ?? "cutoff early only, right after you wake"
        return "Caffeine in your body today \(peakText) and falls to about \(model.caffeineAtBedtime) mg by your \(Clock.format(bedtime)) bedtime, goal under \(bedtimeGoal) mg, \(cutoffText)."
    }
}

// MARK: - Best time for caffeine

/// When caffeine works best today or tomorrow, against her energy curve:
/// grogginess, the best window, the afternoon dip and the cutoff. One tap
/// down from Caffeine.
struct CaffeineTimingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var timingDay: TimingDay = .today
    @State private var selectedTiming: Int?

    private let bedtimeGoal = Int(CaffeineModel.bedtimeLimitMg)

    enum TimingDay: String, CaseIterable, Identifiable {
        case today = "Today", tomorrow = "Tomorrow"
        var id: String { rawValue }
    }

    /// One day's timing, worked out once per redraw: the energy curve
    /// behind it is costly, and the readout asks about every 5 minutes.
    private struct Day {
        var label: String
        var timing: CaffeineModel.Timing
        var groggy: TimeRange?
        var dip: TimeRange?
        /// No safe window for a typical drink (the cutoff comes before
        /// grogginess clears): no window and no cutoff time are shown.
        var noWindow: Bool { timing.cutoffBeforeWindow }
        /// From 7am (or earlier if she's up earlier) to an hour after bedtime.
        var span: ClosedRange<Minutes>
        /// The dot on the timeline: today's first drink, or tomorrow's coffee nap.
        var marker: Minutes?

        /// The scrubbed time, to the 5 minutes, inside the strip.
        func snap(_ raw: Int) -> Int { min(max((raw / 5) * 5, span.lowerBound), span.upperBound) }
    }

    /// After midnight (before the app day rolls over) "tomorrow" is the
    /// morning she's about to wake up to.
    private func label(_ day: TimingDay) -> String {
        switch day {
        case .today: return model.isAfterMidnight ? "Since you woke" : "Today"
        case .tomorrow: return model.nextWakeDayLabel
        }
    }

    private var day: Day {
        let timing = timingDay == .today ? model.caffeineTimingToday : model.caffeineTimingTomorrow
        let energy = timingDay == .today ? model.energyToday : model.energyTomorrow
        let groggy = energy.zone(.grogginess)?.range
        let start = min(420, ((groggy?.start ?? 420) / 60) * 60)
        return Day(label: label(timingDay), timing: timing, groggy: groggy, dip: energy.zone(.afternoonDip)?.range,
                   span: start...max(start + 360, 1440 + model.tonightBedtime + 60),
                   marker: timingDay == .today ? model.caffeineDoses.first?.time : timing.coffeeNapAt)
    }

    var body: some View {
        let d = day
        Screen(title: "Best time for caffeine", accent: .mint) {
            SampleDataBanner()
            timingCard(d)
            // With no window the readout already says it; no second box.
            if !d.noWindow {
                Card {
                    Text(title(d)).font(.bodyEmphasis)
                    Text(d.timing.note).font(.bodyText).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func title(_ d: Day) -> String {
        if d.timing.coffeeNapAt != nil { return "\(d.label): a coffee nap fits" }
        if timingDay == .today, let first = model.caffeineDoses.first?.time {
            return first >= d.timing.bestWindow.start ? "\(d.label): good timing" : "\(d.label): a little early"
        }
        return "\(d.label): best window \(d.timing.bestWindow.label)"
    }

    private func summary(_ d: Day) -> String {
        var parts: [String] = ["\(d.label):"]
        if let g = d.groggy { parts.append("grogginess \(g.label),") }
        if !d.noWindow { parts.append("best caffeine window \(d.timing.bestWindow.label),") }
        if let dip = d.dip { parts.append("afternoon dip \(dip.label),") }
        if let nap = d.timing.coffeeNapAt { parts.append("coffee nap at \(Clock.format(nap)),") }
        else if timingDay == .today, let first = model.caffeineDoses.first?.time { parts.append("first caffeine at \(Clock.format(first)),") }
        parts.append(d.noWindow ? "no safe time for a typical drink; one small drink early." : "cutoff \(Clock.format(d.timing.cutoff)).")
        return parts.joined(separator: " ")
    }

    /// What a moment on the timing bar means for caffeine (nil: the summary).
    private func readout(_ d: Day, at moment: Int?) -> (title: String, value: String, detail: String) {
        let timing = d.timing
        guard let raw = moment else {
            if d.noWindow {
                return (d.label, "Only a small coffee fits today", "Even right after you wake, a 12 oz drip coffee (140 mg) would leave more than \(bedtimeGoal) mg at bedtime. If you have one, keep it small and early.")
            }
            return (d.label, "Best window \(timing.bestWindow.label)",
                    "Caffeine works best once grogginess clears and before your \(Clock.format(timing.cutoff)) cutoff.")
        }
        let t = d.snap(raw)
        let title = Clock.format(t)
        if let nap = timing.coffeeNapAt, abs(t - nap) <= 10 {
            return (title, "Coffee nap", "A regular coffee, then a 20-minute nap. The caffeine kicks in just as you wake up.")
        }
        if let groggy = d.groggy, groggy.contains(t) {
            return (title, "Still groggy", "Caffeine works less well while you're waking up. Daylight and water help more. Wait until \(Clock.format(groggy.end)).")
        }
        if t >= timing.cutoff {
            let inDip = d.dip?.contains(t) == true ? " You're in your afternoon dip, so try daylight or a short break instead." : ""
            return (title, d.noWindow ? "Too late for a typical drink" : "After your cutoff",
                    "Caffeine now would still be in your body at bedtime, which can make sleep a little lighter.\(inDip)")
        }
        if let dip = d.dip, dip.contains(t) {
            return (title, "Afternoon dip", "Your natural energy low. Caffeine is still OK before your cutoff; daylight or a short break works too.")
        }
        if timing.bestWindow.contains(t) {
            return (title, "Good time for caffeine", "Grogginess has cleared and it's early enough to be mostly gone by bedtime.")
        }
        return (title, "Before you're up", "Your caffeine window starts at \(Clock.format(timing.bestWindow.start)).")
    }

    /// The audio graph's points for the timing strip: when you're groggy,
    /// the best window, the dip and the cutoff, in order.
    private static let pointLabels = ["Groggy until", "Best window starts", "Afternoon dip starts", "Cutoff"]
    private func points(_ d: Day) -> [(x: Int, y: Double)] {
        var out: [(x: Int, y: Double)] = []
        if let g = d.groggy { out.append((g.end, 0)) }
        if !d.noWindow { out.append((d.timing.bestWindow.start, 1)) }
        if let dip = d.dip { out.append((dip.start, 2)) }
        if !d.noWindow { out.append((d.timing.cutoff, 3)) }
        return out
    }

    private func timingCard(_ d: Day) -> some View {
        Card(accent: .mint) {
            HStack(spacing: 0) {
                Text("Timed to your energy").font(.bodyEmphasis).accessibilityAddTraits(.isHeader)
                Spacer()
                if d.timing.coffeeNapAt != nil {
                    Text("Coffee nap").font(.secondary).fontWeight(.semibold).secondaryText()
                }
                InfoButton(topic: .coffeeNap).padding(.vertical, -12)
            }
            AdaptiveSegmentedPicker("Day", selection: $timingDay, options: Array(TimingDay.allCases), accent: .mint) { day in label(day) }
            let r = readout(d, at: selectedTiming)
            // Every note the readout can show for this day, so it keeps one height.
            let slots = [readout(d, at: nil).detail]
                + stride(from: d.span.lowerBound, through: d.span.upperBound, by: 5).map { readout(d, at: $0).detail }
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .mint,
                         onClear: selectedTiming == nil ? nil : { selectedTiming = nil },
                         detailSlots: slots)
                .frame(maxWidth: .infinity, alignment: .leading)
                .motion(.dataSwap, value: timingDay)
            EnergyTimingChart(span: d.span, groggy: d.groggy, window: d.noWindow ? nil : d.timing.bestWindow,
                              dip: d.dip, cutoff: d.noWindow ? nil : d.timing.cutoff, marker: d.marker,
                              selected: selectedTiming.map(d.snap),
                              selection: $selectedTiming.snapping { d.snap($0) })
                .frame(height: 74)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary(d))
                .accessibilityChartDescriptor(ClockChartDescriptor(
                    title: "Caffeine timing and your energy", seriesName: "Times", yTitle: "Moment",
                    points: points(d), yLabel: { Self.pointLabels[min(max(Int($0.rounded()), 0), Self.pointLabels.count - 1)] }))
                .motion(.dataSwap, value: timingDay)
            ScrubHint(each: "hour")
            HStack(spacing: 12) {
                // The blocks carry their own labels; this spells them out.
                legend("Groggy: still waking up", color: Accent.indigo.fill(scheme).opacity(0.55))
                if !d.noWindow { legend("Best: best for caffeine", color: Accent.mint.fill(scheme).opacity(0.55)) }
                legend("Dip: afternoon dip", color: Accent.blue.fill(scheme).opacity(0.6))
            }
            .accessibilityHidden(true)
        }
    }

    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
        .font(.secondary)
        .secondaryText()
    }
}

// MARK: - Falloff chart

private struct CaffeinePoint: Identifiable {
    let time: Minutes
    let mg: Double
    var id: Minutes { time }
}

private struct CaffeineFalloffChart: View {
    let points: [CaffeinePoint]
    let start: Minutes
    let end: Minutes
    /// Nil when there's no cutoff time to show (it would come before she's up).
    let cutoff: Minutes?
    let bedtime: Minutes
    let now: Minutes
    let goal: Int
    let selected: CaffeinePoint?
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Every 4 hours, or every 8 (about three labels) at accessibility sizes.
    private var ticks: [Int] {
        let step = typeSize.isAccessibilitySize ? 480 : 240
        let first = ((start + step - 1) / step) * step
        return Array(stride(from: first, through: end, by: step))
    }

    private var nowLevel: Double? {
        guard now >= start, now <= end else { return nil }
        return points.min { abs($0.time - now) < abs($1.time - now) }?.mg
    }

    private var yMax: Double { max(points.map(\.mg).max() ?? 0, 100) * 1.15 }

    private var areaFill: LinearGradient {
        LinearGradient(colors: [Accent.yellow.fill(scheme).opacity(0.45), Accent.yellow.fill(scheme).opacity(0.02)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        // The goal, cutoff and bedtime are named in a legend under the
        // chart at every text size: on the plot, "25 mg" sat on the curve's
        // rise and "2pm cutoff" ran into "bed 12:30" (Weber C3).
        VStack(alignment: .leading, spacing: 8) {
            chart.frame(height: 180)
            legend
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(color: Accent.mint, dashed: true, text: "Goal at bedtime: \(goal) mg")
            if let cutoff, cutoff >= start {
                legendRow(color: Accent.orange, dashed: false, text: "Cutoff: \(BodyLogStyle.shortTime(cutoff))")
            }
            legendRow(color: Accent.purple, dashed: true, text: "Bedtime: \(Clock.format(bedtime))")
        }
        .accessibilityElement(children: .combine)
    }

    private func legendRow(color: Accent, dashed: Bool, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Capsule()
                .fill(color.fill(scheme))
                .frame(width: dashed ? 10 : 18, height: 3)
                .accessibilityHidden(true)
            Text(text).font(.secondary).fontWeight(.semibold).foregroundStyle(color.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.time), y: .value("Caffeine", p.mg))
                    .foregroundStyle(areaFill)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.time), y: .value("Caffeine", p.mg))
                    .foregroundStyle(Accent.yellow.fill(scheme))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            guides
            markers
        }
        // VoiceOver reads the chart's summary (chartScrub makes it one
        // element), so no mark-level hiding (Weber A8). A tick per half hour.
        .drawsIn()
        .chartScrub($selection, snapped: selected?.time, steps: points.map(\.time), feedbackKey: { $0 / 30 })
        .chartXScale(domain: start...end)
        // The last x label ran past the plot's edge (Weber C11).
        .chartXScale(range: .plotDimension(endPadding: 10))
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(BodyLogStyle.shortTime(m))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 100.0, 200.0, 300.0].filter { $0 <= yMax }) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let mg = value.as(Double.self) { Text("\(Int(mg))") }
                }
            }
        }
    }

    @ChartContentBuilder
    private var guides: some ChartContent {
        RuleMark(y: .value("Goal", Double(goal)))
            .foregroundStyle(Accent.mint.fill(scheme))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        if let cutoff, cutoff >= start {
            RuleMark(x: .value("Cutoff", cutoff))
                .foregroundStyle(Accent.orange.fill(scheme))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        RuleMark(x: .value("Bedtime", bedtime))
            .foregroundStyle(Accent.purple.fill(scheme))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    }

    @ChartContentBuilder
    private var markers: some ChartContent {
        if let selected {
            RuleMark(x: .value("Selected", selected.time))
                .foregroundStyle(Palette(scheme: scheme).secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
            PointMark(x: .value("Time", selected.time), y: .value("Caffeine", selected.mg))
                .foregroundStyle(Accent.yellow.ink(scheme))
                .symbolSize(70)
        } else if let level = nowLevel {
            PointMark(x: .value("Time", now), y: .value("Caffeine", level))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .symbolSize(40)
        }
    }
}

// MARK: - Energy timing chart

private struct TimingZone: Identifiable {
    let name: String
    let range: TimeRange
    let color: Color
    /// Drawn on the block itself, so the strip never relies on color alone.
    var short: String = ""
    var id: String { name }
}

/// The "Timed to your energy" bar, from the morning to an hour after bedtime.
private struct EnergyTimingChart: View {
    let span: ClosedRange<Minutes>
    let groggy: TimeRange?
    /// Nil when no window fits (the cutoff comes before grogginess clears).
    let window: TimeRange?
    let dip: TimeRange?
    let cutoff: Minutes?
    let marker: Minutes?
    let selected: Int?
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var scheme

    private var zones: [TimingZone] {
        var out: [TimingZone] = []
        if let groggy { out.append(TimingZone(name: "Grogginess", range: groggy, color: Accent.indigo.fill(scheme).opacity(0.5), short: "Groggy")) }
        if let window { out.append(TimingZone(name: "Best for caffeine", range: window, color: Accent.mint.fill(scheme).opacity(0.45), short: "Best")) }
        // The dip is normal, not a warning: blue, as on the energy curve.
        if let dip { out.append(TimingZone(name: "Afternoon dip", range: dip, color: Accent.blue.fill(scheme).opacity(0.6), short: "Dip")) }
        return out
    }

    /// Zones wide enough (two hours, about 45pt on the strip) to hold their
    /// own label without shrinking it (Weber C4).
    private func labelFits(_ zone: TimingZone) -> Bool {
        clamp(zone.range.end) - clamp(zone.range.start) >= 120
    }

    private func clamp(_ m: Minutes) -> Minutes { min(max(m, span.lowerBound), span.upperBound) }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// A tick every 5 hours from the start of the span (every 8 at
    /// accessibility text sizes, so the labels don't run together).
    private var ticks: [Int] {
        Array(stride(from: span.lowerBound, through: span.upperBound, by: typeSize.isAccessibilitySize ? 480 : 300))
    }

    var body: some View {
        Chart {
            RectangleMark(xStart: .value("Start", span.lowerBound), xEnd: .value("End", span.upperBound),
                          yStart: .value("Low", 0.0), yEnd: .value("High", 1.0))
                .foregroundStyle(Palette(scheme: scheme).chip)
            // No mark-level accessibilityHidden: chartScrub makes the chart
            // one VoiceOver element, and hiding marks risked dropping the
            // zone labels (Weber A8).
            ForEach(zones) { zone in
                RectangleMark(xStart: .value("Start", clamp(zone.range.start)), xEnd: .value("End", clamp(zone.range.end)),
                              yStart: .value("Low", 0.0), yEnd: .value("High", 1.0))
                    .foregroundStyle(zone.color)
                    .annotation(position: .overlay, alignment: .bottom) {
                        if labelFits(zone) {
                            Text(zone.short)
                                .font(.small).fontWeight(.bold)
                                .foregroundStyle(Palette(scheme: scheme).primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.bottom, 4)
                        }
                    }
            }
            cutoffRule
            dots
        }
        // A tick per half hour; the selection is already snapped to 5 minutes.
        .drawsIn()
        .chartScrub($selection, snapped: selected, feedbackKey: { $0 / 30 })
        .chartXScale(domain: span.lowerBound...span.upperBound)
        .chartYScale(domain: 0.0...1.0)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) { Text(BodyLogStyle.shortTime(m)) }
                }
            }
            AxisMarks(position: .top, values: cutoff.map { span.contains($0) ? [$0] : [] } ?? []) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text("\(BodyLogStyle.shortTime(m)) cutoff")
                            .font(.chartLabel(size: 11, weight: .semibold))
                            .foregroundStyle(Accent.yellow.ink(scheme))
                    }
                }
            }
        }
    }

    @ChartContentBuilder
    private var cutoffRule: some ChartContent {
        if let cutoff, span.contains(cutoff) {
            RuleMark(x: .value("Cutoff", cutoff))
                .foregroundStyle(Accent.yellow.fill(scheme))
                .lineStyle(StrokeStyle(lineWidth: 2))
            // Its label is a top-axis label (in the chart's own frame), not
            // an annotation that ran up into the readout (Weber C4).
        }
    }

    @ChartContentBuilder
    private var dots: some ChartContent {
        if let marker {
            PointMark(x: .value("Time", clamp(marker)), y: .value("Level", 0.5))
                .foregroundStyle(Accent.yellow.fill(scheme))
                .symbolSize(150)
        }
        if let selected {
            RuleMark(x: .value("Selected", selected))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .lineStyle(StrokeStyle(lineWidth: 2))
            PointMark(x: .value("Selected", selected), y: .value("Level", 0.5))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .symbolSize(60)
        }
    }
}
