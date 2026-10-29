import WidgetKit
import SwiftUI
import HealthCore

/// Watch-face complications: recovery, cycle, today's pill, caffeine & water,
/// and tonight's bedtime with the smart alarm. They show the numbers the iPhone last sent
/// (`WidgetSnapshot`), say "Example" for example data, never show yesterday's
/// numbers as today's, and open the matching Watch page when tapped.
@main
struct HealthNextComplications: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
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

struct ComplicationProvider: TimelineProvider {
    /// The Bedtime complication: rises in the Smart Stack from 90 minutes
    /// before bed, and knows the alarm's state.
    var bedtime = false

    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: .now, snapshot: .example) }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .example) : WidgetSnapshot.load(),
                                     alarm: bedtime ? WatchAlarmState.load() : nil))
    }

    /// Now; when the numbers turn six hours old (greyed, with their time);
    /// the app-day rollover (caffeine back to 0, recovery and the cycle day
    /// to "—"); and for Bedtime, the stretch before bed. New numbers from the
    /// phone reload the timeline themselves.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let alarm = bedtime ? WatchAlarmState.load() : nil
        let now = Date.now
        var dates: [Date] = [now]
        var relevantFrom: Date?
        var relevantUntil: Date?
        if let s = snap {
            dates.append(s.appDayStart.addingTimeInterval(24 * 3600))
            dates.append(s.updated.addingTimeInterval(6 * 3600))
            // The next pill day (12 hours after the pill time): the pill
            // complication moves on to the next pill.
            if let p = s.pill(at: now) { dates.append(p.pillTime.addingTimeInterval(12 * 3600)) }
            if bedtime, let bed = s.bedtime(at: now) {
                relevantFrom = bed.addingTimeInterval(-90 * 60)
                relevantUntil = bed.addingTimeInterval(60 * 60)
                dates += [relevantFrom!, relevantUntil!]
            }
        }
        let entries = Set(dates.filter { $0 >= now }).sorted().map { date -> ComplicationEntry in
            var relevance: TimelineEntryRelevance?
            if let from = relevantFrom, let until = relevantUntil {
                relevance = date >= from && date < until
                    ? TimelineEntryRelevance(score: 80, duration: until.timeIntervalSince(date))
                    : TimelineEntryRelevance(score: 0)
            }
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
        StaticConfiguration(kind: "WatchRecovery", provider: ComplicationProvider()) { entry in
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

// MARK: - Cycle

struct CycleComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchCycle", provider: ComplicationProvider()) { entry in
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
        StaticConfiguration(kind: "WatchPill", provider: ComplicationProvider()) { entry in
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

    private func headline(_ pill: WidgetSnapshot.PillState?) -> String {
        guard let pill else { return dash }
        if let taken = pill.taken { return "Taken \(time(taken))" }
        if !pill.isPillDay { return pill.breakName }
        return pill.isNewPack ? "New pack \u{00B7} pill 1" : "Pill \(pill.packDay) of \(pill.packLength)"
    }

    private func detail(_ pill: WidgetSnapshot.PillState?) -> String {
        guard let pill else { return "Combined pill only" }
        if pill.taken != nil { return "Pill \(pill.packDay) of \(pill.packLength)" }
        if !pill.isPillDay { return "No pill today" }
        return "\(Clock.format(pill.time)) \u{00B7} tap to mark taken"
    }

    private func cornerLabel(_ pill: WidgetSnapshot.PillState?, _ s: WidgetSnapshot?) -> String {
        if let missing = missingLine(s, now: entry.date), pill == nil { return missing }
        guard let pill else { return "Pill" }
        if let taken = pill.taken { return "Taken \(time(taken))" }
        if !pill.isPillDay { return pill.breakName }
        return "Pill \(pill.packDay) \u{00B7} \(Clock.format(pill.time))"
    }

    private func inline(_ pill: WidgetSnapshot.PillState?, _ s: WidgetSnapshot?) -> String {
        guard let pill else { return missingLine(s, now: entry.date) ?? "Pill" }
        if pill.taken != nil { return "Pill \(pill.packDay) taken" }
        if !pill.isPillDay { return pill.breakName }
        return "Pill \(pill.packDay) \u{00B7} \(Clock.format(pill.time))"
    }

    private func spoken(_ pill: WidgetSnapshot.PillState?, _ s: WidgetSnapshot?) -> String {
        guard let pill else { return "Pill: \(missingLine(s, now: entry.date)?.lowercased() ?? "combined pill only")" }
        if let taken = pill.taken { return "Pill \(pill.packDay) taken at \(time(taken))" }
        if !pill.isPillDay { return "\(pill.breakName), no pill today" }
        return "Pill \(pill.packDay), take at \(Clock.format(pill.time)). Tap to mark taken."
    }
}

// MARK: - Caffeine & water

struct CaffeineComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchCaffeine", provider: ComplicationProvider()) { entry in
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
        StaticConfiguration(kind: "WatchBedtime", provider: ComplicationProvider(bedtime: true)) { entry in
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
