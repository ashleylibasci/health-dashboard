import SwiftUI
import Charts
import HealthCore

/// Alcohol and your sleep: log alcohol, see what your own nights show the
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
    @State private var toast: UndoToast?
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
        // One title, the nav title; "alcohol", since "drink" means caffeine
        // elsewhere in the app (Valtonen F8, Dubois 3).
        Screen(title: "Alcohol and your sleep", accent: .purple) {
            SampleDataBanner()
            header
            logCard
            effectCard
            nightsCard
            recentCard
            tipsCard
            HowWeGotThisLink(title: "Alcohol and your sleep",
                             method: "We take the nights that followed an evening when you logged drinks (anything from 5pm to 5am, so each drink counts for one night only) and compare them with your other nights: how long you slept, your HRV and resting heart rate the next morning compared with your usual, and your morning check-in. It doesn\u{2019}t separate amounts: a night after one glass counts the same as a night after several. We need at least \(HabitEffect.minimumNights) nights of each before showing a result, and it gets more reliable as nights add up.")
        }
        .sheet(item: $editing) { entry in
            AlcoholEntryEditor(entry: entry)
                .environmentObject(model)
                .environmentObject(store)
        }
        .undoToast($toast)
        .sensoryFeedback(.increase, trigger: logCount)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("No judgment, just what your own data shows the morning after.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            InfoButton(topic: .alcohol).padding(.vertical, -10)
        }
        .padding(.top, 4)
    }

    // MARK: Log

    private func logDrinks() {
        if let last = lastLogTap, Date.now.timeIntervalSince(last) < 1.5 { return }
        lastLogTap = .now
        let chosen = time
        let date = min(time.date, .now)
        let entry = AppData.AlcoholEntry(date: date, kind: kind, count: count)
        withMotion(.log) { store.data.alcoholLog.append(entry) }
        toast = UndoToast(LogFormat.loggedLine(Self.phrase(count: count, kind: kind), time: chosen, at: date)) {
            withMotion(.undo) { store.data.alcoholLog.removeAll { $0.id == entry.id } }
        }
        time = .now
        count = 1
        logCount += 1
    }

    private var logCard: some View {
        Card(accent: .purple) {
            Text("Log alcohol").font(.cardTitle)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.kinds, id: \.self) { k in
                        kindChip(k)
                    }
                }
            }
            HStack(spacing: 12) {
                Text("How many").font(.bodyEmphasis)
                Spacer()
                countButton("minus", label: "One fewer") { count = max(1, count - 1) }
                Text("\(count)").font(.numberM).frame(minWidth: 32)
                    .accessibilityLabel(count == 1 ? "1 drink" : "\(count) drinks")
                countButton("plus", label: "One more") { count = min(15, count + 1) }
            }
            Text(Self.standardDrinkLine)
                .font(.secondary).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LogTimeSelector(time: $time, accent: .purple, title: "When?")
            PrimaryButton(title: "Log \(Self.phrase(count: count, kind: kind))", accent: .purple, action: logDrinks)
            AlcoholSafetyNote()
        }
    }

    /// What one drink means here: a US standard drink (14 g of alcohol).
    static let standardDrinkLine = "One drink is 5 oz of wine, 12 oz of 5% beer or seltzer, or a 1.5 oz shot. A cocktail or big pour is often 2 or more."

    private func kindChip(_ k: String) -> some View {
        let p = Palette(scheme: scheme)
        let on = kind == k
        return Button { withMotion(.select) { kind = k } } label: {
            Label(k, systemImage: Self.symbol(for: k))
                .font(.bodyEmphasis)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(on ? Color(hex: 0x14002E) : p.primary)
                .background(on ? Accent.purple.fill(scheme) : p.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Accent.purple.fill(scheme) : p.cardBorder))
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: on) { _, isOn in isOn }
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func countButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.bodyEmphasis)
                .foregroundStyle(Accent.purple.ink(scheme))
                .frame(width: 44, height: 44)
                .background(Accent.purple.fill(scheme).opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Effect

    private var effect: HabitEffect { model.alcoholEffect }

    /// "After alcohol you sleep 25 min less, your HRV is 12% lower and you feel worse the next morning."
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
        return "After alcohol \(joined)."
    }

    private var effectCard: some View {
        Card {
            HStack {
                Text("After alcohol").font(.cardTitle)
                if model.usingSampleData { ExampleTag() }
                Spacer()
                Text("\(effect.withCount) night\(effect.withCount == 1 ? "" : "s")")
                    .font(.secondary).fontWeight(.bold)
                    .foregroundStyle(Accent.purple.ink(scheme))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Accent.purple.fill(scheme).opacity(0.18), in: Capsule())
            }
            if effect.enoughData {
                Text(effectSentence).font(.bodyEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    EffectTile(title: "Sleep", value: signed(effect.asleepDelta, unit: " min"),
                               good: abs(effect.asleepDelta) < 10 ? nil : effect.asleepDelta > 0,
                               explanation: Explanation(id: "drinkSleep", title: "Sleep after alcohol",
                                                        meaning: "How much longer or shorter you slept after alcohol than on your other nights.",
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
                                                            meaning: "Your morning check-in (1 to 5) after alcohol compared with other mornings.",
                                                            forYou: "Below zero means you felt less awake than usual the morning after."))
                    }
                }
                Text("From \(effect.withCount) night\(effect.withCount == 1 ? "" : "s") after alcohol, compared with \(effect.withoutCount) without. It doesn\u{2019}t separate amounts, so one drink and several count the same." + cycleNote)
                    .font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not enough nights yet").font(.bodyEmphasis)
                Text("You have \(effect.withCount) night\(effect.withCount == 1 ? "" : "s") after alcohol and \(effect.withoutCount) without. We need at least \(HabitEffect.minimumNights) of each to compare fairly. If you have drinks, log them and wear your Watch to bed; the comparison fills in over time. There\u{2019}s no need to drink to get there.")
                    .font(.bodyText).secondaryText()
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
                ? "No nights after alcohol in the last two weeks."
                : "Average sleep \(Clock.duration(a)) after alcohol vs \(Clock.duration(b)) on other nights."
            return ("Last \(points.count) nights", "\(drink.count) after alcohol", detail)
        }
        let day = p.night.wakeDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        var detail = p.afterDrinks ? "After drinks\(p.drinksText.map { " (\($0))" } ?? "")." : "No drinks the evening before."
        if let h = p.night.outcome.hrvDeltaPct {
            detail += " HRV \(Int(abs(h).rounded()))% \(h < 0 ? "below" : "above") your usual."
        }
        if let c = p.night.outcome.checkIn { detail += " You felt \(Int(c)) of 5." }
        return ("Night before \(day) \u{00B7} asleep", Clock.duration(p.asleep), detail)
    }

    private var nightsCard: some View {
        Card(accent: .purple) {
            HStack {
                Text("Your recent nights").font(.bodyEmphasis)
                if model.usingSampleData { ExampleTag() }
            }
            let r = nightsReadout
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .purple,
                         onClear: selected == nil ? nil : { selected = nil })
            DrinkNightsChart(points: points, selected: selectedPoint?.index, selection: $selected)
                .frame(height: 170)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hours asleep over the last \(points.count) nights. \(points.filter(\.afterDrinks).count) followed alcohol.")
                .accessibilityChartDescriptor(DateChartDescriptor(
                    title: "Time asleep, last \(points.count) nights", seriesName: "Time asleep", yTitle: "Time asleep",
                    points: points.map { ($0.night.wakeDay, Double($0.asleep)) },
                    yLabel: { Clock.duration(Int($0.rounded())) }, isContinuous: false))
            ScrubHint(each: "night")
            HStack(spacing: 14) {
                legend("After alcohol", color: Self.drinkBar(scheme))
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
        .font(.secondary)
        .secondaryText()
    }

    // MARK: Recent entries

    private var recent: [AppData.AlcoholEntry] { model.recentAlcohol(days: 14) }

    private var recentCard: some View {
        Card {
            HStack {
                Text("Logged alcohol").font(.cardTitle).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Last 2 weeks").font(.secondary).fontWeight(.semibold).secondaryText()
            }
            if recent.isEmpty {
                Text("Nothing logged in the last two weeks.").font(.bodyText).secondaryText()
            } else {
                LogEntryList(items: recent, onTap: { editing = $0 },
                             onDelete: { entry in store.data.alcoholLog.removeAll { $0.id == entry.id } }) { entry in
                    LogEntryRow(systemImage: Self.symbol(for: entry.kind), accent: .purple,
                                title: Self.phrase(count: entry.count, kind: entry.kind),
                                detail: entry.count == 1 ? "1 drink" : "\(entry.count) drinks",
                                time: LogFormat.time(entry.date))
                }
                Text("Tap an entry to change it. Swipe left to delete.")
                    .font(.secondary).secondaryText()
            }
        }
    }

    private var tipsCard: some View {
        Card(accent: .mint) {
            Label("What helps most", systemImage: "lightbulb.fill")
                .font(.bodyEmphasis)
                .foregroundStyle(Accent.mint.ink(scheme))
            Text("Finish your last drink 3 or more hours before bed, and have a glass of water between drinks. A standard drink takes most women about 2 hours to clear, and nothing speeds it up: not coffee, water or sleep. Cocktails are often 2 or more.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Text("Energy drinks and alcohol in the same evening can hide how drunk you feel, so they\u{2019}re best kept apart.")
                .font(.bodyText).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "Water", subtitle: "Log a bottle", systemImage: "drop.fill", accent: .blue) {
                WaterView()
            }
        }
    }
}

// MARK: - Pieces

/// After 4 or more drinks in the last few hours: a calm alcohol-poisoning
/// line with the signs and a 911 button. Facts only, no judgment. Shows
/// nothing otherwise.
struct AlcoholSafetyNote: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if model.showsAlcoholSafetyLine {
            VStack(alignment: .leading, spacing: 8) {
                Label("Looking out for you and your friends", systemImage: "heart.fill")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Accent.pink.ink(scheme))
                Text("4 or more drinks in an evening is a lot for most women, and blood alcohol keeps rising for a while after the last one. Signs of alcohol poisoning: confusion, throwing up, slow or uneven breathing, pale or bluish skin, or can\u{2019}t be woken. If you see any, call 911. Don\u{2019}t leave a friend alone to sleep it off; keep her on her side.")
                    .font(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: URL(string: "tel:911")!) {
                    Label("Call 911", systemImage: "phone.fill")
                        .font(.bodyEmphasis)
                        .foregroundStyle(Accent.pink.ink(scheme))
                        .frame(minHeight: 44)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Accent.pink.tint(scheme), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }
}

/// "Example" on cards that show the sample analysis, not hers.
struct ExampleTag: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("Example")
            .font(.small).fontWeight(.bold)
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
                Text(title.uppercased()).font(.secondary).fontWeight(.bold).secondaryText()
                Spacer(minLength: 0)
                InfoButton(explanation: explanation).padding(.vertical, -12).padding(.trailing, -10)
            }
            Text(value).font(.numberM)
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            // In words too, so color is never the only cue.
            Text(verdict).font(.secondary).fontWeight(.semibold).secondaryText()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
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
        .chartScrub($selection, snapped: selected, steps: points.map(\.index))
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
        LogEditSheet(title: "Edit alcohol", accent: .purple, date: entry.date, amount: Double(entry.count),
                     unit: "drink", pluralUnit: "drinks", step: 1, range: 1...15, showsDate: true,
                     onSave: { date, n in save(date: date, count: Int(n.rounded())) },
                     onDelete: { store.data.alcoholLog.removeAll { $0.id == entry.id } }) {
            Card {
                Text("Kind").font(.bodyEmphasis)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DrinksView.kinds, id: \.self) { k in
                            Button { kind = k } label: {
                                Text(k)
                                    .font(.bodyEmphasis)
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
