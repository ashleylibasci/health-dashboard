import SwiftUI
import Charts
import HealthCore

/// Energy: today's (or tomorrow's) predicted alertness curve, its peaks and
/// dips, the energy bank, and what to do with them. Drag along the curve to
/// see what each moment means.
struct EnergyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// At the largest text sizes the Today/Tomorrow switch moves out of the
    /// navigation bar into the screen, where it has room.
    private var pickerInContent: Bool { typeSize >= .xxxLarge }

    private enum Day: String, CaseIterable, Identifiable {
        case today, tomorrow
        var id: String { rawValue }
    }

    /// "Tomorrow" before midnight; after midnight the next day's name.
    private var nextDayLabel: String { model.isAfterMidnight ? model.nextWakeDayName : "Tomorrow" }
    private func label(_ d: Day) -> String { d == .today ? "Today" : nextDayLabel }
    /// "tomorrow", or "on Wednesday" after midnight.
    private var nextDayPhrase: String { model.isAfterMidnight ? "on \(model.nextWakeDayName)" : "tomorrow" }

    /// Her usual score (her own average once there are 7 days), else a typical one.
    private var usualScore: Int { model.energyUsual }
    /// "your usual 74" or "the starting point of 74".
    private var usualPhrase: String { model.energyUsualPhrase }

    @State private var day: Day = .today
    @State private var selectedKind: EnergyDay.Zone.Kind? = nil
    /// Raw finger position on the energy curve (minutes); snapped in code.
    @State private var curveSelection: Int? = nil
    /// Raw finger position on the energy bank chart (minutes).
    @State private var bankSelection: Int? = nil

    var body: some View {
        let energy: EnergyDay = day == .today ? model.energyToday : model.energyTomorrow
        let zone: EnergyDay.Zone? = selectedZone(in: energy)
        Screen(title: "Energy", accent: .mint) {
            SampleDataBanner()
            if pickerInContent {
                dayPicker
            }
            if !model.lastNightIsFresh && day == .today {
                Card(accent: .purple) {
                    Text("No sleep recorded last night").font(.scaled(size: 16, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Today's curve uses your most recent recorded night, so treat it as a rough guide.")
                        .font(.scaled(size: 13)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                    LinkRow(title: "How to get your sleep recorded", systemImage: "applewatch", accent: .purple) {
                        AccuracyTipsView()
                    }
                }
            }
            scoreCard(energy)
            curveCard(energy, zone: zone)
            zonesCard(energy, zone: zone)
            extremes(energy)
            if day == .today { bankCard }
            debtAndEffort
            makeTheMostCard(energy)
            notifyCard
            footer
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !pickerInContent {
                    dayPicker
                        .frame(width: min(max(170, Font.scaledSize(170)), 230))
                }
            }
        }
        .onChange(of: day) {
            selectedKind = nil
            curveSelection = nil
        }
    }

    private var dayPicker: some View {
        AdaptiveSegmentedPicker("Day", selection: $day, options: Array(Day.allCases), accent: .yellow) { d in label(d) }
    }

    /// Today's score is below her usual: the score card links to "Why is my
    /// energy low today?", so the tips card doesn't repeat it.
    private func isLow(_ e: EnergyDay) -> Bool { day == .today && e.score < usualScore - 2 }

    // MARK: Score

    private func scoreCard(_ e: EnergyDay) -> some View {
        let ringLabel: String = day == .today
            ? "Energy score today \(e.score) out of 100, \(usualPhrase)"
            : "\(nextDayLabel) forecast \(e.score) out of 100"
        let low = isLow(e)
        return Card(accent: .mint) {
            HStack(spacing: 0) {
                SectionLabel(text: day == .today ? "Energy score" : "Energy score forecast", accent: .mint)
                InfoButton(topic: .energyScore).padding(.vertical, -12)
            }
            HStack(spacing: 18) {
                Ring(value: Double(e.score) / 100, accent: .mint, label: "\(e.score)",
                     caption: day == .today ? "Today" : "Forecast", size: 120, accessibilityText: ringLabel)
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline(e)).font(.scaled(size: 20, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subhead(e)).font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("0 to 100: how alert your body is predicted to feel across your waking hours. " + (model.energyUsualIsPersonal ? "Your usual is \(usualScore)." : "The app starts from \(usualScore), a fixed starting point; your own usual shows after 7 days."))
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            HowWeGotThisLink(topic: .energyScore)
            if day == .today && !model.energyDrivers.isEmpty {
                driversList
            }
            if low {
                LinkRow(title: "Why is my energy low today?",
                        subtitle: model.whyOffReasons.first.map { "Biggest reason: \($0.title.lowercased())." } ?? "See what's pulling it down.",
                        systemImage: "questionmark.circle.fill", accent: .coral) { WhyOffView() }
            }
        }
    }

    private func headline(_ e: EnergyDay) -> String {
        switch day {
        case .today:
            if e.score < usualScore - 2 { return "Below \(usualPhrase)" }
            if e.score > usualScore + 2 { return "Above \(usualPhrase)" }
            return "Right around \(usualPhrase)"
        case .tomorrow:
            let bed = Clock.format(1440 + store.data.bedtime)
            return e.score > model.energyToday.score
                ? "Better \(nextDayPhrase), if you sleep by \(bed)"
                : "\(nextDayLabel), if you sleep by \(bed)"
        }
    }

    private func subhead(_ e: EnergyDay) -> String {
        switch day {
        case .today:
            var parts: [String] = []
            let negatives = model.energyDrivers.filter { $0.points < 0 }
            if e.score < usualScore, let main = negatives.min(by: { $0.points < $1.points }) {
                parts.append("Mostly \(main.cause).")
            }
            let now = model.now
            let ordered = e.zones.sorted { $0.range.start < $1.range.start }
            let current = ordered.first { $0.range.contains(now) && $0.kind != .windDown }
            let next = ordered.first { $0.range.start > now }
            if let current, let next {
                parts.append("You're in your \(phrase(current)) now; your \(phrase(next)) starts around \(Clock.format(next.range.start)).")
            } else if let current {
                parts.append("You're in your \(phrase(current)) now.")
            } else if let next {
                parts.append("Next up: your \(phrase(next)), around \(Clock.format(next.range.start)).")
            }
            return parts.joined(separator: " ")
        case .tomorrow:
            guard let plan = model.wakePlan() else {
                return "Forecast from tonight's planned bedtime."
            }
            let gain = e.score - model.energyToday.score
            if gain > 0 {
                return "Waking at the end of a sleep cycle and \(plan.cycles) full cycles tonight add \(gain) \(gain == 1 ? "point" : "points")."
            }
            return "Forecast from tonight's plan: \(plan.cycles) full sleep cycles, up at \(Clock.format(plan.wake))."
        }
    }

    // MARK: Curve

    /// The time the readout describes: the finger, else now (today) or the peak.
    private func readoutTime(_ e: EnergyDay) -> (time: Minutes, isNow: Bool) {
        if let raw = curveSelection, let p = AppModel.nearestPoint(raw, in: e) { return (p.time, false) }
        let start = e.curve.first?.time ?? 0
        let end = e.curve.last?.time ?? 0
        if day == .today, model.now >= start, model.now <= end { return (model.now, true) }
        return (e.highest.time, false)
    }

    private func curveCard(_ e: EnergyDay, zone: EnergyDay.Zone?) -> some View {
        let (t, isNow) = readoutTime(e)
        let moment = model.energyMoment(at: t, in: e)
        let accent: Accent = moment.kind.map(Self.accent(for:)) ?? .mint
        let lead = isNow ? "Now, \(Clock.format(model.now))" : Clock.format(moment.time)
        let action = moment.kind.map { model.zoneActionShown($0) } ?? moment.action
        let selected: Minutes? = curveSelection.flatMap { AppModel.nearestPoint($0, in: e)?.time }
        return Card {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Peaks and dips").font(.scaled(size: 17, weight: .bold))
                InfoButton(title: "Your energy curve",
                           meaning: "A prediction of how alert you'll feel at each time of day, from 0 (running on empty) to 100 (fully switched on). It comes from when and how long you slept and your body clock.",
                           forYou: "Plan hard work for the high parts and easy things for the low parts. Drag along the curve to see what each moment means.")
                    .padding(.vertical, -12)
                Spacer()
                Text(chartNote(e)).font(.scaled(size: 13)).secondaryText()
            }
            ChartReadout(title: "\(lead) · \(moment.title)", value: "Energy level \(moment.level) · \(e.relativeCue(level: Double(moment.level)))",
                         detail: "\(moment.meaning) \(action)", accent: accent)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            EnergyCurveChart(energy: e,
                             band: zone,
                             bandColor: zone.map { Self.accent(for: $0.kind).fill(scheme) } ?? .clear,
                             now: day == .today ? model.now : nil,
                             selected: selected,
                             selection: $curveSelection,
                             summary: chartSummary(e))
                .frame(height: 190)
            ScrubHint(text: "Drag the dot along the curve to see each moment")
        }
    }

    private func selectedZone(in e: EnergyDay) -> EnergyDay.Zone? {
        if let k = selectedKind, let z = e.zone(k) { return z }
        if let raw = curveSelection, let p = AppModel.nearestPoint(raw, in: e) {
            return AppModel.zone(at: p.time, in: e)
        }
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
        let prefix = day == .today ? "Today" : nextDayLabel
        return "\(prefix): peak \(Int(e.highest.level.rounded())) at \(Clock.format(e.highest.time)), low \(Int(e.lowest.level.rounded())) at \(Clock.format(e.lowest.time)). \(zones)."
    }

    private func timeLabel(_ z: EnergyDay.Zone) -> String {
        z.kind == .windDown ? "from \(Clock.format(z.range.start))" : z.range.label
    }

    /// The zone's name for sentences, from the model ("first peak" after a
    /// late wake, not "morning peak").
    private func phrase(_ zone: EnergyDay.Zone) -> String {
        AppModel.zoneTitle(zone).lowercased()
    }

    /// What moved today's energy score: only the inputs the model uses.
    private var driversList: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "What moved today's score")
            ForEach(model.energyDrivers) { d in
                HStack {
                    Text(d.name).font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(d.deltaText)
                        .font(.scaled(size: 13, weight: .bold))
                        .foregroundStyle((d.points >= 0 ? Accent.mint : Accent.coral).ink(scheme))
                        .frame(minWidth: 40)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background((d.points >= 0 ? Accent.mint : Accent.coral).tint(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
    }

    static func accent(for kind: EnergyDay.Zone.Kind) -> Accent {
        switch kind {
        case .grogginess: return .indigo
        case .morningPeak, .secondWind: return .mint
        case .afternoonDip: return .coral
        case .windDown, .melatonin: return .purple
        }
    }

    // MARK: Zones

    private func zonesCard(_ e: EnergyDay, zone: EnergyDay.Zone?) -> some View {
        let ordered = e.zones.sorted { $0.range.start < $1.range.start }
        return Card {
            Text("Your day, zone by zone").font(.scaled(size: 17, weight: .bold))
            Text("Tap a zone to highlight it on the curve. Tap ⓘ for more.")
                .font(.scaled(size: 13)).secondaryText()
            VStack(spacing: 6) {
                ForEach(ordered, id: \.kind) { z in
                    EnergyZoneRow(title: AppModel.zoneTitle(z), time: timeLabel(z),
                                  oneLiner: model.zoneOneLinerShown(z.kind), accent: Self.accent(for: z.kind),
                                  topic: AppModel.zoneTopic(z.kind), selected: z.kind == zone?.kind) {
                        selectedKind = z.kind
                        curveSelection = nil
                    }
                }
            }
            if let zone {
                let accent = Self.accent(for: zone.kind)
                VStack(alignment: .leading, spacing: 4) {
                    Text("For you: \(AppModel.zoneTitle(zone)) · \(timeLabel(zone))").font(.scaled(size: 15, weight: .bold))
                    Text(tip(for: zone)).font(.scaled(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.fill(scheme).opacity(0.3)))
                .accessibilityElement(children: .combine)
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
            return "Dim the lights and put screens down from \(Clock.format(z.range.start)). Your body temperature starts to drop here."
        case .melatonin:
            let bed = 1440 + store.data.bedtime
            if z.range.contains(bed) {
                return "This is about your own body's sleep hormone, not pills. Your bedtime of \(Clock.format(bed)) lands inside it, so falling asleep should come easily."
            }
            return "This is about your own body's sleep hormone, not pills. Your bedtime of \(Clock.format(bed)) misses it, which can make it harder to fall asleep; aim for about \(Clock.format(z.range.start + 30))."
        }
    }

    // MARK: Highest / lowest

    private func extremes(_ e: EnergyDay) -> some View {
        let high = Int(e.highest.level.rounded())
        let low = Int(e.lowest.level.rounded())
        let highNote: String
        let lowNote: String
        if day == .today {
            let nearNoon = abs(e.highest.time - 720) <= 30
            highNote = nearNoon ? "Peak at \(high), right around noon. Best time for hard work." : "Peak at \(high). Best time for hard work."
            let now = model.now
            if abs(e.lowest.time - now) <= 20 {
                lowNote = "Right now, at \(low). Normal for this time; go easy."
            } else if e.lowest.time > now {
                lowNote = "Still ahead, at about \(low). Normal; plan easy tasks."
            } else {
                lowNote = "Earlier today, at \(low)."
            }
        } else {
            highNote = "Forecast peak at \(high). Block it for studying."
            lowNote = "Forecast low at \(low). Keep it for easy tasks."
        }
        return HStack(spacing: 12) {
            EnergyExtremeTile(eyebrow: "Highest", value: Clock.format(e.highest.time), note: highNote, accent: .mint)
            EnergyExtremeTile(eyebrow: "Lowest", value: Clock.format(e.lowest.time), note: lowNote, accent: .coral)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Energy bank

    private var bankCard: some View {
        let wake = model.lastNight.wake
        let bedtime = 1440 + store.data.bedtime
        let atWake = Int(model.energyBankAtWake.rounded())
        let now = Int(model.energyBankNow.rounded())
        let bed = Int(model.energyBankAtBedtime.rounded())
        let selected: Minutes? = bankSelection.map { min(max($0, wake), bedtime) }
        return Card {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Energy left").font(.scaled(size: 17, weight: .bold))
                InfoButton(topic: .energyBank).padding(.vertical, -12)
                Spacer()
                Text("charges asleep, drains awake").font(.scaled(size: 13)).secondaryText()
            }
            Text("Like a phone battery for your body: sleep charges it, being awake drains it. A different number from your energy score.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            bankReadout(selected: selected, now: now, atWake: atWake, bed: bed, bedtime: bedtime)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            EnergyBankChart(wake: wake, atWake: model.energyBankAtWake,
                            now: model.now, atNow: model.energyBankNow,
                            bedtime: bedtime, atBedtime: model.energyBankAtBedtime,
                            selected: selected, selectedLevel: selected.map { model.energyBank(at: $0) },
                            selection: $bankSelection,
                            summary: "Energy left: charged to \(atWake)% overnight, \(now)% at \(Clock.format(model.now)), projected \(bed)% at \(Clock.format(bedtime))")
                .frame(height: 110)
            ScrubHint()
        }
    }

    private func bankReadout(selected: Minutes?, now: Int, atWake: Int, bed: Int, bedtime: Minutes) -> some View {
        guard let t = selected else {
            return ChartReadout(title: "Now, \(Clock.format(model.now))", value: "\(now)% left",
                                detail: "You woke with \(atWake)%. About \(bed)% by bedtime at \(Clock.format(bedtime)).", accent: .mint)
        }
        let level = Int(model.energyBank(at: t).rounded())
        let ahead = t > model.now
        let detail: String
        if t <= model.lastNight.wake + 10 {
            detail = "What last night's sleep charged you to."
        } else if ahead {
            detail = level < 25
                ? "Projected. Running low here; keep plans light and protect your bedtime."
                : "Projected, if your day goes as usual. Stress and hard exercise drain it faster."
        } else {
            detail = "Earlier today."
        }
        return ChartReadout(title: Clock.format(t), value: "\(level)%", detail: detail, accent: .mint)
    }

    // MARK: Sleep debt + effort

    private var debtAndEffort: some View {
        let debt = model.sleepDebt
        let debtNote = debt >= 60
            ? "Missed sleep over 14 nights. Peaks feel flatter until it's under 1 hour."
            : "Under an hour over 14 nights. Your peaks are at full strength."
        return HStack(alignment: .top, spacing: 12) {
            EnergyInfoTile(title: "Sleep debt", topic: .sleepDebt, value: debt > 0 ? Clock.duration(debt) : "None", note: debtNote,
                           accent: .purple, systemImage: "moon.zzz.fill")
            if !model.hidesEffortTargets {
                let effort = effortSuggestion
                EnergyInfoTile(title: "Effort target", topic: .effort, value: effort.value, note: effort.note,
                               accent: .orange, systemImage: "figure.walk")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Make the most of it

    private func makeTheMostCard(_ e: EnergyDay) -> some View {
        // After midnight this is the app day's daylight (yesterday's), not 0.
        let daylight = model.daylightThisAppDay
        let daylightTitle = daylight.map { "Daylight: \($0) min today" } ?? "Daylight: no reading yet"
        let daylightNote: String
        if let daylight, daylight >= 30 {
            daylightNote = "From your Watch. That's enough to keep your body clock steady."
        } else if daylight == nil {
            daylightNote = "Your Watch counts time in daylight. 10 to 20 minutes outside, ideally before noon, helps you feel awake and keeps your body clock steady."
        } else {
            daylightNote = "From your Watch. 10 to 20 minutes outside, ideally before noon, helps you feel awake and keeps your body clock steady."
        }
        let showWhyLow = !isLow(e)
        let dipStart = e.zone(.afternoonDip)?.range.start
        let tomorrowPeak = model.energyTomorrow.zone(.morningPeak)?.range
        let peakTime = e.highest.time
        let peakWord = abs(peakTime - 720) <= 30 ? "noon" : Clock.format(peakTime)
        let typeText = model.chronotype.map { "You're a \($0.category.rawValue.lowercased())." } ?? "It follows your body clock."
        let recapNote: String
        if let recap = model.weekRecap {
            recapNote = "Your best day was \(recap.best.date.formatted(.dateTime.weekday(.wide))). Here's what it had in common with your other good days."
        } else {
            recapNote = "Builds after a full week of tracking."
        }
        let lateCount = model.lateNights.count
        let threshold = Clock.format(model.lateBedtimeThreshold)
        let lateNote = lateCount > 0
            ? "\(lateCount) \(lateCount == 1 ? "night" : "nights") in bed after \(threshold). See what they cost you."
            : "What a night in bed after \(threshold) does to the next two days."
        return Card {
            Text("Make the most of it").font(.scaled(size: 17, weight: .bold))
            EnergyTipRow(systemImage: "sun.max.fill", accent: .yellow,
                         title: daylightTitle, detail: daylightNote, topic: .daylight)
            if let dipStart {
                EnergyTipRow(systemImage: "bed.double.fill", accent: .purple,
                             title: "Best nap: \(TimeRange(dipStart, dipStart + 20).label)",
                             detail: "Early in the dip, 20 minutes max. Later or longer pushes your bedtime back.", topic: nil)
            }
            if showWhyLow {
                LinkRow(title: "Why do I feel off?", subtitle: "Your likeliest reasons, and what to try.",
                        systemImage: "questionmark.circle.fill", accent: .coral) { WhyOffView() }
            }
            LinkRow(title: "The cost of a late night", subtitle: lateNote,
                    systemImage: "moon.haze.fill", accent: .purple) { LateNightView() }
            LinkRow(title: "Study in your peaks",
                    subtitle: tomorrowPeak.map { "\(nextDayLabel) \($0.label) is your sharpest stretch. Block it for review." }
                        ?? "Plan focused work into your morning peak.",
                    systemImage: "book.fill", accent: .mint) { ExamWeekView() }
            LinkRow(title: "Shorter grogginess \(nextDayPhrase)",
                    subtitle: "Waking at the end of a sleep cycle cuts it to about 40 minutes. See your best wake time.",
                    systemImage: "sunrise.fill", accent: .orange) { WakePlanView() }
            LinkRow(title: "Why your peak is at \(peakWord)",
                    subtitle: "\(typeText) See your body clock.",
                    systemImage: "clock.fill", accent: .mint) { ChronotypeView() }
            LinkRow(title: "Last week's energy recap", subtitle: recapNote,
                    systemImage: "chart.bar.fill", accent: .indigo) { WeekRecapView() }
            LinkRow(title: "Streaks and wins", subtitle: "Your streaks and the badges you've earned.",
                    systemImage: "star.fill", accent: .yellow) { AchievementsView() }
        }
    }

    // MARK: Notifications + footer

    private var notifyCard: some View {
        Card {
            Toggle(isOn: $store.data.peakDipNudges) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heads-up before peaks and dips").font(.scaled(size: 15, weight: .bold))
                    Text("A notification 15 minutes before your first peak and your dip. Uses last night's sleep from your Watch, so it starts once a night is recorded.")
                        .font(.scaled(size: 13)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Accent.mint.fill(scheme))
            .frame(minHeight: 44)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.canCheckInNow && !model.checkInDoneToday {
                NavigationLink { CheckInView() } label: {
                    Text("Check in for today: it makes your curve more accurate")
                        .font(.scaled(size: 13, weight: .bold))
                        .foregroundStyle(Accent.mint.ink(scheme))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Subviews

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
    /// Past the end of the curve (well after bedtime) the marker stays at the end.
    private var nowPoint: (time: Minutes, level: Double)? {
        guard selected == nil, let now, now >= start else { return nil }
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
        Chart {
            bandMark.accessibilityHidden(true)
            curveMarks.accessibilityHidden(true)
            extremeMarks.accessibilityHidden(true)
            nowMarks.accessibilityHidden(true)
            selectionMarks.accessibilityHidden(true)
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: -8.0...112.0)
        .chartYAxis(.hidden)
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
        .chartScrub($selection)
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

    @ChartContentBuilder private var extremeMarks: some ChartContent {
        PointMark(x: .value("Time", energy.highest.time), y: .value("Energy", energy.highest.level))
            .symbolSize(40)
            .foregroundStyle(Accent.mint.ink(scheme))
            .annotation(position: .top, spacing: 2) {
                Text("Peak \(Clock.format(energy.highest.time))")
                    .font(.chartLabel(size: 10, weight: .bold))
                    .foregroundStyle(Accent.mint.ink(scheme))
            }
        PointMark(x: .value("Time", energy.lowest.time), y: .value("Energy", energy.lowest.level))
            .symbolSize(40)
            .foregroundStyle(Accent.coral.ink(scheme))
            .annotation(position: .bottom, spacing: 2) {
                Text("Dip \(Clock.format(energy.lowest.time))")
                    .font(.chartLabel(size: 10, weight: .bold))
                    .foregroundStyle(Accent.coral.ink(scheme))
            }
    }

    @ChartContentBuilder private var nowMarks: some ChartContent {
        if let p = nowPoint {
            RuleMark(x: .value("Now", p.time))
                .foregroundStyle(Palette(scheme: scheme).tertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("Now", p.time), y: .value("Energy", p.level))
                .symbolSize(110)
                .foregroundStyle(Palette(scheme: scheme).primary)
                .annotation(position: .top, spacing: 4) {
                    Text(nowIsPastEnd ? "Now: past bedtime" : "Now").font(.chartLabel(size: 11, weight: .bold))
                        .foregroundStyle(Palette(scheme: scheme).primary)
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

    var body: some View {
        Chart {
            lineMarks.accessibilityHidden(true)
            markers.accessibilityHidden(true)
        }
        .chartXScale(domain: wake...max(bedtime, wake + 60))
        .chartYScale(domain: 0.0...100.0)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: [wake, clampedNow, bedtime]) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(Clock.format(m)).font(.chartLabel(size: 11)).foregroundStyle(Palette(scheme: scheme).tertiary)
                    }
                }
            }
        }
        .chartScrub($selection)
        .accessibilityLabel(summary)
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

    @ChartContentBuilder private var markers: some ChartContent {
        if let selected, let selectedLevel {
            RuleMark(x: .value("Selected", selected))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.6))
            PointMark(x: .value("Selected", selected), y: .value("Bank", selectedLevel))
                .symbolSize(120)
                .foregroundStyle(Palette(scheme: scheme).primary)
        } else {
            PointMark(x: .value("Time", clampedNow), y: .value("Bank", atNow))
                .symbolSize(70)
                .foregroundStyle(Palette(scheme: scheme).primary)
                .annotation(position: .top, spacing: 4) {
                    Text("Now").font(.chartLabel(size: 11, weight: .bold))
                }
        }
    }
}

/// One zone: colored dot, name and time, a plain one-liner, and an ⓘ.
private struct EnergyZoneRow: View {
    var title: String
    var time: String
    var oneLiner: String
    var accent: Accent
    var topic: Topic
    var selected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        HStack(alignment: .top, spacing: 0) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(accent.fill(scheme)).frame(width: 10, height: 10).padding(.top, 5)
                    (Text("\(title) \(time)").font(.scaled(size: 14, weight: .bold))
                     + Text(" — \(oneLiner)").font(.scaled(size: 14)).foregroundStyle(p.secondary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Highlights it on the curve")
            InfoButton(topic: topic)
        }
        .padding(.leading, 10)
        .padding(.vertical, 2)
        .background(selected ? accent.tint(scheme) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? accent.fill(scheme).opacity(0.5) : Color.clear))
    }
}

private struct EnergyExtremeTile: View {
    var eyebrow: String
    var value: String
    var note: String
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: eyebrow, accent: accent)
            Text(value).font(.scaledNumber(26)).minimumScaleFactor(0.6).lineLimit(1)
            Text(note).font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A metric tile whose title carries an ⓘ.
private struct EnergyInfoTile: View {
    var title: String
    var topic: Topic
    var value: String
    var note: String
    var accent: Accent
    var systemImage: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(title).font(.scaled(size: 14, weight: .bold))
                InfoButton(topic: topic).padding(.vertical, -12)
                Spacer(minLength: 0)
                Image(systemName: systemImage).foregroundStyle(accent.ink(scheme)).accessibilityHidden(true)
            }
            Text(value).font(.scaledNumber(24)).minimumScaleFactor(0.6).lineLimit(1)
            Text(note).font(.scaled(size: 12, weight: .semibold)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                .font(.scaled(size: 16, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 36, height: 36)
                .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(title).font(.scaled(size: 15, weight: .bold))
                    if let topic { InfoButton(topic: topic).padding(.vertical, -12) }
                }
                Text(detail).font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
