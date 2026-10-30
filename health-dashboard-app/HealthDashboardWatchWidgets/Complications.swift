import WidgetKit
import SwiftUI
import HealthCore

/// Watch-face complications: recovery, energy now, cycle, today's pill, caffeine & water,
/// and tonight's bedtime with the smart alarm. They show the numbers the iPhone last sent
/// (`WidgetSnapshot`), say "Example" for example data, never show yesterday's
/// numbers as today's, and open the matching Watch page when tapped.
@main
struct HealthNextComplications: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
        EnergyComplication()
        CycleComplication()
        PillComplication()
        CaffeineComplication()
        BedtimeComplication()
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// The Watch app's smart alarm (Bedtime only).
    var alarm: WatchAlarmState? = nil
    var relevance: TimelineEntryRelevance? = nil
}

/// When each complication rises in the Smart Stack (D-W4): Recovery for
/// two hours after she wakes, Pill from just before her pill time until
/// it's taken (and, as the break-week card, gently through the break and
/// from the morning of a new pack day), Caffeine & water in the 90 minutes before the cutoff and
/// whenever water falls a bottle behind pace, Bedtime from 90 minutes
/// before bed. Cycle and Energy have no moment of their own.
enum ComplicationKind {
    case recovery, energy, cycle, pill, caffeine, bedtime

    /// A stretch of time it's relevant, and how strongly (0–100).
    struct Window {
        var from: Date
        var until: Date
        var score: Float
    }

    func windows(_ s: WidgetSnapshot, now: Date) -> [Window] {
        switch self {
        case .recovery:
            guard let wake = s.wake, s.recovery(at: now) != nil else { return [] }
            return [Window(from: wake, until: wake.addingTimeInterval(2 * 3600), score: 50)]
        case .cycle, .energy:
            return []
        case .pill:
            guard let p = s.pill(at: now) else { return [] }
            // The pill day runs from 12 hours before the pill time.
            let dayStart = p.pillTime.addingTimeInterval(-12 * 3600)
            if !p.isPillDay {
                // H-F3: "Break week, day 3 · new pack Sun", low and steady.
                return [Window(from: dayStart, until: dayStart.addingTimeInterval(24 * 3600), score: 30)]
            }
            guard p.taken == nil else { return [] }
            var all = [Window(from: p.pillTime.addingTimeInterval(-15 * 60), until: p.pillTime.addingTimeInterval(3 * 3600), score: 90)]
            if p.isNewPack {
                // H-F3: "Start new pack today" from 7am, so she has it with her.
                let morning = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: p.day) ?? dayStart
                all.append(Window(from: max(morning, dayStart), until: p.pillTime.addingTimeInterval(-15 * 60), score: 70))
            }
            return all
        case .caffeine:
            var all: [Window] = []
            if let cutoff = s.caffeineCutoff(at: now) {
                all.append(Window(from: cutoff.addingTimeInterval(-90 * 60), until: cutoff, score: 60))
            }
            if let behind = waterBehind(s, now: now) { all.append(behind) }
            return all
        case .bedtime:
            guard let bed = s.bedtime(at: now) else { return [] }
            return [Window(from: bed.addingTimeInterval(-90 * 60), until: bed.addingTimeInterval(60 * 60), score: 80)]
        }
    }

    /// Water a bottle or more behind an even pace from waking to an hour
    /// before bed. Never with the goal hidden (eating-disorder history).
    private func waterBehind(_ s: WidgetSnapshot, now: Date) -> Window? {
        guard s.showsWaterGoal, s.bottleML > 0, let wake = s.wake, let bed = s.bedtime(at: now) else { return nil }
        let end = bed.addingTimeInterval(-3600)
        guard end > wake else { return nil }
        // The moment the pace reaches today's water plus a bottle.
        let share = (s.waterML(at: now) + s.bottleML) / s.waterGoalML
        guard share < 1 else { return nil }
        let behindFrom = wake.addingTimeInterval(end.timeIntervalSince(wake) * share)
        guard behindFrom < end else { return nil }
        return Window(from: behindFrom, until: end, score: 40)
    }
}

struct ComplicationProvider: TimelineProvider {
    let kind: ComplicationKind

    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: .now, snapshot: .example) }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .example) : WidgetSnapshot.load(),
                                     alarm: kind == .bedtime ? WatchAlarmState.load() : nil))
    }

    /// Now; when the numbers turn six hours old (greyed, with their time);
    /// the app-day rollover (caffeine back to 0, recovery and the cycle day
    /// to "—"); the next pill day; and the edges of its Smart Stack
    /// windows. New numbers from the phone reload the timeline themselves.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let alarm = kind == .bedtime ? WatchAlarmState.load() : nil
        let now = Date.now
        var dates: [Date] = [now]
        var windows: [ComplicationKind.Window] = []
        if let s = snap {
            dates.append(s.appDayStart.addingTimeInterval(24 * 3600))
            dates.append(s.updated.addingTimeInterval(6 * 3600))
            // The next pill day (12 hours after the pill time): the pill
            // complication moves on to the next pill.
            if let p = s.pill(at: now) { dates.append(p.pillTime.addingTimeInterval(12 * 3600)) }
            // Energy's "now" dot moves on to each next point of the curve.
            if kind == .energy, let e = s.energy(at: now) {
                dates += e.moves(after: now).filter { $0 < s.appDayStart.addingTimeInterval(24 * 3600) }
            }
            windows = kind.windows(s, now: now)
            dates += windows.flatMap { [$0.from, $0.until] }
        }
        let entries = Set(dates.filter { $0 >= now }).sorted().map { date -> ComplicationEntry in
            let current = windows.filter { $0.from <= date && date < $0.until }.max { $0.score < $1.score }
            let relevance = current.map { TimelineEntryRelevance(score: $0.score, duration: $0.until.timeIntervalSince(date)) }
                ?? TimelineEntryRelevance(score: 0)
            return ComplicationEntry(date: date, snapshot: snap, alarm: alarm, relevance: relevance)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

/// Opens the Watch app on a page (0 Recovery, 1 Energy, 2 Tonight, 3 Log).
private func page(_ n: Int) -> URL { URL(string: "healthnext://page/\(n)")! }

private let families: [WidgetFamily] = [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]

/// "Recovery · Example".
private func title(_ name: String, _ s: WidgetSnapshot?) -> String {
    s?.isSample == true ? "\(name) \u{00B7} Example" : name
}

/// Rounded numbers with even-width digits.
private let numberFont: Font = .system(.title3, design: .rounded, weight: .bold).monospacedDigit()

private let dash = "\u{2014}"

/// "As of 9:40am", or "As of Mon 9:40pm" from another day.
private func asOf(_ s: WidgetSnapshot, now: Date) -> String {
    let sameDay = Calendar.current.isDate(s.updated, inSameDayAs: now)
    let day = sameDay ? "" : s.updated.formatted(.dateTime.weekday(.abbreviated)) + " "
    return "As of \(day)\(Clock.format(Clock.minutesOfDay(s.updated)))"
}

/// "8:15am".
private func time(_ date: Date) -> String { Clock.format(Clock.minutesOfDay(date)) }

/// The line under the numbers when there's nothing current to show: never
/// synced, or a new day since the phone last updated.
private func missingLine(_ s: WidgetSnapshot?, now: Date) -> String? {
    guard let s else { return "Open on iPhone" }
    return s.isCurrent(at: now) ? nil : "Open on iPhone to update"
}

extension View {
    /// Greys out numbers six hours or more old.
    fileprivate func stale(_ stale: Bool) -> some View { opacity(stale ? 0.55 : 1) }
}

// MARK: - Recovery

struct RecoveryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchRecovery", provider: ComplicationProvider(kind: .recovery)) { entry in
            RecoveryComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(page(0))
        }
        .configurationDisplayName("Recovery")
        .description("Today's recovery score and energy left.")
        .supportedFamilies(families)
    }
}

private struct RecoveryComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        let now = entry.date
        let value = s?.recovery(at: now)
        let stale = s?.isStale(at: now) ?? false
        let label = value.map { "Recovery \($0)" } ?? "Recovery, no reading yet"
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(value ?? 0), in: 0...100) {
                Image(systemName: "bolt.heart.fill")
            } currentValueLabel: {
                Text(value.map(String.init) ?? dash)
                    .font(numberFont)
                    .contentTransition(.numericText(value: Double(value ?? 0)))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Accent.indigo.fill(.dark))
            .widgetAccentable()
            .stale(stale)
            .accessibilityLabel(label)
        case .accessoryCorner:
            Text(value.map(String.init) ?? dash)
                .font(numberFont)
                .widgetAccentable()
                .widgetLabel {
                    if let line = missingLine(s, now: now) {
                        Text(line)
                    } else {
                        Gauge(value: Double(value ?? 0), in: 0...100) { Text("Recovery") }
                            .tint(Accent.indigo.fill(.dark))
                    }
                }
                .stale(stale)
                .accessibilityLabel(label)
        case .accessoryInline:
            if let s, let value {
                Text("Recovery \(value) \u{00B7} \(s.recoveryLabel)")
            } else {
                Text("Recovery: \(missingLine(s, now: now)?.lowercased() ?? "no reading yet")")
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(title("Recovery", s)).font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.indigo.ink(.dark))
                    .widgetAccentable()
                Text(s.flatMap { snap in value.map { "\($0) \u{00B7} \(snap.recoveryLabel)" } } ?? (s?.isCurrent(at: now) == true ? "No reading yet" : dash))
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    .stale(stale)
                if let line = missingLine(s, now: now) {
                    Text(line).font(.caption2)
                } else if let s, stale {
                    Text(asOf(s, now: now)).font(.caption2)
                } else if let e = s?.energyLeft(at: now) {
                    Text("Energy left \(e)%").font(.caption2)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Energy now

struct EnergyComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchEnergy", provider: ComplicationProvider(kind: .energy)) { entry in
            EnergyComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(page(1))
        }
        .configurationDisplayName("Energy now")
        .description("Today's energy curve with a dot for now: \"57 \u{00B7} dip till 6pm\".")
        .supportedFamilies(families)
    }
}

/// Today's "Energy now": the curve with a dot for now and where she is on
/// it. The curve is a prediction from last night, so it isn't greyed as
/// it ages; a new day clears it.
private struct EnergyComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        let now = entry.date
        let curve = s?.energy(at: now)
        let level = curve?.level(at: now)
        let short = curve?.shortLine(at: now)
        let missing = missingLine(s, now: now) ?? "Open on iPhone to update"
        let spoken = level.map { "Energy now \($0) of 100, \(curve?.line(at: now) ?? "")" } ?? "Energy now: \(missing.lowercased())"
        let mint = Accent.mint.fill(.dark)
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(level ?? 0), in: 0...100) {
                Image(systemName: "bolt.fill")
            } currentValueLabel: {
                Text(level.map(String.init) ?? dash)
                    .font(numberFont)
                    .contentTransition(.numericText(value: Double(level ?? 0)))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(mint)
            .widgetAccentable()
            .accessibilityLabel(spoken)
        case .accessoryCorner:
            Text(level.map(String.init) ?? dash)
                .font(numberFont)
                .widgetAccentable()
                .widgetLabel(level == nil ? missing : (short ?? "Energy"))
                .accessibilityLabel(spoken)
        case .accessoryInline:
            Text(level.map { "Energy \($0) \u{00B7} \(short ?? "")" } ?? "Energy: \(missing.lowercased())")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(title("Energy now", s)).font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.mint.ink(.dark))
                    .widgetAccentable()
                if let curve, let level {
                    EnergySpark(levels: curve.levels, now: curve.index(at: now), line: mint, dot: .white,
                                lineWidth: 1.5, dotSize: 6)
                        .widgetAccentable()
                    Text("\(level) \u{00B7} \(short ?? "")")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text(dash).font(.headline)
                    Text(missing).font(.caption2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        }
    }
}

// MARK: - Cycle

struct CycleComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchCycle", provider: ComplicationProvider(kind: .cycle)) { entry in
            CycleComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                // The Recovery page carries the cycle line.
                .widgetURL(page(0))
        }
        .configurationDisplayName("Cycle")
        .description("Your pill or cycle day, with no countdowns.")
        .supportedFamilies(families)
    }
}

private struct CycleComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        let now = entry.date
        let number = s?.cycleNumber(at: now).map(String.init) ?? dash
        let label = s?.cycleNumberLabel ?? "Cycle"
        let missing = missingLine(s, now: now)
        let line = missing ?? s?.cycleLine(at: now) ?? "Not tracking a cycle"
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text(number).font(numberFont)
                        .widgetAccentable()
                    Text(label).font(.system(size: 10, weight: .semibold))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(line)
        case .accessoryCorner:
            Image(systemName: "drop.fill")
                .font(.title3)
                .foregroundStyle(Accent.pink.fill(.dark))
                .widgetAccentable()
                .widgetLabel(missing == nil ? "\(label) \(number)" : "Open on iPhone")
                .accessibilityLabel(line)
        case .accessoryInline:
            Text(line)
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(title("Cycle", s)).font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.pink.ink(.dark))
                    .widgetAccentable()
                Text(line).font(.headline).lineLimit(2).minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Pill

struct PillComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchPill", provider: ComplicationProvider(kind: .pill)) { entry in
            PillComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                // One tap marks an untaken pill taken (with Undo on the
                // Recovery page); otherwise it just opens Recovery.
                .widgetURL(entry.snapshot?.pill(at: entry.date).map { $0.isPillDay && $0.taken == nil } == true
                           ? URL(string: "healthnext://pill")! : page(0))
        }
        .configurationDisplayName("Pill")
        .description("Today's pill: tap to mark it taken. Pink on a new pack day.")
        .supportedFamilies(families)
    }
}

/// "18", or a tick once it's taken; pink on a new pack's first day.
private struct PillComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        let pill = s?.pill(at: entry.date)
        let tint = pill?.isNewPack == true && pill?.taken == nil ? Accent.pink.fill(.dark) : Color.white
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    center(pill, font: numberFont)
                        .foregroundStyle(tint)
                        .widgetAccentable()
                    Text(pill?.isPillDay == false ? "Break" : "Pill").font(.system(size: 10, weight: .semibold))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(pill, s))
        case .accessoryCorner:
            center(pill, font: .system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
                .widgetAccentable()
                .widgetLabel(cornerLabel(pill, s))
                .accessibilityLabel(spoken(pill, s))
        case .accessoryInline:
            Text(inline(pill, s))
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(title("Pill", s)).font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.pink.ink(.dark))
                    .widgetAccentable()
                Text(headline(pill)).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text(missingLine(s, now: entry.date) ?? detail(pill)).font(.caption2).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The number, a tick once taken, or a dash.
    @ViewBuilder
    private func center(_ pill: WidgetSnapshot.PillState?, font: Font) -> some View {
        if let pill, pill.taken != nil {
            Image(systemName: "checkmark").font(font)
        } else if let pill, pill.isPillDay {
            Text("\(pill.packDay)").font(font)
        } else {
            Text(dash).font(font)
        }
    }

    /// The Smart Stack card (H-F3) in the break and on a new pack's
    /// first day: "Break week, day 3" / "New pack Sun", then "Start new
    /// pack today" / "Pill 1 at 9pm".
    private func headline(_ pill: WidgetSnapshot.PillState?) -> String {
        guard let pill else { return dash }
        if let taken = pill.taken { return "Taken \(time(taken))" }
        if let day = pill.breakDay { return "\(pill.breakName), day \(day)" }
        return pill.isNewPack ? "Start new pack today" : "Pill \(pill.packDay) of \(pill.packLength)"
    }

    private func detail(_ pill: WidgetSnapshot.PillState?) -> String {
        guard let pill else { return "Combined pill only" }
        if pill.taken != nil { return "Pill \(pill.packDay) of \(pill.packLength)" }
        if !pill.isPillDay { return newPack(pill) }
        if pill.isNewPack { return "Pill 1 at \(Clock.format(pill.time))" }
        return "\(Clock.format(pill.time)) \u{00B7} tap to mark taken"
    }

    /// "New pack Sun", or "New pack tomorrow" on the last break day.
    private func newPack(_ pill: WidgetSnapshot.PillState) -> String {
        guard let start = pill.newPackDay else { return "No pill today" }
        if Calendar.current.dateComponents([.day], from: pill.day, to: start).day == 1 { return "New pack tomorrow" }
        return "New pack \(start.formatted(.dateTime.weekday(.abbreviated)))"
    }

    private func cornerLabel(_ pill: WidgetSnapshot.PillState?, _ s: WidgetSnapshot?) -> String {
        if let missing = missingLine(s, now: entry.date), pill == nil { return missing }
        guard let pill else { return "Pill" }
        if let taken = pill.taken { return "Taken \(time(taken))" }
        if let day = pill.breakDay { return "\(pill.breakName), day \(day)" }
        return "Pill \(pill.packDay) \u{00B7} \(Clock.format(pill.time))"
    }

    private func inline(_ pill: WidgetSnapshot.PillState?, _ s: WidgetSnapshot?) -> String {
        guard let pill else { return missingLine(s, now: entry.date) ?? "Pill" }
        if pill.taken != nil { return "Pill \(pill.packDay) taken" }
        if let day = pill.breakDay { return "\(pill.breakName), day \(day) \u{00B7} \(newPack(pill).lowercased())" }
        return "Pill \(pill.packDay) \u{00B7} \(Clock.format(pill.time))"
    }

    private func spoken(_ pill: WidgetSnapshot.PillState?, _ s: WidgetSnapshot?) -> String {
        guard let pill else { return "Pill: \(missingLine(s, now: entry.date)?.lowercased() ?? "combined pill only")" }
        if let taken = pill.taken { return "Pill \(pill.packDay) taken at \(time(taken))" }
        if let day = pill.breakDay { return "\(pill.breakName), day \(day). \(newPack(pill))." }
        if pill.isNewPack { return "Start new pack today. Pill 1 at \(Clock.format(pill.time)). Tap to mark taken." }
        return "Pill \(pill.packDay), take at \(Clock.format(pill.time)). Tap to mark taken."
    }
}

// MARK: - Caffeine & water

struct CaffeineComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchCaffeine", provider: ComplicationProvider(kind: .caffeine)) { entry in
            CaffeineComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(page(3))
        }
        .configurationDisplayName("Caffeine & water")
        .description("Today's caffeine and water. Tap to log.")
        .supportedFamilies(families)
    }
}

private struct CaffeineComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    private func oz(_ ml: Double) -> String { "\(Int((ml / 29.5735).rounded())) oz" }

    var body: some View {
        let s = entry.snapshot
        let now = entry.date
        let mg = s?.caffeineMg(at: now) ?? 0
        let water = s?.waterML(at: now) ?? 0
        // Past today's cutoff with caffeine on board: the one coral state.
        let pastCutoff = s?.caffeineCutoff(at: now).map { now >= $0 } ?? false
        let spoken = s == nil ? "Caffeine: open on iPhone" : "\(mg) milligrams of caffeine today" + (pastCutoff ? ", past your cutoff" : "")
        switch family {
        case .accessoryCircular:
            // The ring fills toward 400 mg, the usual daily ceiling for adults.
            Gauge(value: Double(min(mg, 400)), in: 0...400) {
                Image(systemName: "cup.and.saucer.fill")
            } currentValueLabel: {
                Text(s == nil ? dash : "\(mg)")
                    .font(numberFont)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: Double(mg)))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(pastCutoff && mg > 0 ? Accent.coral.fill(.dark) : Accent.yellow.fill(.dark))
            .widgetAccentable()
            .accessibilityLabel(spoken)
        case .accessoryCorner:
            Image(systemName: "cup.and.saucer.fill")
                .font(.title3)
                .foregroundStyle(Accent.yellow.fill(.dark))
                .widgetAccentable()
                .widgetLabel(s == nil ? "Open on iPhone" : "\(mg) mg")
                .accessibilityLabel(spoken)
        case .accessoryInline:
            Text(s == nil ? "Caffeine: open on iPhone" : "\(mg) mg \u{00B7} \(oz(water)) water")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(title("Today", s)).font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.yellow.ink(.dark))
                    .widgetAccentable()
                if let s {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(mg) mg caffeine").font(.headline)
                        if pastCutoff {
                            Text(" \u{00B7} past cutoff").font(.caption.weight(.semibold))
                                .foregroundStyle(Accent.coral.ink(.dark))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // No goal under eating-disorder history: the total only.
                    Text(s.showsWaterGoal ? "\(oz(water)) of \(oz(s.waterGoalML)) water" : "\(oz(water)) water").font(.caption2)
                } else {
                    Text(dash).font(.headline)
                    Text("Open on iPhone").font(.caption2)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Bedtime

struct BedtimeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchBedtime", provider: ComplicationProvider(kind: .bedtime)) { entry in
            BedtimeComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(page(2))
        }
        .configurationDisplayName("Bedtime")
        .description("Tonight's bedtime and whether your Watch alarm is on.")
        .supportedFamilies(families)
    }
}

private struct BedtimeComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    /// "Watch alarm on · by 7:45am", "Tap to turn on Watch alarm", or nil.
    private var alarmLine: String? {
        guard let a = entry.alarm else { return nil }
        if a.needsOpen { return "Tap to turn on Watch alarm" }
        if let end = a.armedEnd, end > entry.date { return "Watch alarm on \u{00B7} by \(time(end))" }
        return nil
    }

    var body: some View {
        let s = entry.snapshot
        let now = entry.date
        let bed = s?.bedtime(at: now).map(time) ?? dash
        let missing = missingLine(s, now: now)
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "moon.fill").font(.system(size: 12))
                        .foregroundStyle(Accent.purple.fill(.dark))
                        .widgetAccentable()
                    Text(bed).font(.system(.footnote, design: .rounded, weight: .bold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bed by \(bed)")
        case .accessoryCorner:
            Image(systemName: "moon.fill")
                .font(.title3)
                .foregroundStyle(Accent.purple.fill(.dark))
                .widgetAccentable()
                .widgetLabel(missing ?? "Bed by \(bed)")
                .accessibilityLabel("Bed by \(bed)")
        case .accessoryInline:
            if let missing {
                Text("Bedtime: \(missing.lowercased())")
            } else if let end = entry.alarm?.armedEnd, end > now {
                Text("Bed by \(bed) \u{00B7} alarm \(time(end))")
            } else {
                Text("Bed by \(bed)")
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(title("Tonight", s)).font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.purple.ink(.dark))
                    .widgetAccentable()
                Text("Bed by \(bed)").font(.headline)
                if let missing {
                    Text(missing).font(.caption2)
                } else if let alarmLine {
                    Text(alarmLine).font(.caption2)
                        .foregroundStyle(Accent.orange.ink(.dark))
                } else if let n = s?.bedtimeStreak {
                    Text("In bed on time \(n) night\(n == 1 ? "" : "s") in a row").font(.caption2)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
