import SwiftUI
import Charts
import HealthCore

/// Caffeine today: total, what's left at bedtime, the cutoff, logging drinks
/// at the time you had them, today's drinks (editable), the caffeine in your
/// body through the day, and timing against your energy.
struct CaffeineView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var timingDay: TimingDay = .today
    @State private var logTime: LogTime = .now
    @State private var toast: UndoToast?
    @State private var editing: AppData.LoggedDrink?
    @State private var selectedTime: Int?
    @State private var selectedTiming: Int?
    @State private var logCount = 0

    /// The ring is a gauge against this, not a goal to fill.
    private let dailyLimit = CaffeineModel.dailyGuideMg
    private let bedtimeGoal = 25

    enum TimingDay: String, CaseIterable, Identifiable {
        case today = "Today", tomorrow = "Tomorrow"
        var id: String { rawValue }
    }

    /// After midnight (before the app day rolls over) "tomorrow" is the
    /// morning she's about to wake up to.
    private func label(_ day: TimingDay) -> String {
        switch day {
        case .today: return model.isAfterMidnight ? "Since you woke" : "Today"
        case .tomorrow: return model.nextWakeDayLabel
        }
    }

    var body: some View {
        Screen(title: "Caffeine", accent: .yellow) {
            SampleDataBanner()
            hero
            logCard
            todayCard
            falloffCard
            timingCard
            Card {
                LinkRow(title: "Find your caffeine limit", subtitle: cutoffSubtitle,
                        systemImage: "flask.fill", accent: .mint) {
                    CutoffTestView()
                }
                Divider().overlay(Palette(scheme: scheme).cardBorder)
                LinkRow(title: "Exam week plan", subtitle: "Caffeine and sleep timed around your exams",
                        systemImage: "calendar", accent: .indigo) {
                    ExamWeekView()
                }
            }
        }
        .sheet(item: $editing) { entry in
            editor(entry)
        }
        .undoToast($toast)
        .sensoryFeedback(.increase, trigger: logCount)
    }

    private var cutoffSubtitle: String {
        let test = model.cutoffTest
        return "How late caffeine works for your sleep \u{00B7} \(min(test.nightsLogged, test.target)) of \(test.target) nights"
    }

    private func log(_ drink: Drink) {
        let chosen = logTime
        let id = UUID()
        withMotion(.log) {
            model.logDrink(id: id, drinkID: drink.id, name: drink.name, mg: drink.caffeineMg, at: chosen.date, saveToHealth: true)
        }
        let when = store.data.drinkLog.first { $0.id == id }?.date ?? .now
        toast = UndoToast(LogFormat.loggedLine(LogFormat.midSentence(drink), time: chosen, at: when)) {
            withMotion(.undo) { model.deleteDrink(id) }
        }
        logTime = .now
        logCount += 1
    }

    // MARK: Hero

    private var lastDrinkName: String {
        model.todaysDrinks.last?.name ?? "Last caffeine"
    }

    private var hero: some View {
        Card {
            AdaptiveStack(spacing: 16) {
                Ring(value: Double(model.caffeineMgToday) / Double(dailyLimit), accent: .yellow,
                     label: "\(model.caffeineMgToday)", caption: "mg today", size: 146)
                VStack(alignment: .leading, spacing: 8) {
                    if let last = model.caffeineDoses.last {
                        heroStat(label: lastDrinkName, value: Clock.format(last.time), accent: .yellow)
                    } else {
                        heroStat(label: "No caffeine yet", value: "\u{2014}", accent: .yellow)
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        heroStat(label: "Cutoff", value: model.caffeineCutoffShown.map { Clock.format($0) } ?? "Before you\u{2019}re up", accent: .orange)
                        InfoButton(topic: .caffeineCutoff).padding(.bottom, -10)
                    }
                    HStack(spacing: 0) {
                        Text("Up to \(dailyLimit) mg a day is generally fine")
                            .font(.secondary).fontWeight(.semibold)
                            .secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                        InfoButton(title: "How much caffeine a day",
                                   meaning: "Up to \(dailyLimit) mg a day is generally fine for healthy adults; under \(CaffeineModel.lowerGuideMg) mg if you could be pregnant or are trying. About \(CaffeineModel.lowerGuideMg) mg in one go is the most that's generally fine at once.",
                                   forYou: "It's a ceiling, not a target: less is fine, and none is fine too. Some people feel shaky, anxious or get a racing heart on much less. The ring shows how close today is to \(dailyLimit) mg.")
                            .padding(.vertical, -12)
                    }
                }
                Spacer(minLength: 0)
            }
            ForEach(dailyNotes, id: \.self) { note in
                Label(note, systemImage: "info.circle.fill")
                    .font(.secondary).fontWeight(.semibold)
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Gentle notes, no alarm: over 400 mg today, and a single drink over
    /// 200 mg (a big single dose).
    private var dailyNotes: [String] {
        var notes: [String] = []
        let total = model.caffeineMgToday
        if total > dailyLimit {
            notes.append("That\u{2019}s \(total) mg today, more than the \(dailyLimit) mg that\u{2019}s generally fine. Water or decaf for the rest of the day is easier on your heart and sleep. Feeling shaky or a racing heart? Stop there.")
        }
        if let big = model.todaysDrinks.last(where: { $0.mg > CaffeineModel.lowerGuideMg }) {
            notes.append("Your \(big.name) was \(big.mg) mg in one go: a big single dose. Over \(CaffeineModel.lowerGuideMg) mg at once is more likely to make you jittery; a smaller size or splitting it up helps.")
        }
        return notes
    }

    private func heroStat(label: String, value: String, accent: Accent) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.secondary).fontWeight(.bold)
                .foregroundStyle(accent.ink(scheme))
                .lineLimit(1)
            Text(value).font(.numberM)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Log a drink

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Log caffeine").font(.cardTitle).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Logs \(logTime.phrase)").font(.secondary).fontWeight(.semibold).secondaryText()
            }
            .padding(.top, 4)
            Card {
                LogTimeSelector(time: $logTime, accent: .yellow, title: "When did you have it?")
            }
            ForEach(Array(store.data.savedDrinks.enumerated()), id: \.element.id) { index, drink in
                Button { log(drink) } label: {
                    SavedDrinkRow(drink: drink, featured: index == 0)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(logLabel(for: drink))
                .contextMenu {
                    Button(role: .destructive) {
                        store.data.savedDrinks.removeAll { $0.id == drink.id }
                        model.pushToWatch()
                    } label: {
                        Label("Remove from My caffeine drinks", systemImage: "trash")
                    }
                }
            }
            if let usual = store.data.savedDrinks.first { doseNote(usual) }
            commonDrinks
            NavigationLink { CustomDrinkView() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.bodyEmphasis).accessibilityHidden(true)
                    Text("New caffeine drink").font(.bodyEmphasis)
                }
                .foregroundStyle(Accent.yellow.ink(scheme))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Accent.yellow.fill(scheme).opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
                    .strokeBorder(Accent.yellow.fill(scheme).opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
    }

    /// Dose-aware: whether this drink, at the chosen time, on top of today's,
    /// would leave too much at bedtime, and the latest time it still fits.
    private func doseNote(_ drink: Drink) -> some View {
        let t = model.appDayMinutes(AppDay.pastTime(logTime.date))
        let tooMuch = model.wouldBeTooMuchAtBedtime(mg: drink.caffeineMg, at: t)
        let text: String
        let when = logTime == .now ? "now" : logTime.phrase
        let bed = Clock.format(model.bedtimeTonight)
        let left = model.caffeineAtBedtime(adding: drink.caffeineMg, at: t)
        // "A latte now", lower case mid-sentence; her own drinks as she named them.
        let name = LogFormat.midSentence(drink)
        let a = drink.isCustom ? "Your" : ("aeiou".contains(name.prefix(1)) ? "An" : "A")
        // The total at bedtime, with today's other drinks: say so, or "a
        // 130 mg latte would leave 140 mg" reads as wrong (round 3).
        let withOthers = model.caffeineDoses.isEmpty ? "" : ", counting what you\u{2019}ve had"
        if !tooMuch {
            text = "\(a) \(name) (\(drink.caffeineMg) mg) \(when) is fine: under 25 mg left by your \(bed) bedtime."
        } else if let latest = model.latestTimeForCaffeine(mg: drink.caffeineMg), latest > t {
            text = "\(a) \(name) \(when) would leave about \(left) mg at bedtime\(withOthers). Have it by \(Clock.format(latest)) instead."
        } else {
            let room = CaffeineModel.largestDose(at: max(t, model.now), bedtime: model.bedtimeTonight, existing: model.caffeineDoses,
                                                 halfLifeHours: model.caffeineHalfLifeHours)
            let smaller = room >= 5 ? " A smaller drink still fits: up to about \(room) mg now." : ""
            text = "\(a) \(name) \(when) would leave about \(left) mg at bedtime\(withOthers). Skip more caffeine today." + smaller
                + (model.caffeineLastsLonger ? " On your birth control caffeine stays \(model.caffeineLongerPhrase)." : "")
        }
        return Label(text, systemImage: tooMuch ? "exclamationmark.triangle.fill" : "checkmark.circle")
            .font(.secondary).fontWeight(.semibold)
            .foregroundStyle((tooMuch ? Accent.orange : Accent.mint).ink(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func logLabel(for drink: Drink) -> String {
        var parts = ["Log \(drink.name)"]
        if let size = drink.sizeLabel { parts.append(size) }
        parts.append("\(drink.caffeineMg) mg")
        if drink.isCustom { parts.append("custom drink") }
        parts.append(logTime.phrase)
        return parts.joined(separator: ", ")
    }

    /// Common drinks she hasn't saved yet, as one-tap chips.
    private var unsavedCommon: [Drink] {
        let saved = Set(store.data.savedDrinks.map(\.name))
        return Drink.common.filter { !saved.contains($0.name) }
    }

    @ViewBuilder
    private var commonDrinks: some View {
        if !unsavedCommon.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Common drinks")
                // Wraps instead of scrolling sideways, so none is cut off
                // at large text sizes (round 3, A8).
                FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(unsavedCommon) { drink in
                            Button { log(drink) } label: {
                                Text("\(drink.name) \u{00B7} \(drink.caffeineMg) mg")
                                    .font(.secondary).fontWeight(.bold)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(Accent.yellow.fill(scheme).opacity(0.14), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Accent.yellow.fill(scheme).opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Log \(drink.name), \(drink.caffeineMg) mg, \(logTime.phrase)")
                        }
                }
                Text("Typical amounts. Coffee-shop coffee is stronger than home brewed, and energy drinks and pre-workouts vary a lot (150 to 300 mg), so check your label. For a different amount, use New caffeine drink.")
                    .font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Today's drinks

    private func symbol(for entry: AppData.LoggedDrink) -> String {
        let all = store.data.savedDrinks + Drink.common
        if let drink = all.first(where: { $0.id == entry.drinkID }) ?? all.first(where: { $0.name == entry.name }) {
            return BodyLogStyle.symbol(for: drink.icon)
        }
        return "cup.and.saucer.fill"
    }

    private var todayCard: some View {
        Card {
            HStack {
                Text("Today's caffeine").font(.cardTitle).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(model.caffeineMgToday) mg").font(.bodyEmphasis).foregroundStyle(Accent.yellow.ink(scheme))
            }
            if model.todaysDrinks.isEmpty {
                Text("Nothing logged yet today.")
                    .font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LogEntryList(items: model.todaysDrinks.reversed(), onTap: { editing = $0 },
                             onDelete: { model.deleteDrink($0.id) }) { entry in
                    LogEntryRow(systemImage: symbol(for: entry), accent: .yellow, title: entry.name,
                                detail: "\(entry.mg) mg", time: Clock.format(Clock.minutesOfDay(entry.date)))
                }
                Text("Tap an entry to change its time or caffeine. Swipe left to delete.")
                    .font(.secondary).secondaryText()
            }
        }
    }

    private func editor(_ entry: AppData.LoggedDrink) -> some View {
        LogEditSheet(title: entry.name, accent: .yellow, date: entry.date, amount: Double(entry.mg), unit: "mg",
                     step: 5, range: 0...600,
                     onSave: { date, mg in model.updateDrink(entry.id, date: date, mg: Int(mg.rounded())) },
                     onDelete: { model.deleteDrink(entry.id) })
            .environmentObject(model)
            .environmentObject(store)
    }

    // MARK: Caffeine in your body

    private var bedtime: Minutes { 1440 + store.data.bedtime }

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

    /// The curve point nearest the finger.
    private var selectedPoint: CaffeinePoint? {
        guard let t = selectedTime else { return nil }
        return curve.min { abs($0.time - t) < abs($1.time - t) }
    }

    private var bedtimeOK: Bool { model.caffeineAtBedtime < bedtimeGoal }

    private var falloffReadout: (title: String, value: String, detail: String) {
        guard let p = selectedPoint else {
            let mg = model.caffeineInBody(at: model.now)
            return ("Now \u{00B7} \(Clock.format(model.now))", "\(Int(mg.rounded())) mg \u{00B7} in your body", AppModel.caffeineMeaning(mg: mg))
        }
        var title = Clock.format(p.time)
        var detail = AppModel.caffeineMeaning(mg: p.mg)
        if abs(p.time - bedtime) <= 10 {
            title += " \u{00B7} your bedtime"
            detail += p.mg < Double(bedtimeGoal) ? " Under the 25 mg goal, so it shouldn't get in the way of deep sleep." : " Over 25 mg at bedtime makes sleep lighter, even if you fall asleep fine."
        } else if let cutoff = model.caffeineCutoffShown, abs(p.time - cutoff) <= 10 {
            title += " \u{00B7} your cutoff"
            detail += " Caffeine after this is still in you at bedtime."
        } else if p.time > model.now {
            detail += " Predicted, if you have no more caffeine."
        }
        return (title, "\(Int(p.mg.rounded())) mg \u{00B7} in your body", detail)
    }

    private var falloffCard: some View {
        Card(accent: .yellow) {
            Text("Caffeine in your body").font(.bodyEmphasis)
            let r = falloffReadout
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .yellow,
                         onClear: selectedTime == nil ? nil : { selectedTime = nil })
            CaffeineFalloffChart(points: curve, start: chartStart, end: chartEnd, cutoff: model.caffeineCutoffShown,
                                 bedtime: bedtime, now: model.now, goal: bedtimeGoal,
                                 selected: selectedPoint, selection: $selectedTime)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartSummary)
                .accessibilityChartDescriptor(ClockChartDescriptor(
                    title: "Caffeine in your body", seriesName: "Caffeine", yTitle: "Milligrams",
                    points: curve.map { ($0.time, $0.mg) },
                    yLabel: { "\(Int($0.rounded())) mg" }))
            ScrubHint(each: "hour")
            HStack(spacing: 0) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(Accent.yellow.tint(scheme), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    // "about", not "~", which VoiceOver reads as "tilde" (Ortiz F8).
                    Text("At bedtime \u{00B7} about \(model.caffeineAtBedtime) mg").font(.bodyEmphasis)
                    Text(bedtimeNote).font(.secondary).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 12)
                Spacer(minLength: 0)
                InfoButton(topic: .caffeineLeft)
            }
            HStack(spacing: 0) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .frame(width: Sizes.icon, height: Sizes.icon)
                    .background(Accent.orange.tint(scheme), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let cutoff = model.caffeineCutoffShown {
                        Text("Cutoff \u{00B7} \(Clock.format(cutoff))").font(.bodyEmphasis)
                        Text("Your last caffeine of the day, so very little is left by your \(Clock.format(bedtime)) bedtime.")
                            .font(.secondary).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Cutoff \u{00B7} before you\u{2019}re up").font(.bodyEmphasis)
                        Text(model.caffeineEarlyOnlyText)
                            .font(.secondary).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 12)
                Spacer(minLength: 0)
                InfoButton(topic: .caffeineCutoff)
            }
            HowWeGotThisLink(title: "Caffeine in your body",
                             method: "Caffeine takes about 45 minutes to be fully absorbed, then about \(Int(model.caffeineHalfLifeHours)) hours for half of it to leave your body. That's 5 hours for most people (somewhere between 3 and 7), and about 8 (one and a half times as long) on the combined pill, which slows how fast the liver clears it, from one small study; the ring and patch probably do the same. The app uses the one that fits your birth control setting. We add up every drink you logged at the time you had it; drinks after midnight count toward the evening before, until \(Clock.format(AppDay.rolloverMinutes)). Your cutoff is the latest time a 12 oz drip coffee (140 mg) would drop below 25 mg by your bedtime, rounded down to the half hour. When that time comes before you\u{2019}re even up, there\u{2019}s no cutoff to show; instead the app works out the biggest single drink you could have soon after waking. Bigger drinks need to be earlier: the note under your usual drink checks its real size.")
        }
    }

    private var bedtimeNote: String {
        if bedtimeOK { return "Under the \(bedtimeGoal) mg goal. Good for deep sleep." }
        if let cutoff = model.caffeineCutoffShown {
            return "Above the \(bedtimeGoal) mg goal. Next time, finish caffeine by \(Clock.format(cutoff))."
        }
        return "Above the \(bedtimeGoal) mg goal. Next time, keep it to one small drink soon after you wake (up to about \(model.caffeineLargestDoseAtWake) mg)."
    }

    private var chartSummary: String {
        let peak = curve.max { $0.mg < $1.mg }
        let peakText = peak.map { "peaks near \(Int($0.mg.rounded())) mg at \(Clock.format($0.time))" } ?? "stays at zero"
        let cutoffText = model.caffeineCutoffShown.map { "Cutoff \(Clock.format($0))." } ?? "Cutoff before you\u{2019}re up: no time today works for a full coffee."
        return "Caffeine in your body today \(peakText) and falls to about \(model.caffeineAtBedtime) mg by your \(Clock.format(bedtime)) bedtime. \(cutoffText) Goal under \(bedtimeGoal) mg."
    }

    // MARK: Timed to your energy

    private var timing: CaffeineModel.Timing {
        timingDay == .today ? model.caffeineTimingToday : model.caffeineTimingTomorrow
    }

    private var timingEnergy: EnergyDay {
        timingDay == .today ? model.energyToday : model.energyTomorrow
    }

    /// The dot on the timeline: today's first drink, or tomorrow's coffee nap.
    private var timingMarker: Minutes? {
        timingDay == .today ? model.caffeineDoses.first?.time : timing.coffeeNapAt
    }

    /// No safe window for a typical drink (the cutoff comes before
    /// grogginess clears): no window and no cutoff time are shown.
    private var noWindow: Bool { timing.cutoffBeforeWindow }

    private var timingTitle: String {
        let day = label(timingDay)
        if noWindow { return "\(day): one small drink early" }
        if timing.coffeeNapAt != nil { return "\(day): a coffee nap fits" }
        if timingDay == .today, let first = model.caffeineDoses.first?.time {
            return first >= timing.bestWindow.start ? "\(day): good timing" : "\(day): a little early"
        }
        return "\(day): best window \(timing.bestWindow.label)"
    }

    private var timingNote: String {
        noWindow ? model.caffeineEarlyOnlyText : timing.note
    }

    private var timingSummary: String {
        var parts: [String] = ["\(label(timingDay)):"]
        if let g = timingEnergy.zone(.grogginess) { parts.append("grogginess \(g.range.label),") }
        if !noWindow { parts.append("best caffeine window \(timing.bestWindow.label),") }
        if let d = timingEnergy.zone(.afternoonDip) { parts.append("afternoon dip \(d.range.label),") }
        if let nap = timing.coffeeNapAt { parts.append("coffee nap at \(Clock.format(nap)),") }
        else if timingDay == .today, let first = model.caffeineDoses.first?.time { parts.append("first caffeine at \(Clock.format(first)),") }
        parts.append(noWindow ? "no safe time for a typical drink; one small drink early." : "cutoff \(Clock.format(timing.cutoff)).")
        return parts.joined(separator: " ")
    }

    /// From 7am (or earlier if she's up earlier) to an hour after bedtime.
    private var span: ClosedRange<Minutes> {
        let groggyStart = timingEnergy.zone(.grogginess)?.range.start ?? 420
        let start = min(420, (groggyStart / 60) * 60)
        return start...max(start + 360, bedtime + 60)
    }

    /// What a moment on the timing bar means for caffeine.
    private var timingReadout: (title: String, value: String, detail: String) {
        guard let raw = selectedTiming else {
            if noWindow {
                return (label(timingDay), "No time works for a full coffee", "At no time today would a 12 oz drip coffee (140 mg) be down to under 25 mg by bedtime. If you have one, keep it small, soon after you wake.")
            }
            return (label(timingDay), "Best window \(timing.bestWindow.label)",
                    "Caffeine works best once grogginess clears and before your \(Clock.format(timing.cutoff)) cutoff.")
        }
        let t = min(max((raw / 5) * 5, span.lowerBound), span.upperBound)
        let groggy = timingEnergy.zone(.grogginess)?.range
        let dip = timingEnergy.zone(.afternoonDip)?.range
        let title = Clock.format(t)
        if let nap = timing.coffeeNapAt, abs(t - nap) <= 10 {
            return (title, "Coffee nap", "A regular coffee, then a 20-minute nap. The caffeine kicks in just as you wake up.")
        }
        if let groggy, groggy.contains(t) {
            return (title, "Still groggy", "Caffeine works less well while you're waking up. Daylight and water help more. Wait until \(Clock.format(groggy.end)).")
        }
        if t >= timing.cutoff {
            let inDip = dip?.contains(t) == true ? " You're in your afternoon dip, so try daylight or a short break instead." : ""
            return (title, noWindow ? "Too late for a typical drink" : "After your cutoff",
                    "Caffeine now would still be in your body at bedtime and make your sleep lighter.\(inDip)")
        }
        if let dip, dip.contains(t) {
            return (title, "Afternoon dip", "Your natural energy low. Caffeine is still OK before your cutoff; daylight or a short break works too.")
        }
        if timing.bestWindow.contains(t) {
            return (title, "Good time for caffeine", "Grogginess has cleared and it's early enough to be mostly gone by bedtime.")
        }
        return (title, "Before you're up", "Your caffeine window starts at \(Clock.format(timing.bestWindow.start)).")
    }

    /// The audio graph's points for the timing strip: when you're groggy,
    /// the best window, the dip and the cutoff, in order.
    private var timingLabels: [String] { ["Groggy until", "Best window starts", "Afternoon dip starts", "Cutoff"] }
    private var timingPoints: [(x: Int, y: Double)] {
        var out: [(x: Int, y: Double)] = []
        if let g = timingEnergy.zone(.grogginess)?.range { out.append((g.end, 0)) }
        if !noWindow { out.append((timing.bestWindow.start, 1)) }
        if let d = timingEnergy.zone(.afternoonDip)?.range { out.append((d.start, 2)) }
        if !noWindow { out.append((timing.cutoff, 3)) }
        return out
    }

    private var timingCard: some View {
        Card(accent: .mint) {
            HStack(spacing: 0) {
                Text("Timed to your energy").font(.bodyEmphasis)
                Spacer()
                if timing.coffeeNapAt != nil {
                    Text("Coffee nap").font(.secondary).fontWeight(.semibold).secondaryText()
                }
                InfoButton(topic: .coffeeNap).padding(.vertical, -12)
            }
            AdaptiveSegmentedPicker("Day", selection: $timingDay, options: Array(TimingDay.allCases), accent: .mint) { day in label(day) }
            let r = timingReadout
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .mint,
                         onClear: selectedTiming == nil ? nil : { selectedTiming = nil })
                .frame(maxWidth: .infinity, alignment: .leading)
                .motion(.dataSwap, value: timingDay)
            EnergyTimingChart(span: span, groggy: timingEnergy.zone(.grogginess)?.range, window: noWindow ? nil : timing.bestWindow,
                              dip: timingEnergy.zone(.afternoonDip)?.range, cutoff: noWindow ? nil : timing.cutoff, marker: timingMarker,
                              selected: selectedTiming.map { min(max($0, span.lowerBound), span.upperBound) },
                              selection: $selectedTiming)
                .frame(height: 74)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(timingSummary)
                .accessibilityChartDescriptor(ClockChartDescriptor(
                    title: "Caffeine timing and your energy", seriesName: "Times", yTitle: "Moment",
                    points: timingPoints, yLabel: { timingLabels[min(max(Int($0.rounded()), 0), timingLabels.count - 1)] }))
                .motion(.dataSwap, value: timingDay)
            ScrubHint(each: "hour")
            HStack(spacing: 12) {
                // The blocks carry their own labels; this spells them out.
                legend("Groggy: still waking up", color: Accent.indigo.fill(scheme).opacity(0.55))
                if !noWindow { legend("Best: best for caffeine", color: Accent.mint.fill(scheme).opacity(0.55)) }
                legend("Dip: afternoon dip", color: Accent.blue.fill(scheme).opacity(0.6))
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(timingTitle).font(.bodyEmphasis)
                Text(timingNote).font(.bodyText).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            NavigationLink { EnergyView() } label: {
                HStack(spacing: 6) {
                    Text("See your energy curve")
                    Image(systemName: "chevron.right").font(.secondary).fontWeight(.bold).accessibilityHidden(true)
                }
                .font(.bodyEmphasis)
                .foregroundStyle(Accent.indigo.ink(scheme))
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
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

    /// At accessibility sizes the goal, cutoff and bedtime labels collided
    /// on the chart ("2pmbed12:30"), so they move to a legend under it.
    private var labelsInLegend: Bool { typeSize.isAccessibilitySize }

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
        VStack(alignment: .leading, spacing: 8) {
            chart.frame(height: 180)
            if labelsInLegend { legend }
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
            .accessibilityHidden(true)   // VoiceOver reads the chart's summary instead (round 3, A9)
            guides.accessibilityHidden(true)
            markers.accessibilityHidden(true)
        }
        .chartScrub($selection, snapped: selected?.time, steps: points.map(\.time))
        .chartXScale(domain: start...end)
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
            AxisMarks(position: .leading, values: [0.0, 100.0, 200.0]) { value in
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
            .annotation(position: .top, alignment: .leading) {
                if !labelsInLegend {
                    Text("\(goal) mg").font(.chartLabel(size: 11, weight: .semibold)).foregroundStyle(Accent.mint.ink(scheme))
                }
            }
        if let cutoff, cutoff >= start {
            RuleMark(x: .value("Cutoff", cutoff))
                .foregroundStyle(Accent.orange.fill(scheme))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .annotation(position: .top, alignment: .leading) {
                    if !labelsInLegend {
                        Text("\(BodyLogStyle.shortTime(cutoff)) cutoff").font(.chartLabel(size: 11, weight: .semibold)).foregroundStyle(Accent.orange.ink(scheme))
                    }
                }
        }
        RuleMark(x: .value("Bedtime", bedtime))
            .foregroundStyle(Accent.purple.fill(scheme))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            .annotation(position: .top, alignment: .trailing) {
                if !labelsInLegend {
                    Text("bed \(Clock.format(bedtime, suffix: false))").font(.chartLabel(size: 11, weight: .semibold)).foregroundStyle(Accent.purple.ink(scheme))
                }
            }
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

    /// Zones wide enough (about an hour) to hold their own label.
    private func labelFits(_ zone: TimingZone) -> Bool {
        clamp(zone.range.end) - clamp(zone.range.start) >= 50
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
            .accessibilityHidden(true)   // VoiceOver reads the chart's summary instead (round 3, A9)
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
            .accessibilityHidden(true)   // VoiceOver reads the chart's summary instead (round 3, A9)
            cutoffRule.accessibilityHidden(true)
            dots.accessibilityHidden(true)
        }
        .chartScrub($selection)
        .chartXScale(domain: span.lowerBound...span.upperBound)
        .chartYScale(domain: 0.0...1.0)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) { Text(BodyLogStyle.shortTime(m)) }
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
                .annotation(position: .top, alignment: .center) {
                    Text("\(BodyLogStyle.shortTime(cutoff)) cutoff").font(.chartLabel(size: 11, weight: .semibold)).foregroundStyle(Accent.yellow.ink(scheme))
                }
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
