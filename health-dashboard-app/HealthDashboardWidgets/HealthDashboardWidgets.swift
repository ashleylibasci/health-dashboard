import WidgetKit
import SwiftUI
import HealthCore

/// Home Screen and Lock Screen widgets. They show the last numbers the app
/// saved (`WidgetSnapshot`): recovery, cycle, today's caffeine and water, and
/// the bedtime streak. Example data is always labelled, and yesterday's
/// numbers never show as today's.
@main
struct HealthDashboardWidgets: WidgetBundle {
    var body: some Widget {
        RecoveryWidget()
        CycleWidget()
        TodayWidget()
        StreakWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil until the app has run once.
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .example) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .example) : WidgetSnapshot.load()))
    }

    /// Now; the caffeine cutoff (the latte button says so after it); when the
    /// numbers turn six hours old (greyed); and the moment the app day rolls
    /// over (caffeine and water back to 0, recovery and the cycle day to "—").
    /// The app reloads the widgets whenever its numbers change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let now = Date.now
        var dates: [Date] = [now]
        if let s = snap {
            dates.append(s.appDayStart.addingTimeInterval(24 * 3600))
            dates.append(s.updated.addingTimeInterval(6 * 3600))
            if let cutoff = s.caffeineCutoff { dates.append(cutoff) }
        }
        let entries = Set(dates.filter { $0 >= now }).sorted().map { SnapshotEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

// MARK: - Shared pieces

/// Widget type: rounded numbers with even-width digits, as in the app.
private enum WidgetType {
    /// Big numbers on Home Screen widgets.
    static let hero: Font = .system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    /// Numbers on Lock Screen widgets.
    static let number: Font = .system(.title3, design: .rounded, weight: .bold).monospacedDigit()
}

private let dash = "\u{2014}"

private struct WidgetHeader: View {
    let title: String
    let accent: Accent
    let snapshot: WidgetSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .widgetAccentable()
            Spacer(minLength: 2)
            if snapshot.isSample {
                Text("Example")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .accessibilityLabel("Example data")
            }
        }
    }
}

/// "As of 7:22pm", or "As of Mon 7:22pm" from another day, so old numbers
/// never pass as current.
private struct AsOf: View {
    let snapshot: WidgetSnapshot
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(asOfText(snapshot, now: now))
            .font(.system(size: 11))
            .foregroundStyle(Palette(scheme: scheme).tertiary)
    }
}

private func asOfText(_ s: WidgetSnapshot, now: Date) -> String {
    let sameDay = Calendar.current.isDate(s.updated, inSameDayAs: now)
    let day = sameDay ? "" : s.updated.formatted(.dateTime.weekday(.abbreviated)) + " "
    return "As of \(day)\(time(s.updated))"
}

/// Before the app has run once, in a size that fits each family.
private struct OpenAppPrompt: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "heart.text.square").font(.title3)
            }
            .accessibilityLabel("Open Health Dashboard to see your numbers")
        case .accessoryInline:
            Text("Open Health Dashboard")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Health Dashboard").font(.caption2.weight(.semibold))
                Text("Open the app to see your numbers").font(.headline).lineLimit(2).minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
        default:
            VStack(spacing: 4) {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                Text("Open Health Dashboard to see your numbers")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private func ounces(_ ml: Double) -> String {
    let oz = ml / 29.5735
    return oz >= 10 ? "\(Int(oz.rounded())) oz" : String(format: "%.1f oz", oz)
}

/// "8:15am", like everywhere in the app.
private func time(_ date: Date) -> String {
    Clock.format(Clock.minutesOfDay(date))
}

extension View {
    /// Greys out numbers six hours or more old.
    fileprivate func stale(_ stale: Bool) -> some View { opacity(stale ? 0.55 : 1) }
}

/// The app's own background in both modes.
private struct WidgetBackground: View {
    let accent: Accent
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Palette(scheme: scheme).background
            Palette(scheme: scheme).glow(accent)
        }
    }
}

// MARK: - Recovery

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Recovery", provider: SnapshotProvider()) { entry in
            RecoveryView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground(accent: .indigo) }
        }
        .configurationDisplayName("Recovery")
        .description("Today's recovery score and how much energy you have left.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct RecoveryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let s = entry.snapshot {
            let now = entry.date
            let value = s.recovery(at: now)
            let stale = s.isStale(at: now)
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(value ?? 0), in: 0...100) {
                    Text("Recovery")
                } currentValueLabel: {
                    Text(value.map(String.init) ?? dash)
                        .font(WidgetType.number)
                        .contentTransition(.numericText(value: Double(value ?? 0)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .stale(stale)
                .accessibilityLabel(recoverySentence(s, now: now))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recovery\(s.isSample ? " \u{00B7} Example" : "")").font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    Text(headline(s, now: now))
                        .font(.headline)
                        .stale(stale)
                    if stale {
                        Text(asOfText(s, now: now)).font(.caption2)
                    } else if let e = s.energyLeft(at: now) {
                        Text("Energy left \(e)%").font(.caption2)
                    }
                }
                .accessibilityElement(children: .combine)
            case .accessoryInline:
                Text(value.map { "Recovery \($0) \u{00B7} \(s.recoveryLabel)" } ?? "Recovery: \(headline(s, now: now).lowercased())")
            default:
                let p = Palette(scheme: scheme)
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Recovery", accent: .indigo, snapshot: s)
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle().inset(by: 3.5).stroke(p.track, lineWidth: 7)
                            Circle().inset(by: 3.5).trim(from: 0, to: Double(value ?? 0) / 100)
                                .stroke(Accent.indigo.fill(scheme), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .widgetAccentable()
                            Text(value.map(String.init) ?? dash)
                                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                                .minimumScaleFactor(0.6)
                                .contentTransition(.numericText(value: Double(value ?? 0)))
                        }
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                        if family == .systemMedium { details(s, now: now) }
                    }
                    .stale(stale)
                    if family != .systemMedium {
                        Text(headline(s, now: now, withValue: false))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    AsOf(snapshot: s, now: now)
                }
                .foregroundStyle(p.primary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(recoverySentence(s, now: now))
            }
        } else {
            OpenAppPrompt()
        }
    }

    /// "68 · Take it steady"; "No reading yet"; or, once a new day has
    /// started, "Not updated today".
    private func headline(_ s: WidgetSnapshot, now: Date, withValue: Bool = true) -> String {
        guard s.isCurrent(at: now) else { return "Not updated today" }
        guard let value = s.recovery else { return "No reading yet" }
        return withValue ? "\(value) \u{00B7} \(s.recoveryLabel)" : s.recoveryLabel
    }

    private func details(_ s: WidgetSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline(s, now: now, withValue: false))
                .font(.system(size: 15, weight: .semibold))
            if let e = s.energyLeft(at: now) {
                // Energy is mint everywhere.
                Label("Energy left \(e)%", systemImage: "bolt.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Accent.mint.ink(scheme))
            }
            if let line = s.cycleLine(at: now) {
                Label(line, systemImage: "drop.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette(scheme: scheme).secondary)
                    .lineLimit(1)
            }
        }
    }

    private func recoverySentence(_ s: WidgetSnapshot, now: Date) -> String {
        var parts = [s.recovery(at: now).map { "Recovery \($0) out of 100, \(s.recoveryLabel)" } ?? "Recovery: \(headline(s, now: now).lowercased())"]
        if let e = s.energyLeft(at: now) { parts.append("energy left \(e) percent") }
        if s.isSample { parts.append("example data") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Cycle

struct CycleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Cycle", provider: SnapshotProvider()) { entry in
            CycleWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground(accent: .pink) }
        }
        .configurationDisplayName("Cycle")
        .description("Your cycle day or pill, with no countdowns.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct CycleWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let s = entry.snapshot {
            let now = entry.date
            let number = s.cycleNumber(at: now)
            let line = s.isCurrent(at: now) ? (s.cycleLine ?? "Not tracking a cycle") : "Not updated today"
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text(number.map(String.init) ?? dash)
                            .font(WidgetType.number)
                            .widgetAccentable()
                            .contentTransition(.numericText(value: Double(number ?? 0)))
                        Text(s.cycleNumberLabel ?? "Cycle").font(.caption2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(line)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cycle\(s.isSample ? " \u{00B7} Example" : "")").font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    Text(line).font(.headline).lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            default:
                let p = Palette(scheme: scheme)
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Cycle", accent: .pink, snapshot: s)
                    if let n = number {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(s.cycleNumberLabel ?? "Day").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(p.secondary)
                            Text("\(n)")
                                .font(WidgetType.hero)
                                .contentTransition(.numericText(value: Double(n)))
                        }
                    }
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(p.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    AsOf(snapshot: s, now: now)
                }
                .foregroundStyle(p.primary)
                .accessibilityElement(children: .combine)
            }
        } else {
            OpenAppPrompt()
        }
    }
}

// MARK: - Today: caffeine and water

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground(accent: .yellow) }
        }
        .configurationDisplayName("Caffeine & water")
        .description("Today's caffeine, your cutoff and water in ounces, with a button to log your latte.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let s = entry.snapshot {
            let now = entry.date
            let mg = s.caffeineMg(at: now)
            let water = s.waterML(at: now)
            // Past today's cutoff: the note turns coral and the button says so.
            let cutoff = s.caffeineCutoff(at: now)
            let pastCutoff = cutoff.map { now >= $0 } ?? false
            let note: String = {
                if !s.isCurrent(at: now) { return "Open the app for today\u{2019}s cutoff" }
                if let cutoff, pastCutoff { return "Past your \(time(cutoff)) cutoff" }
                return s.caffeineNote
            }()
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(mg) mg caffeine")
                        .font(.headline)
                        .contentTransition(.numericText(value: Double(mg)))
                        .invalidatableContent()
                    Text(note).font(.caption2)
                    Text("\(ounces(water)) of \(ounces(s.waterGoalML)) water").font(.caption2)
                }
                .accessibilityElement(children: .combine)
            } else {
                let p = Palette(scheme: scheme)
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Today", accent: .yellow, snapshot: s)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(mg)")
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: Double(mg)))
                            .invalidatableContent()
                        Text("mg").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.secondary)
                    }
                    // With the button there's no room for the note: the
                    // button carries the cutoff instead.
                    if s.quickDrink == nil {
                        Text(note).font(.system(size: 12))
                            .foregroundStyle(pastCutoff ? Accent.coral.ink(scheme) : p.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: min(water / max(s.waterGoalML, 1), 1))
                        .tint(Accent.blue.fill(scheme))
                    Text("\(ounces(water)) of \(ounces(s.waterGoalML))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Accent.blue.ink(scheme))
                        .contentTransition(.numericText(value: water))
                    Spacer(minLength: 0)
                    if let drink = s.quickDrink {
                        // Logs it right here, no need to open the app.
                        Button(intent: LogLatteIntent()) {
                            Label(pastCutoff ? "\(drink.name) \u{00B7} past cutoff" : "\(drink.name) \(drink.mg) mg", systemImage: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        }
                        .tint(pastCutoff ? Accent.coral.fill(scheme) : Accent.yellow.fill(scheme))
                        .accessibilityLabel("Log a \(drink.name.lowercased()), \(drink.mg) milligrams" + (pastCutoff ? ", past your cutoff" : ""))
                    }
                }
                .foregroundStyle(p.primary)
            }
        } else {
            OpenAppPrompt()
        }
    }
}

// MARK: - Bedtime streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SnapshotProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground(accent: .purple) }
        }
        .configurationDisplayName("Bedtime streak")
        .description("Nights in a row you were in bed on time, and tonight's bedtime.")
        .supportedFamilies([.systemSmall])
    }
}

private struct StreakWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let s = entry.snapshot {
            let p = Palette(scheme: scheme)
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "In bed on time", accent: .purple, snapshot: s)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(s.bedtimeStreak)")
                        .font(WidgetType.hero)
                        .contentTransition(.numericText(value: Double(s.bedtimeStreak)))
                    Text(s.bedtimeStreak == 1 ? "night" : "nights").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.secondary)
                }
                if let bed = s.bedtime(at: entry.date) {
                    Label("Bed by \(time(bed))", systemImage: "moon.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Accent.purple.ink(scheme))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(p.primary)
            .accessibilityElement(children: .combine)
        } else {
            OpenAppPrompt()
        }
    }
}
