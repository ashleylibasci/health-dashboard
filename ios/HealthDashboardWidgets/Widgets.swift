import AppIntents
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app pushes fresh numbers whenever it reads Health. Between those, entries at midnight
        // and 5am make the day-based values (recovery, cycle day, today's caffeine) turn over on time.
        let snap = WidgetSnapshot.load()
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: .now.addingTimeInterval(86_400))
        let fiveAM = cal.nextDate(after: .now, matching: DateComponents(hour: 5, minute: 0), matchingPolicy: .nextTime)!
        let entries = [Date.now, midnight, fiveAM].sorted().map { SnapshotEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(3600))))
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.name = "Ashley"; s.recovery = 72; s.recoveryLabel = "Moderate"; s.headline = "Go easy today"
        s.cycleDay = 22; s.phase = "Luteal"; s.sleepMinutes = 430; s.bedBy = "12:15am"; s.energy = 58; s.streakNights = 6
        s.updated = .now
        return s
    }
}

private func hm(_ m: Int) -> String { "\(m / 60)h \(m % 60)m" }

// MARK: Recovery (medium, small, Lock Screen)

struct RecoveryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    /// After midnight, until the app refreshes, don't show yesterday's numbers as today's: recovery,
    /// energy and sleep go blank, the cycle day moves on with the calendar, and the phase and
    /// bedtime (which may have changed) are left out. `date` is when the entry shows.
    static func todayOnly(_ snap: WidgetSnapshot, at date: Date = .now) -> WidgetSnapshot {
        let cal = Calendar.current
        guard !cal.isDate(snap.updated, inSameDayAs: date) else { return snap }
        var s = snap
        s.recovery = nil; s.energy = nil; s.sleepMinutes = nil
        s.headline = s.updated == .distantPast ? "Open the app to get started" : "Open the app for today’s numbers"
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: snap.updated), to: cal.startOfDay(for: date)).day ?? 0
        if let d = snap.cycleDay, days > 0, days < 7 { s.cycleDay = d + days } else if days >= 7 { s.cycleDay = nil }
        s.phase = nil; s.bedBy = nil
        return s
    }

    var body: some View {
        let s = Self.todayOnly(entry.snapshot, at: entry.date)
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(s.recovery ?? 0), in: 0...100) { Text("RECOV") } currentValueLabel: { Text(s.recovery.map(String.init) ?? "–") }
                .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery \(s.recovery.map(String.init) ?? "–")").font(.headline)
                Text("Energy \(s.energy.map { "\($0)%" } ?? "–")").font(.caption)
                Gauge(value: Double(s.energy ?? 0), in: 0...100) { EmptyView() }.gaugeStyle(.accessoryLinear)
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Text("RECOVERY").font(.label).kerning(0.8).foregroundStyle(Color.mainText)
                WidgetRing(value: s.recovery, size: 70)
                Text(s.headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            HStack(spacing: 14) {
                WidgetRing(value: s.recovery, size: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.headline).font(.number(19)).foregroundStyle(Color.ink).lineLimit(2)
                    if let d = s.cycleDay, let p = s.phase {
                        HStack(spacing: 6) { Circle().fill(Color(hex: 0xC9CFFF)).frame(width: 10, height: 10); Text("Day \(d) · \(p)") }
                            .font(.system(size: 13)).foregroundStyle(Color.muted)
                    }
                    Text([s.sleepMinutes.map { "Sleep \(hm($0))" }, s.bedBy.map { "Bed by \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct WidgetRing: View {
    var value: Int?
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.lavender, lineWidth: size * 0.13)
            Circle().trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(Color.main, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(value.map(String.init) ?? "–").font(.number(size * 0.32)).foregroundStyle(Color.ink)
        }
        .frame(width: size, height: size)
    }
}

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Recovery", provider: SnapshotProvider()) { entry in
            RecoveryWidgetView(entry: entry).containerBackground(Color.surface, for: .widget)
        }
        .configurationDisplayName("Recovery")
        .description("Today’s recovery, cycle day, sleep and bedtime.")
        .supportedFamilies([.systemMedium, .systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: Cycle (Lock Screen)

struct CycleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Cycle", provider: SnapshotProvider()) { entry in
            VStack(spacing: 0) {
                Text(RecoveryWidgetView.todayOnly(entry.snapshot, at: entry.date).cycleDay.map { "D\($0)" } ?? "–").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("CYCLE").font(.system(size: 9, weight: .bold))
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Cycle day")
        .description("Your cycle day on the Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: Latte (interactive)

struct LatteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Latte", provider: SnapshotProvider()) { entry in
            Button(intent: LogLatteIntent()) {
                VStack(alignment: .leading) {
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 28)).foregroundStyle(Color.butterInk)
                    Spacer()
                    Text("+ Latte").font(.number(22)).foregroundStyle(Color.ink)
                    Text("Today \(Int(entry.snapshot.caffeine(at: entry.date))) mg · cutoff 2pm").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.butterInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .containerBackground(Color.butter, for: .widget)
        }
        .configurationDisplayName("Log a latte")
        .description("Tap to save a 130 mg latte to Apple Health.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: Streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading) {
                Text("STREAK").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.muted)
                Spacer()
                Text("\(entry.snapshot.streakNights)").font(.number(40)).foregroundStyle(Color.ink)
                Text("nights by \(entry.snapshot.bedBy ?? "bedtime")").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.mainText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(Color.surface, for: .widget)
        }
        .configurationDisplayName("Bedtime streak")
        .description("Nights in a row asleep by your bedtime.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct HealthDashboardWidgets: WidgetBundle {
    var body: some Widget {
        RecoveryWidget()
        LatteWidget()
        StreakWidget()
        CycleWidget()
    }
}
