import WidgetKit
import SwiftUI

/// Home Screen and Lock Screen widgets. They show the last numbers the app
/// saved (`WidgetSnapshot`): recovery, cycle, today's caffeine and water, and
/// the bedtime streak. Example data is always labelled.
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

    /// Now, plus the moment the app day rolls over (caffeine and water go
    /// back to 0). The app reloads the widgets whenever its numbers change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        var dates: [Date] = [.now]
        if let s = snap {
            let rollover = s.appDayStart.addingTimeInterval(24 * 3600)
            if rollover > .now { dates.append(rollover) }
        }
        completion(Timeline(entries: dates.map { SnapshotEntry(date: $0, snapshot: snap) },
                            policy: .after(.now.addingTimeInterval(3600))))
    }
}

// MARK: - Shared pieces

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
            Spacer(minLength: 2)
            if snapshot.isSample {
                Text("Example")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Accent.yellow.ink(scheme))
                    .accessibilityLabel("Example data")
            }
        }
    }
}

/// "As of 7:22pm", so old numbers never pass as current.
private struct AsOf: View {
    let snapshot: WidgetSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text("As of \(snapshot.updated.formatted(date: .omitted, time: .shortened).lowercased())")
            .font(.system(size: 10))
            .foregroundStyle(Palette(scheme: scheme).tertiary)
    }
}

private struct OpenAppPrompt: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.text.square")
                .font(.title2)
            Text("Open Health Next to see your numbers")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

private func ounces(_ ml: Double) -> String {
    let oz = ml / 29.5735
    return oz >= 10 ? "\(Int(oz.rounded())) oz" : String(format: "%.1f oz", oz)
}

private func shortTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened).lowercased().replacingOccurrences(of: ":00", with: "")
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
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(s.recovery ?? 0), in: 0...100) {
                    Text("Rec")
                } currentValueLabel: {
                    Text(s.recovery.map(String.init) ?? "\u{2014}")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .accessibilityLabel(recoverySentence(s))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recovery\(s.isSample ? " \u{00B7} Example" : "")").font(.caption2.weight(.semibold))
                    Text(s.recovery.map { "\($0) \u{00B7} \(s.recoveryLabel)" } ?? "No reading yet")
                        .font(.headline)
                    if let e = s.energyLeft { Text("Energy left \(e)%").font(.caption2) }
                }
                .accessibilityElement(children: .combine)
            case .accessoryInline:
                Text(s.recovery.map { "Recovery \($0) \u{00B7} \(s.recoveryLabel)" } ?? "Recovery: no reading yet")
            default:
                let p = Palette(scheme: scheme)
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Recovery", accent: .indigo, snapshot: s)
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle().stroke(p.track, lineWidth: 7)
                            Circle().trim(from: 0, to: Double(s.recovery ?? 0) / 100)
                                .stroke(Accent.indigo.fill(scheme), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(s.recovery.map(String.init) ?? "\u{2014}")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                        if family == .systemMedium { details(s) }
                    }
                    if family != .systemMedium {
                        Text(s.recovery == nil ? "No reading yet" : s.recoveryLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    AsOf(snapshot: s)
                }
                .foregroundStyle(p.primary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(recoverySentence(s))
            }
        } else {
            OpenAppPrompt()
        }
    }

    private func details(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.recovery == nil ? "No reading yet" : s.recoveryLabel)
                .font(.system(size: 15, weight: .semibold))
            if let e = s.energyLeft {
                Label("Energy left \(e)%", systemImage: "bolt.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Accent.yellow.ink(scheme))
            }
            if let line = s.cycleLine {
                Text(line).font(.system(size: 12)).foregroundStyle(Palette(scheme: scheme).secondary).lineLimit(1)
            }
        }
    }

    private func recoverySentence(_ s: WidgetSnapshot) -> String {
        var parts = [s.recovery.map { "Recovery \($0) out of 100, \(s.recoveryLabel)" } ?? "Recovery: no reading yet"]
        if let e = s.energyLeft { parts.append("energy left \(e) percent") }
        if s.isSample { parts.append("example data") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Cycle

struct CycleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Cycle", provider: SnapshotProvider()) { entry in
            CycleWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground(accent: .purple) }
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
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(s.cycleNumber.map(String.init) ?? "\u{2014}").font(.title2.weight(.bold))
                    Text(s.cycleNumberLabel ?? "Cycle").font(.caption2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(s.cycleLine ?? "Not tracking a cycle")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cycle").font(.caption2.weight(.semibold))
                    Text(s.cycleLine ?? "Not tracking a cycle").font(.headline).lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            default:
                let p = Palette(scheme: scheme)
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Cycle", accent: .purple, snapshot: s)
                    if let n = s.cycleNumber {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(s.cycleNumberLabel ?? "Day").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(p.secondary)
                            Text("\(n)").font(.system(size: 34, weight: .bold, design: .rounded))
                        }
                    }
                    Text(s.cycleLine ?? "Not tracking a cycle")
                        .font(.system(size: 13))
                        .foregroundStyle(p.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    AsOf(snapshot: s)
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
        .description("Today's caffeine, your cutoff, and water in ounces.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let s = entry.snapshot {
            let mg = s.caffeineMg(at: entry.date)
            let water = s.waterML(at: entry.date)
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(mg) mg caffeine").font(.headline)
                    Text(s.caffeineNote).font(.caption2)
                    Text("\(ounces(water)) of \(ounces(s.waterGoalML)) water").font(.caption2)
                }
                .accessibilityElement(children: .combine)
            } else {
                let p = Palette(scheme: scheme)
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Today", accent: .yellow, snapshot: s)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(mg)").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("mg").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.secondary)
                    }
                    Text(s.caffeineNote).font(.system(size: 12)).foregroundStyle(p.secondary).lineLimit(1)
                    ProgressView(value: min(water / max(s.waterGoalML, 1), 1))
                        .tint(Accent.blue.fill(scheme))
                    Text("\(ounces(water)) of \(ounces(s.waterGoalML))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Accent.blue.ink(scheme))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(p.primary)
                .accessibilityElement(children: .combine)
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
                    Text("\(s.bedtimeStreak)").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(s.bedtimeStreak == 1 ? "night" : "nights").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.secondary)
                }
                if let bed = s.bedtime {
                    Label("Bed by \(shortTime(bed))", systemImage: "moon.fill")
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
