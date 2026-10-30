import SwiftUI
import Charts
import HealthCore

/// Energy: today's day score first, then one chart (the curve, or energy
/// left), then the details one tap down: what moved the score, the day
/// zone by zone, what to do with it, and tomorrow's curve (the same screen
/// for the next day, pushed from a row, F3).
struct EnergyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Day: String, Identifiable {
        case today, tomorrow
        var id: String { rawValue }
    }

    /// Today, or the forecast for the next wake day.
    let day: Day

    init(day: Day = .today) { self.day = day }

    /// "Tomorrow" before midnight; after midnight the next day's name
    /// ("Wednesday").
    private var nextDayName: String {
        model.isAfterMidnight ? model.nextWakeDayName : "Tomorrow"
    }

    /// Her usual score (her own average once there are 7 days), else a typical one.
    private var usualScore: Int { model.energyUsual }

    @State private var selectedKind: EnergyDay.Zone.Kind? = nil
    /// Counts zone-row taps; each one clears the curve's selection.
    @State private var zoneTaps = 0
    @State private var zoneSheet: ZoneSheetItem? = nil
    @State private var showNoSleep = false

    // The chart selections live in their own panels (`EnergyCurvePanel`,
    // `EnergyBankPanel`), so dragging redraws only the chart card, never
    // this whole screen (Weber A2).

    var body: some View {
        let energy: EnergyDay = day == .today ? model.energyToday : model.energyTomorrow
        let zone: EnergyDay.Zone? = selectedZone(in: energy)
        Screen(title: day == .today ? "Energy" : "\(nextDayName)'s energy", accent: .mint) {
            SampleDataBanner()
            if !model.lastNightIsFresh && day == .today {
                CalloutBar(text: "No sleep recorded last night", systemImage: "moon.zzz.fill", accent: .purple) {
                    showNoSleep = true
                }
            }
            summary(energy)
            EnergyChartCard(energy: energy, isToday: day == .today, zone: zone,
                            chartNote: chartNote(energy), summary: chartSummary(energy),
                            resetKey: "\(day.rawValue)-\(zoneTaps)")
            RowCard { rows(energy, zone: zone) }
            Card(density: .compact) {
                LearnMoreRow("Learn more about energy", article: .energyThroughTheDay, accent: .mint)
            }
        }
        .bottomSheet(isPresented: $showNoSleep, title: "No sleep recorded") {
            Text("Today's curve uses your most recent recorded night, so treat it as a rough guide.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "How to get your sleep recorded", systemImage: "applewatch", accent: .purple) {
                AccuracyTipsView()
            }
        }
        .bottomSheet(item: $zoneSheet, title: { AppModel.zoneTitle($0.zone) }) { item in
            zoneDetail(item.zone)
        }
    }

    /// Today's score is below her usual: a row links to "Why is my energy
    /// low today?".
    private func isLow(_ e: EnergyDay) -> Bool { day == .today && e.score < usualScore - 2 }

    // MARK: Summary

    /// The day score, labelled as one so it isn't read as "now" (the chart's
    /// readout is now), with the day's one peak and its dip (F1, F2).
    private func summary(_ e: EnergyDay) -> some View {
        let peak = e.dayPeak
        return SummaryHeader(eyebrow: day == .today ? "Day score" : "Forecast day score",
                             value: "\(e.score)", unit: "of 100", status: status(e), line: line(e),
                             pairs: [StatPair(label: "Peak", value: "\(Clock.format(peak.time)) \u{00B7} \(Int(peak.level.rounded()))"),
                                     StatPair(label: "Dip", value: "\(Clock.format(e.lowest.time)) \u{00B7} \(Int(e.lowest.level.rounded()))")],
                             accent: .mint, info: info)
    }

    /// "Below your usual 74" (or "a typical 74" until she has 7 days) today;
    /// "Up 6 on today" when tomorrow looks better.
    private func status(_ e: EnergyDay) -> SummaryStatus? {
        switch day {
        case .today:
            let usual = model.energyUsualIsPersonal ? "your usual \(usualScore)" : "a typical \(usualScore)"
            // A low day is normal, not a warning: blue, not coral.
            if e.score < usualScore - 2 { return SummaryStatus(text: "Below \(usual)", accent: .blue) }
            if e.score > usualScore + 2 { return SummaryStatus(text: "Above \(usual)", accent: .mint) }
            return SummaryStatus(text: "Around \(usual)", accent: .indigo)
        case .tomorrow:
            let gain = e.score - model.energyToday.score
            return gain > 0 ? SummaryStatus(text: "Up \(gain) on today", accent: .mint) : nil
        }
    }

    /// The day score's ⓘ, starting with what the number in the badge is.
    private var info: Explanation {
        let topic = Topic.energyScore.explanation
        let usual = model.energyUsualIsPersonal
            ? "The \(usualScore) in the badge is your usual: your own average day score over recent days."
            : "The \(usualScore) in the badge is a typical day: until there are 7 days of your own, the app compares with this fixed middle-of-the-range value, not anyone's measured average."
        return Explanation(id: topic.id, title: topic.title, meaning: topic.meaning,
                           forYou: usual + " " + topic.forYou, howWeGotIt: topic.howWeGotIt)
    }

    /// One sentence: the main reason when it's low, then where she is in
    /// the day. Tomorrow: the plan the forecast assumes.
    private func line(_ e: EnergyDay) -> String {
        switch day {
        case .today:
            var parts: [String] = []
            let negatives = model.energyDrivers.filter { $0.points < 0 }
            if e.score < usualScore, let main = negatives.min(by: { $0.points < $1.points }) {
                parts.append("Mostly \(main.cause).")
            }
            let ordered = e.zones.sorted { $0.range.start < $1.range.start }
            if let current = ordered.first(where: { $0.range.contains(model.now) && $0.kind != .windDown }) {
                parts.append("You're in your \(phrase(current)) now.")
            } else if let next = ordered.first(where: { $0.range.start > model.now }) {
                parts.append("Next: your \(phrase(next)), around \(Clock.format(next.range.start)).")
            }
            return parts.isEmpty ? "Predicted from your sleep and your body clock." : parts.joined(separator: " ")
        case .tomorrow:
            let bed = Clock.format(1440 + model.tonightBedtime)
            guard let plan = model.wakePlan() else { return "If you sleep by \(bed), from tonight's planned bedtime." }
            return "If you sleep by \(bed): about \(Clock.duration(plan.asleep)) asleep, up at \(Clock.format(plan.wake))."
        }
    }

    // MARK: Curve

    /// The zone the curve's band highlights: the one she tapped, else the
    /// current or next useful one. Never the one under her finger:
    /// scrubbing the curve must not change anything outside its card
    /// (Weber A3).
    private func selectedZone(in e: EnergyDay) -> EnergyDay.Zone? {
        if let k = selectedKind, let z = e.zone(k) { return z }
        if day == .today {
            let daytime: [EnergyDay.Zone.Kind] = [.grogginess, .morningPeak, .afternoonDip, .secondWind]
            if let current = e.zones.first(where: { daytime.contains($0.kind) && $0.range.contains(model.now) }) {
                return current
            }
            return e.zone(.afternoonDip) ?? e.zones.first
        }
        return e.zone(.morningPeak) ?? e.zones.first
    }

    private func chartNote(_ e: EnergyDay) -> String {
        let wake = e.curve.first?.time ?? model.lastNight.wake
        if day == .today { return "woke \(Clock.format(wake))" }
        return "forecast, wake \(Clock.format(wake))"
    }

    private func chartSummary(_ e: EnergyDay) -> String {
        let zones = e.zones.map { "\(AppModel.zoneTitle($0)) \(timeLabel($0))" }.joined(separator: ", ")
        let prefix = day == .today ? "Today" : model.nextWakeDayName
        return "\(prefix): peak \(Int(e.dayPeak.level.rounded())) at \(Clock.format(e.dayPeak.time)), dip \(Int(e.lowest.level.rounded())) at \(Clock.format(e.lowest.time)); \(zones)."
    }

    private func timeLabel(_ z: EnergyDay.Zone) -> String {
        z.kind == .windDown ? "from \(Clock.format(z.range.start))" : z.range.label
    }

    /// The zone's name for sentences, from the model ("first peak" after a
    /// late wake, not "morning peak").
    private func phrase(_ zone: EnergyDay.Zone) -> String {
        AppModel.zoneTitle(zone).lowercased()
    }

    static func accent(for kind: EnergyDay.Zone.Kind) -> Accent {
        switch kind {
        case .grogginess: return .indigo
        case .morningPeak, .secondWind: return .mint
        // A dip is normal, not a warning: blue, not coral (Tanaka F1).
        case .afternoonDip: return .blue
        case .windDown, .melatonin: return .purple
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func rows(_ e: EnergyDay, zone: EnergyDay.Zone?) -> some View {
        let isToday = day == .today
        if isLow(e) {
            MetricRow(title: "Why is my energy low today?",
                      note: model.whyOffReasons.first.map { "Biggest reason: \($0.title.lowercased())" } ?? "See what's pulling it down",
                      systemImage: "questionmark.circle.fill", accent: .coral) { WhyOffView() }
            RowDivider()
        }
        if isToday && !model.energyDrivers.isEmpty {
            ExpandRow(title: "What moved today's score", summary: driversSummary,
                      systemImage: "arrow.up.arrow.down", accent: .mint) { driversList }
            RowDivider()
        }
        ExpandRow(title: "Your day, zone by zone", summary: zonesSummary(e),
                  systemImage: "clock.fill", accent: .mint) { zoneRows(e, zone: zone) }
        if isToday {
            // Tomorrow is a row down, not a second switch at the top (F3).
            let tomorrow = model.energyTomorrow
            let gain = tomorrow.score - e.score
            RowDivider()
            MetricRow(title: "\(nextDayName)'s curve",
                      note: "Forecast if you sleep by \(Clock.format(1440 + model.tonightBedtime))",
                      value: "\(tomorrow.score)",
                      verdict: gain > 0 ? RowVerdict(text: "Up \(gain)", accent: .mint) : nil,
                      systemImage: "chart.line.uptrend.xyaxis", accent: .mint) { EnergyView(day: .tomorrow) }
            // Does the score match how she felt? (H-E3)
            RowDivider()
            ExpandRow(title: "Does it match how you feel?", summary: model.scoreMatchSummary(model.energyMatch),
                      systemImage: "person.fill.questionmark", accent: .mint) {
                Text(model.scoreMatchDetail("energy score")).fixedSize(horizontal: false, vertical: true)
            }
            RowDivider()
            MetricRow(title: "Make the most of today",
                      note: model.hidesEffortTargets ? "Daylight, best nap and sleep debt" : "Daylight, best nap, sleep debt and effort",
                      systemImage: "sparkles", accent: .yellow) { EnergyTipsView(energy: e) }
            // Last week's energy, with streaks and badges inside it.
            RowDivider()
            MetricRow(title: "Your week",
                      note: model.weekRecap.map { "Average \($0.averageEnergy) \u{00B7} streaks and badges" } ?? "Streaks and badges",
                      systemImage: "chart.bar.fill", accent: .indigo) { WeekRecapView() }
        }
    }

    /// The driver that moved the score most, while the row is closed.
    private var driversSummary: String? {
        model.energyDrivers.max { abs($0.points) < abs($1.points) }.map { "\($0.name) \($0.deltaText)" }
    }

    /// What moved today's energy score: only the inputs the model uses.
    private var driversList: some View {
        ForEach(model.energyDrivers) { d in
            HStack {
                Text(d.name).font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(d.deltaText)
                    .font(.secondary).fontWeight(.bold)
                    .foregroundStyle((d.points >= 0 ? Accent.mint : Accent.coral).ink(scheme))
                    .frame(minWidth: 40)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background((d.points >= 0 ? Accent.mint : Accent.coral).tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "Now: Afternoon dip · 3:17–6:07pm", or the next zone.
    private func zonesSummary(_ e: EnergyDay) -> String {
        let ordered = e.zones.sorted { $0.range.start < $1.range.start }
        if day == .today {
            if let current = ordered.first(where: { $0.range.contains(model.now) }) {
                return "Now: \(AppModel.zoneTitle(current)) \u{00B7} \(timeLabel(current))"
            }
            if let next = ordered.first(where: { $0.range.start > model.now }) {
                return "Next: \(AppModel.zoneTitle(next)) \u{00B7} \(timeLabel(next))"
            }
        } else if let peak = e.zone(.morningPeak) {
            return "\(AppModel.zoneTitle(peak)) \u{00B7} \(timeLabel(peak))"
        }
        return "\(ordered.count) zones"
    }

    /// One line per zone: tap to highlight it on the curve and read what it
    /// means for her.
    @ViewBuilder
    private func zoneRows(_ e: EnergyDay, zone: EnergyDay.Zone?) -> some View {
        let p = Palette(scheme: scheme)
        ForEach(e.zones.sorted { $0.range.start < $1.range.start }, id: \.kind) { z in
            let accent = Self.accent(for: z.kind)
            let selected = z.kind == zone?.kind
            Button {
                selectedKind = z.kind
                zoneTaps += 1
                zoneSheet = ZoneSheetItem(zone: z)
            } label: {
                AdaptiveStack(spacing: Space.xs, alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Circle().fill(accent.fill(scheme)).frame(width: 10, height: 10)
                        Text(AppModel.zoneTitle(z)).font(.bodyEmphasis).foregroundStyle(p.primary)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: Space.s) }
                    Text(timeLabel(z)).font(.secondary).foregroundStyle(p.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: Sizes.minTap, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Highlights it on the curve and shows what it means")
        }
    }

    // MARK: Zone sheet

    private func zoneDetail(_ z: EnergyDay.Zone) -> some View {
        let accent = Self.accent(for: z.kind)
        let explanation = AppModel.zoneTopic(z.kind).explanation
        return VStack(alignment: .leading, spacing: Space.m) {
            Text(timeLabel(z)).font(.cardTitle)
            Text(explanation.meaning).font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.xs) {
                CapsLabel("For you", color: accent.ink(scheme))
                Text(tip(for: z)).font(.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .accessibilityElement(children: .combine)
            if let how = explanation.howWeGotIt {
                CapsLabel("How it's worked out")
                Text(how).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tip(for z: EnergyDay.Zone) -> String {
        let isToday = day == .today
        switch z.kind {
        case .grogginess:
            let length = Clock.duration(z.range.length)
            if isToday && model.lastNightIsFresh {
                let how = model.lastNight.wokeFromLight ? "at the end of a sleep cycle" : "partway through a sleep cycle"
                return "About \(length) this morning: you woke at \(Clock.format(z.range.start)), \(how). Skip hard decisions here and get outside light instead."
            }
            return "About \(length) if you wake at the end of a sleep cycle. Get daylight in the first half hour to clear it faster."
        case .morningPeak:
            return "Your sharpest stretch. Save it for problem sets, writing and anything that needs focus."
        case .afternoonDip:
            let pickMeUp = model.hidesEffortTargets ? "A few minutes of fresh air and daylight" : "A 10-minute walk outside"
            // On the pill (or with a very early bedtime) there's no clock time
            // for a typical drink: never print a cutoff before she's up.
            guard let cutoffTime = model.caffeineCutoffShown else {
                let early = model.caffeineNoCutoffShort.lowercased()
                if isToday && z.range.contains(model.now) {
                    return "You're in it now, so it's normal to feel flat. \(pickMeUp) helps more than coffee here. Caffeine today: \(early)."
                }
                return "Plan easy tasks here: email, errands, a break outside. A 20-minute nap at the start of the dip is fine. Coffee in the dip would still be in your body at bedtime; \(early) is the safer choice."
            }
            let cutoff = Clock.format(cutoffTime)
            guard isToday else {
                return "Plan easy tasks here: email, errands, a break outside. A 20-minute nap at the start of the dip is fine. Caffeine cutoff is \(cutoff)."
            }
            if z.range.contains(model.now) {
                let caffeine = model.now >= cutoffTime
                    ? "and your \(cutoff) caffeine cutoff has passed."
                    : "and if you do want caffeine, have it before your \(cutoff) cutoff."
                return "You're in it now, so it's normal to feel flat. \(pickMeUp) helps more than another coffee, \(caffeine)"
            }
            if model.now < z.range.start {
                return "Plan easy tasks here: email, errands, a break outside. Any coffee should come before your \(cutoff) caffeine cutoff so it's cleared by bedtime."
            }
            return "Behind you now; it's why mid-afternoon felt slow. Your caffeine cutoff was \(cutoff), so skip coffee from here."
        case .secondWind:
            let wrapUp = ((z.range.end + 59) / 60) * 60
            if model.hidesEffortTargets {
                return "A good window for group study or seeing friends. Wrap up anything intense by \(Clock.format(wrapUp))."
            }
            var text = "A good window for a workout or group study. Wrap up anything intense by \(Clock.format(wrapUp))."
            if store.data.upBy <= 7 * 60 {
                text += " Training in the morning instead? Give yourself until your grogginess clears and warm up a little longer."
            }
            return text
        case .windDown:
            return "About 2 hours before you usually fall asleep, your body's own sleep hormone starts rising. Dim the lights and put screens down from around \(Clock.format(z.range.start))."
        case .melatonin:
            let bed = 1440 + model.tonightBedtime
            if z.range.contains(bed) {
                return "This is about your own body's sleep hormone, not pills. Your bedtime of \(Clock.format(bed)) lands inside it, so falling asleep should come easily."
            }
            return "This is about your own body's sleep hormone, not pills. Your bedtime of \(Clock.format(bed)) falls outside it, which can make it harder to fall asleep. It's an estimate from your usual sleep times."
        }
    }
}

/// A zone whose sheet is open.
private struct ZoneSheetItem: Identifiable {
    var zone: EnergyDay.Zone
    var id: EnergyDay.Zone.Kind { zone.kind }
}

// MARK: - Make the most of today

/// What to do with today's energy: daylight, the best nap, sleep debt and
/// (unless effort targets are hidden) how hard to train. Pushed from Energy.
private struct EnergyTipsView: View {
    var energy: EnergyDay
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: DataStore

    @Environment(\.colorScheme) private var scheme

    /// After midnight this is the app day's daylight (yesterday's), not 0.
    private var daylightNote: String {
        guard let daylight = model.daylightThisAppDay else {
            return "Your Watch counts time in daylight. 10 to 20 minutes outside, ideally before noon, helps you feel awake and keeps your body clock steady."
        }
        if daylight >= 30 { return "From your Watch. That's enough to keep your body clock steady." }
        return "From your Watch. 10 to 20 minutes outside, ideally before noon, helps you feel awake and keeps your body clock steady."
    }

    var body: some View {
        let daylightTitle = model.daylightThisAppDay.map { "Daylight: \($0) min today" } ?? "Daylight: no reading yet"
        let debt = model.sleepDebt
        Screen(title: "Make the most of today", accent: .mint) {
            Card {
                EnergyTipRow(systemImage: "sun.max.fill", accent: .yellow,
                             title: daylightTitle, detail: daylightNote, topic: .daylight)
                if let dipStart = energy.zone(.afternoonDip)?.range.start {
                    EnergyTipRow(systemImage: "bed.double.fill", accent: .purple,
                                 title: "Best nap: \(TimeRange(dipStart, dipStart + 20).label)",
                                 detail: "Early in the dip, 20 minutes max. Later or longer pushes your bedtime back.", topic: nil)
                }
            }
            RowCard {
                MetricRow(title: "Sleep debt",
                          // One line; the debt's detail is on the page it opens.
                          note: debt >= 60 ? "Flattens your peaks" : "Peaks at full strength",
                          value: debt > 0 ? Clock.duration(debt) : nil,
                          verdict: debt > 0 ? nil : RowVerdict(text: "None", accent: .mint),
                          systemImage: "moon.zzz.fill", accent: .purple) { SleepNeedView() }
                if !model.hidesEffortTargets {
                    let effort = effortSuggestion
                    RowDivider()
                    ExpandRow(title: "Effort target", summary: effort.value, systemImage: "figure.walk", accent: .orange) {
                        Text(Topic.effort.explanation.meaning)
                        Text(effort.note).foregroundStyle(Palette(scheme: scheme).primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// From today's shown recovery against her usual (or a typical value).
    /// Only shown when effort targets aren't hidden.
    private var effortSuggestion: (value: String, note: String) {
        let usual = model.recoveryUsualPhrase
        let steps = "\(model.stepsToday.formatted(.number)) steps so far."
        // The sick check comes before recovery: training hard while your
        // body may be fighting something isn't worth it (round 4, Ruiz F3).
        if model.sickCheckFlagged || !model.loggedSickSymptoms.isEmpty {
            let why = model.sickCheckFlagged ? "Your sick check found \(model.sickSignsPhrase)." : "You logged feeling sick today."
            return (Recovery.Level.easy.effort, "\(why) Skip hard training until you feel better; a gentle walk is fine if you feel up to it.")
        }
        guard model.hasHeartData, let recovery = model.recoveryShown else {
            return ("As planned", "No recovery reading yet, so no change suggested. \(steps)")
        }
        let example = model.recoveryIsExample ? " (an example number for now)" : ""
        let morning = store.data.upBy <= 7 * 60 ? " Training early? Warm up a little longer." : ""
        // The same band, and so the same name, as the recovery label.
        let level = model.recoveryLevel(for: recovery)
        let label = level.label
        switch level {
        case .push:
            return (level.effort, "Recovery \(recovery)\(example), \(label.lowercased()): above \(usual). A good day for a hard workout.\(morning) \(steps)")
        case .onTrack:
            return (level.effort, "Recovery \(recovery)\(example), \(label.lowercased()): about \(usual). Train as planned.\(morning) \(steps)")
        case .steady:
            return (level.effort, "Recovery \(recovery)\(example), \(label.lowercased()): a bit below \(usual). Keep hard sessions moderate today.\(morning) \(steps)")
        case .easy:
            return (level.effort, "Recovery \(recovery)\(example), \(label.lowercased()): well below \(usual). Keep training light today. \(steps)")
        }
    }
}

// MARK: - Chart card

/// The one chart on Energy: the score curve, or energy left (today only),
/// picked with a segmented switch. Each panel owns its selection, so a
/// drag redraws only this card (Weber A2).
private struct EnergyChartCard: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case score, left
        var id: String { rawValue }
    }

    var energy: EnergyDay
    var isToday: Bool
    /// The zone the curve highlights while nothing is selected.
    var zone: EnergyDay.Zone?
    var chartNote: String
    var summary: String
    /// Changing it (another day, a zone row tapped) clears the selection.
    var resetKey: String
    @State private var mode: Mode = .score

    var body: some View {
        // Energy left is only worked out for today.
        let shown: Mode = isToday ? mode : .score
        Card {
            if isToday {
                AdaptiveSegmentedPicker("Chart", selection: $mode, options: Mode.allCases, accent: .mint) {
                    $0 == .score ? "Score" : "Energy left"
                }
            }
            // The new chart fades in and traces its line (D-M4), rather
            // than snapping.
            Group {
                switch shown {
                case .score:
                    EnergyCurvePanel(energy: energy, isToday: isToday, zone: zone, chartNote: chartNote,
                                     summary: summary, resetKey: resetKey)
                        .transition(.opacity)
                case .left:
                    EnergyBankPanel()
                        .transition(.opacity)
                }
            }
            .motion(.dataSwap, value: shown)
        }
    }
}

/// "Peaks and dips": the readout and the energy curve. The selection is the
/// snapped point, written only when it changes.
private struct EnergyCurvePanel: View {
    var energy: EnergyDay
    var isToday: Bool
    var zone: EnergyDay.Zone?
    var chartNote: String
    var summary: String
    var resetKey: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    /// The selected curve point's time (snapped), or nil.
    @State private var selection: Int? = nil

    /// The time the readout describes: the finger, else now (today) or the peak.
    private var readoutTime: (time: Minutes, isNow: Bool) {
        if let selection { return (selection, false) }
        let start = energy.curve.first?.time ?? 0
        let end = energy.curve.last?.time ?? 0
        if isToday, model.now >= start, model.now <= end { return (model.now, true) }
        return (energy.dayPeak.time, false)
    }

    var body: some View {
        let e = energy
        let (t, isNow) = readoutTime
        let moment = model.energyMoment(at: t, in: e)
        let accent: Accent = moment.kind.map(EnergyView.accent(for:)) ?? .mint
        let lead = isNow ? "Now, \(Clock.format(model.now))" : Clock.format(moment.time)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Peaks and dips").font(.cardTitle)
                InfoButton(title: "Your energy curve",
                           meaning: "A prediction of how alert you'll feel at each time of day, from 0 (running on empty) to 100 (fully switched on). It comes from when and how long you slept and your body clock.",
                           forYou: "Plan hard work for the high parts and easy things for the low parts. Drag along the curve to see what each moment means.")
                    .padding(.vertical, -12)
                Spacer()
                Text(chartNote).font(.secondary).secondaryText()
            }
            // "58 · 3 below today's peak": the level big, the comparison
            // beside it (Dubois 5, Hale F8). One line, so it never changes
            // height while you drag; what the moment means is the row under
            // the chart (F3).
            ChartReadout(title: "\(lead) · \(moment.title)", value: "\(moment.level) · \(e.relativeCue(level: Double(moment.level)))",
                         accent: accent, onClear: selection == nil ? nil : { selection = nil })
            // The band shows the highlighted zone only while nothing is
            // selected: a band following the finger jumped across the
            // chart and changed colour at every zone edge (Weber A5).
            EnergyCurveChart(energy: e,
                             band: selection == nil ? zone : nil,
                             bandColor: zone.map { EnergyView.accent(for: $0.kind).fill(scheme) } ?? .clear,
                             now: isToday ? model.now : nil,
                             selected: selection,
                             selection: $selection.snapping { AppModel.nearestPoint($0, in: e)?.time },
                             summary: summary)
                .frame(height: 175)
                .motion(.dataSwap, value: isToday)
            ScrubHint(each: "moment")
            // Edge to edge at the foot of the card, like a row in a RowCard.
            VStack(spacing: 0) {
                RowDivider(hasIcon: false)
                ExpandRow(title: "What this moment means", accent: accent) {
                    Text(moment.note).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, -Space.l)
            .padding(.bottom, -Space.l)
        }
        .onChange(of: resetKey) { selection = nil }
    }
}

/// "Energy left": the readout and the bank chart, with its own selection
/// (snapped to 5 minutes).
private struct EnergyBankPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: DataStore
    /// The selected time, in minutes, snapped to 5.
    @State private var selection: Int? = nil

    var body: some View {
        let wake = model.lastNight.wake
        let bedtime = 1440 + model.tonightBedtime
        let atWake = Int(model.energyBankAtWake.rounded())
        let now = Int(model.energyBankNow.rounded())
        let bed = Int(model.energyBankAtBedtime.rounded())
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Energy left").font(.cardTitle)
                InfoButton(topic: .energyBank).padding(.vertical, -12)
                Spacer()
                Text("charges asleep, drains awake").font(.secondary).secondaryText()
            }
            readout(now: now, atWake: atWake, bed: bed, bedtime: bedtime)
            EnergyBankChart(wake: wake, atWake: model.energyBankAtWake,
                            now: model.now, atNow: model.energyBankNow,
                            bedtime: bedtime, atBedtime: model.energyBankAtBedtime,
                            selected: selection, selectedLevel: selection.map { model.energyBank(at: $0) },
                            selection: $selection.snapping { raw in
                                min(max(Int((Double(raw) / 5).rounded()) * 5, wake), bedtime)
                            },
                            summary: "Energy left: charged to \(atWake)% overnight, \(now)% at \(Clock.format(model.now)), projected \(bed)% at \(Clock.format(bedtime))")
                .frame(height: 150)
            ScrubHint(each: "moment")
        }
    }

    private static let wakeNote = "What last night's sleep charged you to."
    private static let lowNote = "Projected. Running low here; keep plans light and protect your bedtime."
    private static let aheadNote = "Projected, if your day goes as usual. Stress and hard exercise drain it faster."
    private static let earlierNote = "Earlier today."

    private func readout(now: Int, atWake: Int, bed: Int, bedtime: Minutes) -> some View {
        let nowNote = "You woke with \(atWake)%. About \(bed)% by bedtime at \(Clock.format(bedtime))."
        let slots = [nowNote, Self.wakeNote, Self.lowNote, Self.aheadNote, Self.earlierNote]
        guard let t = selection else {
            return ChartReadout(title: "Now, \(Clock.format(model.now)) \u{00B7} left", value: "\(now)%",
                                detail: nowNote, accent: .mint, detailSlots: slots)
        }
        let level = Int(model.energyBank(at: t).rounded())
        let detail: String
        if t <= model.lastNight.wake + 10 {
            detail = Self.wakeNote
        } else if t > model.now {
            detail = level < 25 ? Self.lowNote : Self.aheadNote
        } else {
            detail = Self.earlierNote
        }
        return ChartReadout(title: Clock.format(t), value: "\(level)%", detail: detail, accent: .mint,
                            onClear: { selection = nil }, detailSlots: slots)
    }
}

private struct EnergyCurveChart: View {
    var energy: EnergyDay
    var band: EnergyDay.Zone?
    var bandColor: Color
    var now: Minutes?
    /// Snapped selection (a curve point's time).
    var selected: Minutes?
    @Binding var selection: Int?
    var summary: String
    @Environment(\.colorScheme) private var scheme

    @Environment(\.dynamicTypeSize) private var typeSize
    private var lineColor: Color { Accent.mint.fill(scheme) }
    private var area: LinearGradient {
        LinearGradient(colors: [lineColor.opacity(0.35), lineColor.opacity(0.02)], startPoint: .top, endPoint: .bottom)
    }
    private var start: Int { energy.curve.first?.time ?? 420 }
    private var end: Int { max(energy.curve.last?.time ?? 1560, start + 60) }
    /// Every 3 hours, or every 6 (about three labels) at accessibility sizes.
    private var ticks: [Int] {
        let step = typeSize.isAccessibilitySize ? 360 : 180
        let first = ((start + step - 1) / step) * step
        return Array(stride(from: first, through: end, by: step))
    }
    /// Past the end of the curve (well after bedtime) the marker stays at the
    /// end. Always drawn, dimmed while a point is selected, so it never pops
    /// out on the first touch and back in on clear (Weber A4).
    private var nowPoint: (time: Minutes, level: Double)? {
        guard let now, now >= start else { return nil }
        let t = min(now, end)
        guard let level = energy.level(at: t) ?? energy.curve.last.map({ $0.level }) else { return nil }
        return (t, level)
    }
    private var nowIsPastEnd: Bool { (now ?? 0) > end }
    private var selectedPoint: EnergyDay.Point? {
        guard let selected else { return nil }
        return energy.curve.first { $0.time == selected }
    }

    var body: some View {
        // No mark-level accessibilityHidden: `chartScrub` already makes the
        // chart one VoiceOver element, and hiding marks risked dropping
        // their annotations (Weber A8).
        Chart {
            bandMark
            curveMarks
            extremeMarks
            nowMarks
            selectionMarks
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: -8.0...112.0)
        // A 0 / 50 / 100 scale, so a curve that peaks at 61 doesn't read as
        // a full tank (Tanaka F12).
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)").font(.chartLabel(size: 10)).foregroundStyle(Palette(scheme: scheme).tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(Self.hourLabel(m)).font(.chartLabel(size: 11)).foregroundStyle(Palette(scheme: scheme).tertiary)
                    }
                }
            }
        }
        // A tick per half hour, not per 10-minute point (Weber A6).
        .drawsIn()
        .chartScrub($selection, snapped: selected, steps: energy.curve.map(\.time), feedbackKey: { $0 / 30 })
        // Scrubbing moves the marks with the finger, never animated, so a
        // mark can't lag a frame behind the readout.
        .transaction(value: selected) { $0.animation = nil }
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(ClockChartDescriptor(
            title: "Energy through the day", seriesName: "Energy", yTitle: "Energy, 0 to 100",
            points: energy.curve.map { ($0.time, $0.level) },
            yLabel: { "\(Int($0.rounded())) of 100" }))
    }

    @ChartContentBuilder private var bandMark: some ChartContent {
        if let band {
            RectangleMark(xStart: .value("From", band.range.start), xEnd: .value("To", band.range.end),
                          yStart: .value("Bottom", 0.0), yEnd: .value("Top", 100.0))
                .foregroundStyle(bandColor.opacity(0.22))
        }
    }

    @ChartContentBuilder private var curveMarks: some ChartContent {
        ForEach(energy.curve, id: \.time) { p in
            AreaMark(x: .value("Time", p.time), y: .value("Energy", p.level))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(area)
        }
        ForEach(energy.curve, id: \.time) { p in
            LineMark(x: .value("Time", p.time), y: .value("Energy", p.level))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    /// Dots only: the "Peak 64 · 12:57pm" and "Dip" labels sat on the Now
    /// label and the x axis, and the summary's Peak and Dip already say
    /// both (Weber C1). The peak is the day's one peak (F2).
    @ChartContentBuilder private var extremeMarks: some ChartContent {
        PointMark(x: .value("Time", energy.dayPeak.time), y: .value("Energy", energy.dayPeak.level))
            .symbolSize(40)
            .foregroundStyle(Accent.mint.ink(scheme))
        PointMark(x: .value("Time", energy.lowest.time), y: .value("Energy", energy.lowest.level))
            .symbolSize(40)
            .foregroundStyle(Accent.blue.ink(scheme))
    }

    @ChartContentBuilder private var nowMarks: some ChartContent {
        if let p = nowPoint {
            let dim = selected == nil ? 1.0 : 0.35
            RuleMark(x: .value("Now", p.time))
                .foregroundStyle(Palette(scheme: scheme).tertiary.opacity(dim))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("Now", p.time), y: .value("Energy", p.level))
                .symbolSize(110)
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(dim))
                .annotation(position: .top, spacing: 4,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    Text(nowIsPastEnd ? "Now: past bedtime" : "Now").font(.chartLabel(size: 11, weight: .bold))
                        .foregroundStyle(Palette(scheme: scheme).primary)
                        .opacity(dim)
                }
        }
    }

    @ChartContentBuilder private var selectionMarks: some ChartContent {
        if let p = selectedPoint {
            RuleMark(x: .value("Selected", p.time))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            PointMark(x: .value("Selected", p.time), y: .value("Energy", p.level))
                .symbolSize(160)
                .foregroundStyle(Palette(scheme: scheme).primary)
        }
    }

    /// "9am", "12pm"
    static func hourLabel(_ m: Int) -> String {
        let h = ((m / 60) % 24 + 24) % 24
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12)\(h < 12 ? "am" : "pm")"
    }
}

private struct BankPoint: Identifiable {
    let id: Int
    let time: Int
    let level: Double
    let part: String
}

private struct EnergyBankChart: View {
    var wake: Minutes
    var atWake: Double
    var now: Minutes
    var atNow: Double
    var bedtime: Minutes
    var atBedtime: Double
    var selected: Minutes?
    var selectedLevel: Double?
    @Binding var selection: Int?
    var summary: String
    @Environment(\.colorScheme) private var scheme

    private var clampedNow: Int { min(max(now, wake), bedtime) }
    private var points: [BankPoint] {
        [
            BankPoint(id: 0, time: wake, level: atWake, part: "So far"),
            BankPoint(id: 1, time: clampedNow, level: atNow, part: "So far"),
            BankPoint(id: 2, time: clampedNow, level: atNow, part: "Ahead"),
            BankPoint(id: 3, time: bedtime, level: atBedtime, part: "Ahead"),
        ]
    }

    /// Wake and bedtime, plus now when it's at least 2.5 hours from both:
    /// closer, its label printed over its neighbour's (Weber C2). The Now
    /// dot's own label says where now is.
    private var ticks: [Int] {
        let nowFits = clampedNow - wake > 150 && bedtime - clampedNow > 150
        return [wake, bedtime] + (nowFits ? [clampedNow] : [])
    }

    var body: some View {
        Chart {
            lineMarks
            markers
        }
        .chartXScale(domain: wake...max(bedtime, wake + 60))
        // Room for the end dot, which was half cut off at the right edge.
        .chartXScale(range: .plotDimension(endPadding: 6))
        .chartYScale(domain: 0.0...100.0)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(Clock.format(m)).font(.chartLabel(size: 11)).foregroundStyle(Palette(scheme: scheme).tertiary)
                    }
                }
            }
        }
        .drawsIn()
        .chartScrub($selection, snapped: selected, feedbackKey: { $0 / 30 })
        .transaction(value: selected) { $0.animation = nil }
        .accessibilityLabel(summary)
        .accessibilityChartDescriptor(ClockChartDescriptor(
            title: "Energy left through the day", seriesName: "Energy left", yTitle: "Energy left, percent",
            points: [(wake, atWake), (clampedNow, atNow), (bedtime, atBedtime)],
            yLabel: { "\(Int($0.rounded()))%" }))
    }

    @ChartContentBuilder private var lineMarks: some ChartContent {
        ForEach(points) { p in
            LineMark(x: .value("Time", p.time), y: .value("Bank", p.level), series: .value("Part", p.part))
                .foregroundStyle(Accent.mint.fill(scheme))
                .lineStyle(p.part == "Ahead"
                           ? StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 5])
                           : StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    /// The Now dot is always drawn (dimmed while a time is selected); the
    /// selection marks are added on top (Weber A4).
    @ChartContentBuilder private var markers: some ChartContent {
        let dim = selected == nil ? 1.0 : 0.35
        PointMark(x: .value("Time", clampedNow), y: .value("Bank", atNow))
            .symbolSize(70)
            .foregroundStyle(Palette(scheme: scheme).primary.opacity(dim))
            .annotation(position: .top, spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                Text("Now").font(.chartLabel(size: 11, weight: .bold)).opacity(dim)
            }
        if let selected, let selectedLevel {
            RuleMark(x: .value("Selected", selected))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.6))
            PointMark(x: .value("Selected", selected), y: .value("Bank", selectedLevel))
                .symbolSize(120)
                .foregroundStyle(Palette(scheme: scheme).primary)
        }
    }
}

/// A non-navigating row with an icon tile, title, detail and optional ⓘ.
private struct EnergyTipRow: View {
    var systemImage: String
    var accent: Accent
    var title: String
    var detail: String
    var topic: Topic?
    @Environment(\.colorScheme) private var scheme

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
                    if let topic { InfoButton(topic: topic).padding(.vertical, -12) }
                }
                Text(detail).font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
