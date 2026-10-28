import WidgetKit
import SwiftUI

/// Watch-face complications: recovery, cycle, caffeine & water, and tonight's
/// bedtime. They show the numbers the iPhone last sent (`WidgetSnapshot`),
/// say "Ex" for example data, and open the matching Watch page when tapped.
@main
struct HealthNextComplications: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
        CycleComplication()
        CaffeineComplication()
        BedtimeComplication()
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: .now, snapshot: .example) }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .example) : WidgetSnapshot.load()))
    }

    /// Now, and the app-day rollover (caffeine goes back to 0). New numbers
    /// from the phone reload the timeline themselves.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        var dates: [Date] = [.now]
        if let s = snap {
            let rollover = s.appDayStart.addingTimeInterval(24 * 3600)
            if rollover > .now { dates.append(rollover) }
        }
        completion(Timeline(entries: dates.map { ComplicationEntry(date: $0, snapshot: snap) },
                            policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

/// Opens the Watch app on a page (0 Recovery, 1 Energy, 2 Tonight, 3 Log).
private func page(_ n: Int) -> URL { URL(string: "healthnext://page/\(n)")! }

private let families: [WidgetFamily] = [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]

private func sampleTag(_ s: WidgetSnapshot) -> String { s.isSample ? " \u{00B7} Ex" : "" }

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
        let value = s?.recovery
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(value ?? 0), in: 0...100) {
                Text("REC")
            } currentValueLabel: {
                Text(value.map(String.init) ?? "\u{2014}")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Accent.indigo.fill(.dark))
            .accessibilityLabel(value.map { "Recovery \($0)" } ?? "Recovery, no reading yet")
        case .accessoryCorner:
            Text(value.map(String.init) ?? "\u{2014}")
                .font(.title3.weight(.bold))
                .widgetLabel {
                    Gauge(value: Double(value ?? 0), in: 0...100) { Text("Recovery") }
                        .tint(Accent.indigo.fill(.dark))
                }
                .accessibilityLabel(value.map { "Recovery \($0)" } ?? "Recovery, no reading yet")
        case .accessoryInline:
            Text(s.flatMap { snap in snap.recovery.map { "Recovery \($0) \u{00B7} \(snap.recoveryLabel)" } } ?? "Recovery: no reading yet")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("Recovery\(s.map(sampleTag) ?? "")").font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.indigo.ink(.dark))
                Text(s.flatMap { snap in snap.recovery.map { "\($0) \u{00B7} \(snap.recoveryLabel)" } } ?? "No reading yet")
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                if let e = s?.energyLeft { Text("Energy left \(e)%").font(.caption2) }
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
        let number = s?.cycleNumber.map(String.init) ?? "\u{2014}"
        let label = s?.cycleNumberLabel ?? "Cycle"
        switch family {
        case .accessoryCircular:
            VStack(spacing: -2) {
                Text(number).font(.title3.weight(.bold))
                Text(label).font(.system(size: 10, weight: .semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(s?.cycleLine ?? "Not tracking a cycle")
        case .accessoryCorner:
            Image(systemName: "drop.fill")
                .foregroundStyle(Accent.purple.fill(.dark))
                .widgetLabel("\(label) \(number)")
                .accessibilityLabel(s?.cycleLine ?? "Not tracking a cycle")
        case .accessoryInline:
            Text(s?.cycleLine ?? "Not tracking a cycle")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("Cycle\(s.map(sampleTag) ?? "")").font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.purple.ink(.dark))
                Text(s?.cycleLine ?? "Not tracking a cycle").font(.headline).lineLimit(2).minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
        }
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
        let mg = s?.caffeineMg(at: entry.date) ?? 0
        let water = s?.waterML(at: entry.date) ?? 0
        switch family {
        case .accessoryCircular:
            VStack(spacing: -2) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 11))
                Text("\(mg)").font(.title3.weight(.bold)).minimumScaleFactor(0.6)
                Text("mg").font(.system(size: 10, weight: .semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(mg) milligrams of caffeine today")
        case .accessoryCorner:
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(Accent.yellow.fill(.dark))
                .widgetLabel("\(mg) mg")
                .accessibilityLabel("\(mg) milligrams of caffeine today")
        case .accessoryInline:
            Text("\(mg) mg \u{00B7} \(oz(water)) water")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("Today\(s.map(sampleTag) ?? "")").font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.yellow.ink(.dark))
                Text("\(mg) mg caffeine").font(.headline)
                Text(s?.showsWaterGoal == true ? "\(oz(water)) of \(oz(s?.waterGoalML ?? 0)) water" : "\(oz(water)) water").font(.caption2)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Bedtime

struct BedtimeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchBedtime", provider: ComplicationProvider()) { entry in
            BedtimeComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(page(2))
        }
        .configurationDisplayName("Bedtime")
        .description("Tonight's bedtime and your on-time streak.")
        .supportedFamilies(families)
    }
}

private struct BedtimeComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    private func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened).lowercased().replacingOccurrences(of: ":00", with: "")
    }

    var body: some View {
        let s = entry.snapshot
        let bed = s?.bedtime.map(time) ?? "\u{2014}"
        switch family {
        case .accessoryCircular:
            VStack(spacing: -1) {
                Image(systemName: "moon.fill").font(.system(size: 12)).foregroundStyle(Accent.purple.fill(.dark))
                Text(bed).font(.system(size: 13, weight: .bold)).minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bed by \(bed)")
        case .accessoryCorner:
            Image(systemName: "moon.fill")
                .foregroundStyle(Accent.purple.fill(.dark))
                .widgetLabel("Bed \(bed)")
                .accessibilityLabel("Bed by \(bed)")
        case .accessoryInline:
            Text("Bed by \(bed)")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("Tonight\(s.map(sampleTag) ?? "")").font(.caption2.weight(.semibold))
                    .foregroundStyle(Accent.purple.ink(.dark))
                Text("Bed by \(bed)").font(.headline)
                if let n = s?.bedtimeStreak { Text("On time \(n) night\(n == 1 ? "" : "s") in a row").font(.caption2) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
