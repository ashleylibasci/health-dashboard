import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: .now, snapshot: WidgetSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(Timeline(entries: [ComplicationEntry(date: .now, snapshot: WidgetSnapshot.load())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

/// Recovery as a ring, from the canvas's watch face.
struct RecoveryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchRecovery", provider: ComplicationProvider()) { entry in
            Gauge(value: Double(entry.snapshot.recovery ?? 0), in: 0...100) { Text("REC") } currentValueLabel: {
                Text(entry.snapshot.recovery.map(String.init) ?? "–")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Color.main)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Recovery")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// Opens the app's Log page for a one-tap latte.
struct LatteComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchLatte", provider: ComplicationProvider()) { _ in
            VStack(spacing: 0) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 18))
                Text("LATTE").font(.system(size: 9, weight: .bold))
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Log a latte")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Energy, bedtime and cycle day in one line, like the bottom of the canvas face.
struct TodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchToday", provider: ComplicationProvider()) { entry in
            let s = entry.snapshot
            HStack(spacing: 10) {
                item("ENERGY", s.energy.map { "\($0)%" } ?? "–")
                item("BED BY", s.bedBy?.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "") ?? "–")
                if let d = s.cycleDay { item("CYCLE", "D\(d)") }
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Today")
        .supportedFamilies([.accessoryRectangular])
    }

    private func item(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
        }
    }
}

@main
struct WatchComplications: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
        TodayComplication()
        LatteComplication()
    }
}
