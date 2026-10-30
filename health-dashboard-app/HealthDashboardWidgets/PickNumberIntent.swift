import AppIntents
import WidgetKit

/// What the Recovery widget shows (D-W7): touch and hold, Edit Widget, and
/// pick Recovery, Energy, Sleep debt or Water. One widget slot can follow
/// whichever number she cares about this month.
enum WidgetNumber: String, AppEnum {
    case recovery, energy, sleepDebt, water

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Number"
    static let caseDisplayRepresentations: [WidgetNumber: DisplayRepresentation] = [
        .recovery: "Recovery",
        .energy: "Energy",
        .sleepDebt: "Sleep debt",
        .water: "Water",
    ]
}

struct PickNumberIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Pick a number"
    static let description = IntentDescription("Choose what this widget shows.")

    @Parameter(title: "Show", default: .recovery)
    var number: WidgetNumber
}

struct PickedEntry: TimelineEntry {
    let date: Date
    /// nil until the app has run once.
    let snapshot: WidgetSnapshot?
    let number: WidgetNumber
}

/// The same moments as the other widgets (now, six hours old, the app-day
/// rollover), plus each move of the "now" dot when it shows Energy.
struct PickedProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PickedEntry {
        PickedEntry(date: .now, snapshot: .example, number: .recovery)
    }

    func snapshot(for configuration: PickNumberIntent, in context: Context) async -> PickedEntry {
        PickedEntry(date: .now, snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .example) : WidgetSnapshot.load(),
                    number: configuration.number)
    }

    func timeline(for configuration: PickNumberIntent, in context: Context) async -> Timeline<PickedEntry> {
        let snap = WidgetSnapshot.load()
        let now = Date.now
        var dates: [Date] = [now]
        if let s = snap {
            let rollover = s.appDayStart.addingTimeInterval(24 * 3600)
            dates += [rollover, s.updated.addingTimeInterval(6 * 3600)]
            if configuration.number == .energy, let e = s.energy(at: now) {
                dates += e.moves(after: now).filter { $0 < rollover }
            }
        }
        let entries = Set(dates.filter { $0 >= now }).sorted()
            .map { PickedEntry(date: $0, snapshot: snap, number: configuration.number) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600)))
    }
}
