import SwiftUI
import Charts
import HealthCore

/// Drinks and your body: log alcohol, see what your own nights show the
/// morning after, and edit what you've logged. No judgment.
struct DrinksView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var kind = "Wine"
    @State private var count = 1
    @State private var time: LogTime = .now
    @State private var editing: AppData.AlcoholEntry?
    @State private var selected: Int?
    @State private var lastLogged: String?
    @State private var logCount = 0
    /// When the Log button last fired, so a double tap doesn't log twice.
    @State private var lastLogTap: Date?

    static let kinds = ["Wine", "Beer", "Seltzer", "Cocktail", "Shot"]

    /// "1 glass of wine", "2 beers", "3 shots".
    static func phrase(count: Int, kind: String) -> String {
        let one = count == 1
        switch kind {
        case "Wine": return "\(count) glass\(one ? "" : "es") of wine"
        case "Beer": return "\(count) beer\(one ? "" : "s")"
        case "Seltzer": return "\(count) seltzer\(one ? "" : "s")"
        case "Cocktail": return "\(count) cocktail\(one ? "" : "s")"
        case "Shot": return "\(count) shot\(one ? "" : "s")"
        default: return "\(count) \(kind.lowercased())"
        }
    }

    static func symbol(for kind: String) -> String {
        switch kind {
        case "Wine": return "wineglass.fill"
        case "Beer": return "mug.fill"
        case "Seltzer": return "bubbles.and.sparkles.fill"
        case "Cocktail": return "wineglass"
        default: return "drop.fill"
        }
    }

    var body: some View {
        Screen(title: "Drinks", accent: .purple) {
            SampleDataBanner()
            header
            logCard
            effectCard
            nightsCard
            recentCard
            tipsCard
            HowWeGotThisLink(title: "Drinks and your body",
                             method: "We take the nights that followed an evening when you logged drinks (anything from 5pm to 5am, so each drink counts for one night only) and compare them with your other nights: how long you slept, your HRV and resting heart rate the next morning compared with your usual, and your morning check-in. We need at least \(HabitEffect.minimumNights) nights of each before showing a result, and it gets more reliable as nights add up.")
        }
        .sheet(item: $editing) { entry in
            AlcoholEntryEditor(entry: entry)
                .environmentObject(model)
                .environmentObject(store)
        }
        .sensoryFeedback(.success, trigger: logCount)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("Drinks and your body").font(.scaled(size: 28, weight: .bold)).accessibilityAddTraits(.isHeader)
                InfoButton(topic: .alcohol)
            }
            Text("No judgment, just what your own data shows the morning after.")
                .font(.scaled(size: 15)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: Log

    private func logDrinks() {
        if let last = lastLogTap, Date.now.timeIntervalSince(last) < 1.5 { return }
        lastLogTap = .now
        let date = min(time.date, .now)
        store.data.alcoholLog.append(AppData.AlcoholEntry(date: date, kind: kind, count: count))
        lastLogged = LogFormat.loggedLine(Self.phrase(count: count, kind: kind), at: date)
        time = .now
        count = 1
        logCount += 1
    }

    private var logCard: some View {
        Card(accent: .purple) {
            Text("Log drinks").font(.scaled(size: 17, weight: .bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.kinds, id: \.self) { k in
                        kindChip(k)
                    }
                }
            }
            HStack(spacing: 12) {
                Text("How many").font(.scaled(size: 15, weight: .semibold))
                Spacer()
                countButton("minus", label: "One fewer") { count = max(1, count - 1) }
                Text("\(count)").font(.scaledNumber(24)).frame(minWidth: 32)
                    .accessibilityLabel(count == 1 ? "1 drink" : "\(count) drinks")
                countButton("plus", label: "One more") { count = min(15, count + 1) }
            }
            LogTimeSelector(time: $time, accent: .purple, title: "When?")
            PrimaryButton(title: "Log \(Self.phrase(count: count, kind: kind))", accent: .purple, action: logDrinks)
            if let lastLogged {
                Label(lastLogged, systemImage: "checkmark.circle.fill")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.mint.ink(scheme))
            }
        }
    }

    private func kindChip(_ k: String) -> some View {
        let p = Palette(scheme: scheme)
        let on = kind == k
        return Button { kind = k } label: {
            Label(k, systemImage: Self.symbol(for: k))
                .font(.scaled(size: 14, weight: .bold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(on ? Color(hex: 0x14002E) : p.primary)
                .background(on ? Accent.purple.fill(scheme) : p.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Accent.purple.fill(scheme) : p.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func countButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.scaled(size: 16, weight: .bold))
                .foregroundStyle(Accent.purple.ink(scheme))
                .frame(width: 44, height: 44)
                .background(Accent.purple.fill(scheme).opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Effect

    private var effect: HabitEffect { model.alcoholEffect }

    /// "After drinks you sleep 25 min less, your HRV is 12% lower and you feel worse the next morning."
    private var effectSentence: String {
        let e = effect
        var parts: [String] = []
        if abs(e.asleepDelta) < 5 { parts.append("you sleep about the same") }
        else { parts.append("you sleep \(Clock.duration(abs(e.asleepDelta))) \(e.asleepDelta < 0 ? "less" : "more")") }
        if let h = e.hrvDeltaPct, abs(h) >= 2 {
            parts.append("your HRV is \(Int(abs(h).rounded()))% \(h < 0 ? "lower" : "higher")")
        }
        if let r = e.restingHRDelta, abs(r) >= 1 {
            parts.append("your resting heart rate is \(Int(abs(r).rounded())) bpm \(r > 0 ? "higher" : "lower")")
        }
        if let c = e.checkInDelta {
            if c <= -0.3 { parts.append("you feel worse the next morning") }
            else if c >= 0.3 { parts.append("you feel better the next morning") }
            else { parts.append("you feel about the same the next morning") }
        }
        let joined: String
        if parts.count > 1 {
            joined = parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
        } else {
            joined = parts.first ?? ""
        }
        return "After drinks \(joined)."
    }

    private var effectCard: some View {
        Card {
            HStack {
                Text("After drinks").font(.scaled(size: 17, weight: .bold))
                if model.usingSampleData { ExampleTag() }
                Spacer()
                Text("\(effect.withCount) night\(effect.withCount == 1 ? "" : "s")")
                    .font(.scaled(size: 13, weight: .bold))
                    .foregroundStyle(Accent.purple.ink(scheme))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Accent.purple.fill(scheme).opacity(0.18), in: Capsule())
            }
            if effect.enoughData {
                Text(effectSentence).font(.scaled(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    EffectTile(title: "Sleep", value: signed(effect.asleepDelta, unit: " min"),
                               good: abs(effect.asleepDelta) < 10 ? nil : effect.asleepDelta > 0,
                               explanation: Explanation(id: "drinkSleep", title: "Sleep after drinks",
                                                        meaning: "How much longer or shorter you slept after drinks than on your other nights.",
                                                        forYou: "Alcohol often helps you fall asleep, then wakes you more in the second half of the night."))
                    if let h = effect.hrvDeltaPct {
                        EffectTile(title: "HRV", value: signed(Int(h.rounded()), unit: "%"), good: abs(h) < 3 ? nil : h > 0,
                                   explanation: Topic.hrv.explanation)
                    }
                    if let r = effect.restingHRDelta {
                        EffectTile(title: "Resting HR", value: signed(Int(r.rounded()), unit: " bpm"), good: abs(r) < 1 ? nil : r < 0,
                                   explanation: Topic.restingHR.explanation)
                    }
                    if let c = effect.checkInDelta {
                        EffectTile(title: "Morning feel", value: String(format: "%+.1f of 5", c), good: abs(c) < 0.3 ? nil : c > 0,
                                   explanation: Explanation(id: "drinkFeel", title: "How you felt",
                                                            meaning: "Your morning check-in (1 to 5) after drinks compared with other mornings.",
                                                            forYou: "Below zero means you felt less awake than usual the morning after."))
                    }
                }
                Text("From \(effect.withCount) night\(effect.withCount == 1 ? "" : "s") after drinks, compared with \(effect.withoutCount) without." + cycleNote)
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not enough nights yet").font(.scaled(size: 16, weight: .semibold))
                Text("You have \(effect.withCount) night\(effect.withCount == 1 ? "" : "s") after drinks and \(effect.withoutCount) without. We need at least \(HabitEffect.minimumNights) of each to compare fairly. If you have drinks, log them and wear your Watch to bed; the comparison fills in over time. There\u{2019}s no need to drink to get there.")
                    .font(.scaled(size: 14)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The comparison mixes all nights, so cycle changes are in it too.
    private var cycleNote: String {
        if case .phases = model.cycleDisplay {
            return " It doesn\u{2019}t separate out your cycle, so the week before your period (lighter sleep, lower HRV) can be mixed in."
        }
        return ""
    }

    private func signed(_ v: Int, unit: String) -> String {
        v > 0 ? "+\(v)\(unit)" : v < 0 ? "\u{2212}\(abs(v))\(unit)" : "0\(unit)"
    }

    // MARK: Recent nights chart

    private var points: [DrinkNightPoint] { model.recentDrinkNights(14) }

    private var selectedPoint: DrinkNightPoint? {
        guard let i = selected else { return nil }
        return points.min { abs($0.index - i) < abs($1.index - i) }
    }

    private var nightsReadout: (title: String, value: String, detail: String) {
        guard let p = selectedPoint else {
            let drink = points.filter(\.afterDrinks)
            let other = points.filter { !$0.afterDrinks }
            let a = drink.isEmpty ? 0 : drink.map(\.asleep).reduce(0, +) / drink.count
            let b = other.isEmpty ? 0 : other.map(\.asleep).reduce(0, +) / other.count
            let detail = drink.isEmpty
                ? "No nights after drinks in the last two weeks."
                : "Average sleep \(Clock.duration(a)) after drinks vs \(Clock.duration(b)) on other nights."
            return ("Last \(points.count) nights", "\(drink.count) after drinks", detail)
        }
        let day = p.night.wakeDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        var detail = p.afterDrinks ? "After drinks\(p.drinksText.map { " (\($0))" } ?? "")." : "No drinks the evening before."
        if let h = p.night.outcome.hrvDeltaPct {
            detail += " HRV \(Int(abs(h).rounded()))% \(h < 0 ? "below" : "above") your usual."
        }
        if let c = p.night.outcome.checkIn { detail += " You felt \(Int(c)) of 5." }
        return ("Night before \(day)", "\(Clock.duration(p.asleep)) asleep", detail)
    }

    private var nightsCard: some View {
        Card(accent: .purple) {
            HStack {
                Text("Your recent nights").font(.scaled(size: 15, weight: .bold))
                if model.usingSampleData { ExampleTag() }
            }
            let r = nightsReadout
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .purple)
                .frame(maxWidth: .infinity, alignment: .leading)
            DrinkNightsChart(points: points, selected: selectedPoint?.index, selection: $selected)
                .frame(height: 170)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hours asleep over the last \(points.count) nights. \(points.filter(\.afterDrinks).count) followed drinks.")
            ScrubHint()
            HStack(spacing: 14) {
                legend("After drinks", color: Self.drinkBar(scheme))
                legend("Other nights", color: Palette(scheme: scheme).tertiary)
            }
            .accessibilityHidden(true)
        }
    }

    nonisolated static func drinkBar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Accent.purple.fill(.dark) : Accent.purple.ink(.light)
    }

    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
        .font(.scaled(size: 12))
        .secondaryText()
    }

    // MARK: Recent entries

    private var recent: [AppData.AlcoholEntry] { model.recentAlcohol(days: 14) }

    private var recentCard: some View {
        Card {
            HStack {
                Text("Logged drinks").font(.scaled(size: 17, weight: .bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Last 2 weeks").font(.scaled(size: 13, weight: .semibold)).secondaryText()
            }
            if recent.isEmpty {
                Text("Nothing logged in the last two weeks.").font(.scaled(size: 14)).secondaryText()
            } else {
                LogEntryList(items: recent, onTap: { editing = $0 },
                             onDelete: { entry in store.data.alcoholLog.removeAll { $0.id == entry.id } }) { entry in
                    LogEntryRow(systemImage: Self.symbol(for: entry.kind), accent: .purple,
                                title: Self.phrase(count: entry.count, kind: entry.kind),
                                detail: entry.count == 1 ? "1 drink" : "\(entry.count) drinks",
                                time: LogFormat.time(entry.date))
                }
                Text("Tap an entry to change it. Swipe left to delete.")
                    .font(.scaled(size: 12)).secondaryText()
            }
        }
    }

    private var tipsCard: some View {
        Card(accent: .mint) {
            Label("What helps most", systemImage: "lightbulb.fill")
                .font(.scaled(size: 15, weight: .bold))
                .foregroundStyle(Accent.mint.ink(scheme))
            Text("Finish your last drink 3 or more hours before bed, and have a glass of water between drinks. Your body clears about one drink an hour.")
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "Water", subtitle: "Log a bottle", systemImage: "drop.fill", accent: .blue) {
                WaterView()
            }
        }
    }
}

// MARK: - Pieces

/// "Example" on cards that show the sample analysis, not hers.
struct ExampleTag: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("Example")
            .font(.scaled(size: 11, weight: .bold))
            .foregroundStyle(Accent.yellow.ink(scheme))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Accent.yellow.tint(scheme), in: Capsule())
            .accessibilityLabel("Example data")
    }
}

private struct EffectTile: View {
    var title: String
    var value: String
    /// Nil for a change too small to matter: no color, "about the same".
    var good: Bool?
    var explanation: Explanation
    @Environment(\.colorScheme) private var scheme

    private var verdict: String {
        switch good {
        case true?: return "Better"
        case false?: return "Worse"
        case nil: return "About the same"
        }
    }

    private var color: Color {
        switch good {
        case true?: return Accent.mint.ink(scheme)
        case false?: return Accent.coral.ink(scheme)
        case nil: return Palette(scheme: scheme).primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text(title.uppercased()).font(.scaled(size: 12, weight: .bold)).secondaryText()
                Spacer(minLength: 0)
                InfoButton(explanation: explanation).padding(.vertical, -12).padding(.trailing, -10)
            }
            Text(value).font(.scaledNumber(22))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            // In words too, so color is never the only cue.
            Text(verdict).font(.scaled(size: 12, weight: .semibold)).secondaryText()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DrinkNightsChart: View {
    let points: [DrinkNightPoint]
    let selected: Int?
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var scheme

    private func color(_ p: DrinkNightPoint) -> Color {
        // 3:1 or more against the card in both modes.
        let base = p.afterDrinks ? DrinksView.drinkBar(scheme) : Palette(scheme: scheme).tertiary
        guard let selected else { return base }
        return p.index == selected ? base : base.opacity(0.35)
    }

    private var tickIndices: [Int] { Array(stride(from: 0, to: points.count, by: 3)) }

    var body: some View {
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Night", p.index), y: .value("Hours", Double(p.asleep) / 60), width: .fixed(14))
                    .foregroundStyle(color(p))
                    .cornerRadius(4)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Palette(scheme: scheme).secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartScrub($selection)
        .chartXScale(domain: -1...max(points.count, 1))
        .chartYScale(domain: 0.0...10.0)
        .chartXAxis {
            AxisMarks(values: tickIndices) { value in
                AxisValueLabel {
                    if let i = value.as(Int.self), i >= 0, i < points.count {
                        Text(points[i].night.wakeDay.formatted(.dateTime.weekday(.abbreviated)))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 4.0, 8.0]) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let h = value.as(Double.self) { Text("\(Int(h))h") }
                }
            }
        }
    }
}

/// Edit a logged drink: kind, number and time (any day in the last two weeks).
private struct AlcoholEntryEditor: View {
    let entry: AppData.AlcoholEntry
    @EnvironmentObject var store: DataStore
    @State private var kind: String
    @Environment(\.colorScheme) private var scheme

    init(entry: AppData.AlcoholEntry) {
        self.entry = entry
        _kind = State(wrappedValue: entry.kind)
    }

    var body: some View {
        LogEditSheet(title: "Edit drinks", accent: .purple, date: entry.date, amount: Double(entry.count),
                     unit: "drink", pluralUnit: "drinks", step: 1, range: 1...15, showsDate: true,
                     onSave: { date, n in save(date: date, count: Int(n.rounded())) },
                     onDelete: { store.data.alcoholLog.removeAll { $0.id == entry.id } }) {
            Card {
                Text("Kind").font(.scaled(size: 15, weight: .bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DrinksView.kinds, id: \.self) { k in
                            Button { kind = k } label: {
                                Text(k)
                                    .font(.scaled(size: 14, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .foregroundStyle(kind == k ? Color(hex: 0x14002E) : Palette(scheme: scheme).primary)
                                    .background(kind == k ? Accent.purple.fill(scheme) : Palette(scheme: scheme).chip, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == k ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    private func save(date: Date, count: Int) {
        guard let i = store.data.alcoholLog.firstIndex(where: { $0.id == entry.id }) else { return }
        store.data.alcoholLog[i].date = min(date, .now)
        store.data.alcoholLog[i].count = max(1, count)
        store.data.alcoholLog[i].kind = kind
    }
}
