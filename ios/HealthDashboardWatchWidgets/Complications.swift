import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: .now, snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: context.isPreview ? .preview : WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        // The phone pushes fresh numbers; this re-checks every 30 minutes and at midnight.
        let next = min(Date.now.addingTimeInterval(1800), Calendar.current.startOfDay(for: .now.addingTimeInterval(86400)))
        completion(Timeline(entries: [ComplicationEntry(date: .now, snapshot: WidgetSnapshot.load())], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.recovery = 72; s.recoveryLabel = "Moderate"; s.headline = "Go easy today"; s.energy = 58; s.bedBy = "12:15am"
        s.cycleDay = 22; s.phase = "Luteal"; s.caffeineMg = 130; s.caffeineDay = WidgetSnapshot.eveningKey()
        s.waterBottles = 1.5; s.waterGoal = 3; s.waterDay = WidgetSnapshot.calendarKey(); s.updated = .now
        return s
    }
    var recoveryToday: Int? { isFromToday ? recovery : nil }
    var bedShort: String { bedBy?.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "") ?? "–" }
}

private let lavender = Color(hex: 0x7C8CF8), coffee = Color(hex: 0xE0A800), water = Color(hex: 0x4FA3F7)
private let rose = Color(hex: 0xF07A6B), night = Color(hex: 0x7C6CF0), mint = Color(hex: 0x5CC79A)
private let alarm = Color(hex: 0xFFA94D)

/// Every face spot: circle, corner, a wide rectangle, and the one-line text spot.
private let allFamilies: [WidgetFamily] = [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]

// MARK: Recovery

struct RecoveryComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var s: WidgetSnapshot

    var body: some View {
        let value = s.recoveryToday
        switch family {
        case .accessoryCorner:
            Image(systemName: "heart.fill").font(.title3).widgetAccentable()
                .widgetLabel { Gauge(value: Double(value ?? 0), in: 0...100) { Text("REC") } currentValueLabel: { Text(value.map(String.init) ?? "–") }.tint(lavender) }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Gauge(value: Double(value ?? 0), in: 0...100) { EmptyView() } currentValueLabel: { Text(value.map(String.init) ?? "–") }
                    .gaugeStyle(.accessoryCircularCapacity).tint(lavender)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recovery").font(.headline).widgetAccentable()
                    Text(value == nil ? "Open the app" : s.headline).font(.caption)
                    Text("Bed by \(s.bedShort)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Label("Recovery \(value.map(String.init) ?? "–")", systemImage: "heart.fill")
        default:
            Gauge(value: Double(value ?? 0), in: 0...100) { Image(systemName: "heart.fill") } currentValueLabel: { Text(value.map(String.init) ?? "–") }
                .gaugeStyle(.accessoryCircular).tint(lavender)
        }
    }
}

struct RecoveryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchRecovery", provider: ComplicationProvider()) { e in
            RecoveryComplicationView(s: e.snapshot).containerBackground(.clear, for: .widget).widgetURL(URL(string: "healthdashboard://recovery"))
        }
        .configurationDisplayName("Recovery")
        .description("Today’s recovery score.")
        .supportedFamilies(allFamilies)
    }
}

// MARK: Caffeine

struct CaffeineComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var s: WidgetSnapshot

    var body: some View {
        let mg = Int(s.caffeineToday)
        switch family {
        case .accessoryCorner:
            Image(systemName: "cup.and.saucer.fill").font(.title3).foregroundStyle(coffee).widgetAccentable()
                .widgetLabel("\(mg) mg")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill").font(.title2).foregroundStyle(coffee).widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(mg) mg today").font(.headline)
                    Text(s.caffeineAtBed.map { "~\(Int($0)) mg left at bedtime" } ?? "Tap to log a latte").font(.caption)
                    Text("Cutoff 2pm").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Label("\(mg) mg caffeine", systemImage: "cup.and.saucer.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 15)).foregroundStyle(coffee).widgetAccentable()
                    Text("\(mg)").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("MG").font(.system(size: 8, weight: .bold))
                }
            }
        }
    }
}

struct CaffeineComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchLatte", provider: ComplicationProvider()) { e in
            CaffeineComplicationView(s: e.snapshot).containerBackground(.clear, for: .widget).widgetURL(URL(string: "healthdashboard://log"))
        }
        .configurationDisplayName("Caffeine")
        .description("Caffeine today. Tap to log a latte.")
        .supportedFamilies(allFamilies)
    }
}

// MARK: Water

struct WaterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var s: WidgetSnapshot

    var body: some View {
        let done = s.waterToday, goal = max(1, s.waterGoal)
        let text = done.formatted(.number.precision(.fractionLength(0...1)))
        switch family {
        case .accessoryCorner:
            Image(systemName: "drop.fill").font(.title3).foregroundStyle(water).widgetAccentable()
                .widgetLabel { Gauge(value: min(done, goal), in: 0...goal) { Text("Water") }.tint(water) }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Gauge(value: min(done, goal), in: 0...goal) { Image(systemName: "drop.fill") } currentValueLabel: { Text(text) }
                    .gaugeStyle(.accessoryCircularCapacity).tint(water)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Water").font(.headline).widgetAccentable()
                    Text("\(text) of \(goal.formatted(.number.precision(.fractionLength(0...1)))) bottles").font(.caption)
                }
            }
        case .accessoryInline:
            Label("\(text) of \(goal.formatted(.number.precision(.fractionLength(0...1)))) bottles", systemImage: "drop.fill")
        default:
            Gauge(value: min(done, goal), in: 0...goal) { Image(systemName: "drop.fill") } currentValueLabel: { Text(text) }
                .gaugeStyle(.accessoryCircularCapacity).tint(water)
        }
    }
}

struct WaterComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchWater", provider: ComplicationProvider()) { e in
            WaterComplicationView(s: e.snapshot).containerBackground(.clear, for: .widget).widgetURL(URL(string: "healthdashboard://water"))
        }
        .configurationDisplayName("Water")
        .description("Bottles today. Tap to add one.")
        .supportedFamilies(allFamilies)
    }
}

// MARK: Cycle

struct CycleComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var s: WidgetSnapshot

    var body: some View {
        let day = s.cycleDay, length = Double(s.typicalLength ?? 28)
        switch family {
        case .accessoryCorner:
            Text(day.map { "D\($0)" } ?? "–").font(.system(size: 18, weight: .bold, design: .rounded)).widgetAccentable()
                .widgetLabel(s.phase ?? "Cycle")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Gauge(value: Double(day ?? 0), in: 0...length) { EmptyView() } currentValueLabel: { Text(day.map(String.init) ?? "–") }
                    .gaugeStyle(.accessoryCircularCapacity).tint(rose)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.phase ?? "Cycle").font(.headline).widgetAccentable()
                    Text(s.daysToPeriod.map { $0 > 0 ? "Period in \($0) days" : $0 == 0 ? "Period expected today" : "Log your period" } ?? "Day \(day ?? 0)").font(.caption)
                }
            }
        case .accessoryInline:
            Label("Day \(day.map(String.init) ?? "–")\(s.phase.map { " · \($0)" } ?? "")", systemImage: "circle.dashed")
        default:
            Gauge(value: Double(day ?? 0), in: 0...length) { Text("DAY") } currentValueLabel: { Text(day.map(String.init) ?? "–") }
                .gaugeStyle(.accessoryCircular).tint(rose)
        }
    }
}

struct CycleComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchCycle", provider: ComplicationProvider()) { e in
            CycleComplicationView(s: e.snapshot).containerBackground(.clear, for: .widget).widgetURL(URL(string: "healthdashboard://cycle"))
        }
        .configurationDisplayName("Cycle day")
        .description("Cycle day and phase, or pill-pack day.")
        .supportedFamilies(allFamilies)
    }
}

// MARK: Bedtime and energy

struct BedtimeComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var s: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "moon.stars.fill").font(.title3).foregroundStyle(night).widgetAccentable()
                .widgetLabel("Bed \(s.bedShort)")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill").font(.title2).foregroundStyle(night).widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bed by \(s.bedShort)").font(.headline)
                    Text(s.examNote ?? (s.energy.map { "Energy \($0)%" } ?? "Tonight")).font(.caption).lineLimit(2)
                }
            }
        case .accessoryInline:
            Label("Bed by \(s.bedShort)", systemImage: "moon.stars.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 13)).foregroundStyle(night).widgetAccentable()
                    Text(s.bedShort).font(.system(size: 14, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                }
            }
        }
    }
}

struct BedtimeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchBedtime", provider: ComplicationProvider()) { e in
            BedtimeComplicationView(s: e.snapshot).containerBackground(.clear, for: .widget).widgetURL(URL(string: "healthdashboard://tonight"))
        }
        .configurationDisplayName("Bedtime")
        .description("When to be asleep tonight.")
        .supportedFamilies(allFamilies)
    }
}

struct EnergyComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var s: WidgetSnapshot

    var body: some View {
        let energy = s.isFromToday ? s.energy : nil
        switch family {
        case .accessoryCorner:
            Image(systemName: "bolt.fill").font(.title3).foregroundStyle(mint).widgetAccentable()
                .widgetLabel { Gauge(value: Double(energy ?? 0), in: 0...100) { Text("Energy") }.tint(mint) }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label("Energy", systemImage: "bolt.fill").font(.headline).widgetAccentable()
                    Spacer()
                    Text(energy.map { "\($0)%" } ?? "–").font(.headline)
                }
                Gauge(value: Double(energy ?? 0), in: 0...100) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).tint(mint)
                Text("ENERGY · BED BY · CYCLE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                Text("\(energy.map { "\($0)%" } ?? "–")  ·  \(s.bedShort)  ·  \(s.cycleDay.map { "D\($0)" } ?? "–")").font(.caption)
            }
        case .accessoryInline:
            Label("Energy \(energy.map { "\($0)%" } ?? "–")", systemImage: "bolt.fill")
        default:
            Gauge(value: Double(energy ?? 0), in: 0...100) { Image(systemName: "bolt.fill") } currentValueLabel: { Text(energy.map(String.init) ?? "–") }
                .gaugeStyle(.accessoryCircular).tint(mint)
        }
    }
}

struct EnergyComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchToday", provider: ComplicationProvider()) { e in
            EnergyComplicationView(s: e.snapshot).containerBackground(.clear, for: .widget).widgetURL(URL(string: "healthdashboard://recovery"))
        }
        .configurationDisplayName("Energy")
        .description("Energy left today, plus bedtime and cycle day.")
        .supportedFamilies(allFamilies)
    }
}

// MARK: Smart alarm

struct AlarmEntry: TimelineEntry {
    var date: Date
    var status: WatchAlarmStatus?
}

/// Redraws when the Watch app saves a new status, and again once the alarm time has passed.
struct AlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlarmEntry { AlarmEntry(date: .now, status: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (AlarmEntry) -> Void) {
        completion(AlarmEntry(date: .now, status: context.isPreview ? .preview : WatchAlarmStatus.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AlarmEntry>) -> Void) {
        let status = WatchAlarmStatus.load()
        var entries = [AlarmEntry(date: .now, status: status)]
        if let latest = status?.latest, latest > .now { entries.append(AlarmEntry(date: latest.addingTimeInterval(60), status: status)) }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(3600))))
    }
}

extension WatchAlarmStatus {
    static var preview: WatchAlarmStatus {
        WatchAlarmStatus(state: .armed, latest: .now.addingTimeInterval(9 * 3600), plan: SmartAlarmPlan(latest: 465))
    }
}

struct AlarmComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var status: WatchAlarmStatus?

    var body: some View {
        let set = status?.isSet ?? false
        // Needs opening: a plan that the Watch hasn't been able to schedule yet.
        let needsApp = !set && status?.plan != nil
        let time = status?.plan.map { $0.latestText.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "") }
        let icon = needsApp ? "alarm.waves.left.and.right" : "alarm.fill"
        switch family {
        case .accessoryCorner:
            Image(systemName: icon).font(.title3).foregroundStyle(alarm).widgetAccentable()
                .widgetLabel(set ? (time ?? "On") : needsApp ? "Open app" : "Off")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Smart alarm", systemImage: icon).font(.headline).foregroundStyle(alarm).widgetAccentable()
                if set, let plan = status?.plan {
                    Text("Up by \(plan.latestText)").font(.body.weight(.semibold))
                    Text("Set · from \(SmartAlarmPlan(latest: plan.latest - plan.window).latestText)").font(.caption2).foregroundStyle(.secondary)
                } else if needsApp {
                    Text("Not set yet").font(.body.weight(.semibold))
                    Text("Tap to open and set it").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Off").font(.body.weight(.semibold))
                    Text("Tap to set one").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Label(set ? "Alarm \(time ?? "on")" : needsApp ? "Alarm needs app" : "Alarm off", systemImage: icon)
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(alarm).widgetAccentable()
                    Text(set ? (time ?? "On") : needsApp ? "!" : "Off").font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }
}

struct AlarmComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchSmartAlarm", provider: AlarmProvider()) { e in
            AlarmComplicationView(status: e.status).containerBackground(.clear, for: .widget).widgetURL(URL(string: "healthdashboard://alarm"))
        }
        .configurationDisplayName("Smart alarm")
        .description("Whether tomorrow’s alarm is set, and for when.")
        .supportedFamilies(allFamilies)
    }
}

@main
struct WatchComplications: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
        CaffeineComplication()
        WaterComplication()
        CycleComplication()
        BedtimeComplication()
        EnergyComplication()
        AlarmComplication()
    }
}
