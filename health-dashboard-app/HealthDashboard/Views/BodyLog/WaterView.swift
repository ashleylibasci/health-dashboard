import SwiftUI
import Charts
import HealthCore

/// Water today: progress, adding water at any time, the running total
/// through the day, today's entries (editable), and your bottle size and goal.
struct WaterView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var time: LogTime = .now
    /// What she typed, parsed only when she taps Add / Set, so the button
    /// always uses the number on screen.
    @State private var customOz = ""
    @State private var customBottle = ""
    @State private var editing: AppData.WaterEntry?
    @State private var selected: Int?
    @State private var lastLogged: String?
    /// Why a typed amount wasn't used (out of range), instead of a silent change.
    @State private var amountNote: String?
    @State private var bottleNote: String?
    @State private var logCount = 0
    @FocusState private var focused: Field?

    private enum Field: Hashable { case amount, bottle }

    /// Common bottles in fluid ounces: a can-size cup, a store water bottle, 24, 32 and 40 oz tumblers.
    private static let bottlePresetsOz: [Double] = [12, 16.9, 24, 32, 40]

    var body: some View {
        Screen(title: "Water", accent: .blue) {
            hero
            addCard
            chartCard
            entriesCard
            bottleCard
            goalCard
        }
        .sheet(item: $editing) { entry in
            editor(entry)
        }
        .sensoryFeedback(.success, trigger: logCount)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    /// "8", "8.5" or "8,5" as a number; nil if it isn't one.
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private var bottleML: Double { store.data.bottleSizeML }
    private var goalML: Double { store.data.waterGoalML }

    // MARK: Hero

    private var status: String {
        let have = model.waterTodayML
        if have >= goalML { return "Goal reached. Nice." }
        let pace = model.waterPace(at: model.now)
        let gap = pace - have
        if gap <= bottleML * 0.25 { return "On track for this time of day." }
        if gap < bottleML { return "A little behind a steady pace. About \(LogFormat.oz(gap)) to catch up." }
        let behind = gap / bottleML
        return "About \(LogFormat.bottles(behind)) bottle\((behind * 2).rounded() / 2 > 1 ? "s" : "") behind a steady pace for this time of day."
    }

    private var hero: some View {
        Card(padding: 18) {
            HStack(spacing: 16) {
                Ring(value: goalML > 0 ? model.waterTodayML / goalML : 0, accent: .blue,
                     label: LogFormat.bottles(model.waterBottlesToday),
                     caption: "of \(LogFormat.bottlesPhrase(model.waterGoalBottles))", size: 132)
                VStack(alignment: .leading, spacing: 6) {
                    Text(LogFormat.oz(model.waterTodayML)).font(.scaledNumber(26))
                    HStack(spacing: 0) {
                        Text("of \(LogFormat.oz(goalML)) goal").font(.scaled(size: 13, weight: .semibold)).secondaryText()
                        InfoButton(title: "Daily water goal",
                                   meaning: "How much you want to drink across the day. Bottles are counted with your own bottle size, which you can change below.",
                                   forYou: "About 50 to 70 oz a day from drinks is a common target for adults (food adds more). Drink more on hot days, workout days, and after alcohol. Pale yellow pee usually means you're drinking enough.")
                            .padding(.vertical, -12)
                    }
                    Text(status).font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(Accent.blue.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Add

    private func add(ml: Double, label: String) {
        model.addWater(ml: ml, at: time.date)
        let when = store.data.waterLog.last?.date ?? .now
        lastLogged = LogFormat.loggedLine(label, at: when).replacingOccurrences(of: "Logged ", with: "Added ")
        time = .now
        logCount += 1
    }

    private var addCard: some View {
        Card {
            Text("Add water").font(.scaled(size: 17, weight: .bold)).accessibilityAddTraits(.isHeader)
            LogTimeSelector(time: $time, accent: .blue)
            HStack(spacing: 10) {
                addButton(title: "1 bottle", detail: LogFormat.oz(bottleML)) { add(ml: bottleML, label: "1 bottle") }
                addButton(title: "\u{00BD} bottle", detail: LogFormat.oz(bottleML / 2)) { add(ml: bottleML / 2, label: "half a bottle") }
            }
            HStack(spacing: 10) {
                Text("Other amount").font(.scaled(size: 14, weight: .semibold))
                Spacer()
                TextField("8", text: $customOz)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.scaled(size: 16, weight: .semibold))
                    .focused($focused, equals: .amount)
                    .padding(.horizontal, 10)
                    .frame(width: Font.scaledSize(80))
                    .frame(minHeight: 44)
                    .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Other amount in ounces")
                Text("oz").font(.scaled(size: 14)).secondaryText()
                Button {
                    focused = nil
                    guard let oz = Self.parse(customOz), oz > 0 else { return }
                    guard oz <= 100 else {
                        amountNote = "\(customOz) oz is more than 100 oz at once, so it wasn\u{2019}t added. Log it in parts, or check the number."
                        return
                    }
                    amountNote = nil
                    let ml = max(oz, 1) * LogFormat.mlPerOunce
                    add(ml: ml, label: LogFormat.oz(ml))
                    customOz = ""
                } label: {
                    Text("Add")
                        .font(.scaled(size: 15, weight: .bold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .foregroundStyle(Color(hex: 0x00111F))
                        .background(Accent.blue.fill(scheme), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled((Self.parse(customOz) ?? 0) <= 0)
                .accessibilityLabel("Add \(customOz.isEmpty ? "the amount you typed" : customOz + " ounces"), \(time.phrase)")
            }
            if let amountNote { rangeNote(amountNote) }
            if let lastLogged {
                Label(lastLogged, systemImage: "checkmark.circle.fill")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.mint.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rangeNote(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.scaled(size: 13, weight: .semibold))
            .foregroundStyle(Accent.orange.ink(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func addButton(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Label(title, systemImage: "plus").font(.scaled(size: 15, weight: .bold))
                Text(detail).font(.scaled(size: 12, weight: .semibold)).secondaryText()
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(Accent.blue.ink(scheme))
            .background(Accent.blue.fill(scheme).opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Accent.blue.fill(scheme).opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(title), \(detail), \(time.phrase)")
    }

    // MARK: Chart

    private var chartStart: Minutes {
        let first = model.todaysWater.first.map { model.appDayMinutes($0.date) } ?? model.lastNight.wake
        return (min(first, model.lastNight.wake) / 60) * 60
    }

    private var chartEnd: Minutes { max(1440 + store.data.bedtime, model.now + 30) }

    private var run: [WaterRunPoint] { model.waterRun(from: chartStart, to: min(model.now, chartEnd)) }

    private var paceLine: [WaterRunPoint] {
        let start = model.lastNight.wake
        let end = 1440 + store.data.bedtime - 60
        return [WaterRunPoint(time: start, ml: 0), WaterRunPoint(time: end, ml: goalML)]
    }

    /// Snap to a drink if one is close, otherwise to the quarter hour.
    private func snap(_ t: Int) -> Int {
        let clamped = min(max(t, chartStart), chartEnd)
        let times = model.todaysWater.map { model.appDayMinutes($0.date) }
        if let near = times.min(by: { abs($0 - clamped) < abs($1 - clamped) }), abs(near - clamped) <= 20 { return near }
        return (clamped / 15) * 15
    }

    private var readout: (title: String, value: String, detail: String) {
        guard let raw = selected else {
            let have = model.waterTodayML
            return ("Now \u{00B7} \(Clock.format(model.now))", "\(LogFormat.oz(have)) \u{00B7} \(LogFormat.bottlesPhrase(model.waterBottlesToday))", status)
        }
        let t = snap(raw)
        let have = model.waterML(by: t)
        let pct = goalML > 0 ? Int((have / goalML * 100).rounded()) : 0
        let atThatTime = model.todaysWater.filter { model.appDayMinutes($0.date) == t }.map(\.ml).reduce(0, +)
        var detail = "\(pct)% of your goal."
        if atThatTime > 0 { detail = "You drank \(LogFormat.oz(atThatTime)) here. " + detail }
        if t > model.now {
            detail = "Later today. A steady pace reaches \(LogFormat.oz(model.waterPace(at: t))) by then."
        } else {
            detail += " A steady pace would be about \(LogFormat.oz(model.waterPace(at: t))) by then."
        }
        return ("By \(Clock.format(t))", "\(LogFormat.oz(have)) \u{00B7} \(LogFormat.bottlesPhrase(have / max(bottleML, 1)))", detail)
    }

    private var chartCard: some View {
        Card(accent: .blue) {
            Text("Water through the day").font(.scaled(size: 15, weight: .bold))
            let r = readout
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .blue)
                .frame(maxWidth: .infinity, alignment: .leading)
            WaterDayChart(run: run, pace: paceLine, goal: goalML, start: chartStart, end: chartEnd,
                          now: model.now, selected: selected.map(snap), selectedML: selected.map { model.waterML(by: snap($0)) },
                          selection: $selected)
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Water today: \(LogFormat.oz(model.waterTodayML)) so far of a \(LogFormat.oz(goalML)) goal. \(status)")
            ScrubHint()
            HStack(spacing: 14) {
                legend("You", color: Accent.blue.fill(scheme), dashed: false)
                legend("Steady pace", color: Palette(scheme: scheme).tertiary, dashed: true)
            }
            .accessibilityHidden(true)
            HowWeGotThisLink(title: "Water through the day",
                             method: "The blue line adds up every drink you log, at the time you logged it. The dashed steady-pace line spreads your daily goal evenly from when you woke up to an hour before your bedtime, so you can see whether you're ahead or behind for the time of day.")
        }
    }

    private func legend(_ text: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 16, height: dashed ? 2 : 4)
            Text(text)
        }
        .font(.scaled(size: 12))
        .secondaryText()
    }

    // MARK: Entries

    private var entriesCard: some View {
        Card {
            HStack {
                Text("Today").font(.scaled(size: 17, weight: .bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(model.todaysWater.count) logged").font(.scaled(size: 13, weight: .semibold)).secondaryText()
            }
            if model.todaysWater.isEmpty {
                Text("Nothing logged yet today. Add water above, at the time you had it.")
                    .font(.scaled(size: 14)).secondaryText()
            } else {
                LogEntryList(items: model.todaysWater.reversed(), onTap: { editing = $0 },
                             onDelete: { model.deleteWater($0.id) }) { entry in
                    LogEntryRow(systemImage: "drop.fill", accent: .blue, title: LogFormat.oz(entry.ml),
                                detail: LogFormat.bottlesPhrase(entry.ml / max(bottleML, 1)),
                                time: LogFormat.time(entry.date))
                }
                Text("Tap an entry to change its time or amount. Swipe left to delete.")
                    .font(.scaled(size: 12)).secondaryText()
            }
        }
    }

    private func editor(_ entry: AppData.WaterEntry) -> some View {
        // The sheet works in ounces; storage stays in ml.
        let toOz = { (ml: Double) in ((ml / LogFormat.mlPerOunce) * 10).rounded() / 10 }
        let presets: [(label: String, value: Double)] = [("\u{00BD} bottle", toOz(bottleML / 2)), ("1 bottle", toOz(bottleML))]
        return LogEditSheet(title: "Edit water", accent: .blue, date: entry.date, amount: toOz(entry.ml), unit: "oz",
                            step: 1, range: 1...100, presets: presets,
                            onSave: { date, oz in model.updateWater(entry.id, date: date, ml: oz * LogFormat.mlPerOunce) },
                            onDelete: { model.deleteWater(entry.id) })
            .environmentObject(model)
            .environmentObject(store)
    }

    // MARK: Bottle and goal

    private var bottleBinding: Binding<Double> {
        // In ounces. Storage stays in ml.
        Binding(get: { (store.data.bottleSizeML / LogFormat.mlPerOunce * 10).rounded() / 10 },
                set: { store.data.bottleSizeML = min(max($0, 4), 68) * LogFormat.mlPerOunce })
    }

    private var goalBinding: Binding<Double> {
        // In ounces. Storage stays in ml.
        Binding(get: { (store.data.waterGoalML / LogFormat.mlPerOunce).rounded() },
                set: { store.data.waterGoalML = min(max($0, 16), 170) * LogFormat.mlPerOunce })
    }

    private var bottleCard: some View {
        Card {
            HStack(spacing: 0) {
                Text("Your bottle").font(.scaled(size: 17, weight: .bold)).accessibilityAddTraits(.isHeader)
                InfoButton(title: "Bottle size",
                           meaning: "How much your usual water bottle holds. Every \u{201C}1 bottle\u{201D} button and bottle count in the app uses it.",
                           forYou: "Check the label or the bottom of your bottle. If you switch bottles, change it here; entries you already logged keep their amounts.")
                    .padding(.vertical, -12)
                Spacer()
                Text(LogFormat.oz(bottleML))
                    .font(.scaled(size: 14, weight: .bold)).foregroundStyle(Accent.blue.ink(scheme))
            }
            HStack(spacing: 8) {
                ForEach(Self.bottlePresetsOz, id: \.self) { oz in
                    presetButton(oz * LogFormat.mlPerOunce)
                }
            }
            Stepper(value: bottleBinding, in: 4...68, step: 1) {
                Text("Adjust by 1 oz").font(.scaled(size: 14, weight: .semibold))
            }
            .frame(minHeight: 44)
            HStack(spacing: 10) {
                Text("Exact size").font(.scaled(size: 14, weight: .semibold))
                Spacer()
                TextField("\(LogFormat.ozNumber(bottleML))", text: $customBottle)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.scaled(size: 16, weight: .semibold))
                    .focused($focused, equals: .bottle)
                    .padding(.horizontal, 10)
                    .frame(width: Font.scaledSize(80))
                    .frame(minHeight: 44)
                    .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Exact bottle size in ounces")
                Text("oz").font(.scaled(size: 14)).secondaryText()
                Button {
                    focused = nil
                    guard let oz = Self.parse(customBottle), oz >= 4 else { return }
                    guard oz <= 68 else {
                        bottleNote = "\(customBottle) oz is bigger than the 68 oz limit, so your bottle size didn\u{2019}t change."
                        return
                    }
                    bottleNote = nil
                    bottleBinding.wrappedValue = oz
                    customBottle = ""
                } label: {
                    Text("Set")
                        .font(.scaled(size: 15, weight: .bold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .foregroundStyle(Accent.blue.ink(scheme))
                        .background(Accent.blue.fill(scheme).opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled((Self.parse(customBottle) ?? 0) < 4)
            }
            if let bottleNote { rangeNote(bottleNote) }
            Text("Between 4 and 68 oz.").font(.scaled(size: 12)).secondaryText()
        }
    }

    private func presetButton(_ ml: Double) -> some View {
        let p = Palette(scheme: scheme)
        let on = abs(bottleML - ml) < 1
        return Button { store.data.bottleSizeML = ml } label: {
            VStack(spacing: 2) {
                Text(LogFormat.ozNumber(ml)).font(.scaled(size: 15, weight: .bold))
                Text("oz").font(.scaled(size: 11, weight: .semibold))
                    .foregroundStyle(on ? Color(hex: 0x00111F).opacity(0.75) : p.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(on ? Color(hex: 0x00111F) : p.primary)
            .background(on ? Accent.blue.fill(scheme) : p.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Accent.blue.fill(scheme) : p.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LogFormat.ozNumber(ml)) ounce bottle")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var goalCard: some View {
        Card {
            Text("Daily goal").font(.scaled(size: 17, weight: .bold)).accessibilityAddTraits(.isHeader)
            Stepper(value: goalBinding, in: 16...170, step: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LogFormat.oz(goalML)).font(.scaledNumber(22))
                    Text(LogFormat.bottlesPhrase(model.waterGoalBottles))
                        .font(.scaled(size: 13)).secondaryText()
                }
            }
            .frame(minHeight: 52)
            Text("Drinks like tea, milk and juice count too. Food adds more on top.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Chart

private struct WaterDayChart: View {
    let run: [WaterRunPoint]
    let pace: [WaterRunPoint]
    let goal: Double
    let start: Minutes
    let end: Minutes
    let now: Minutes
    let selected: Int?
    let selectedML: Double?
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var scheme

    private var ticks: [Int] {
        let first = ((start + 179) / 180) * 180
        return Array(stride(from: first, through: end, by: 180))
    }

    private var yMax: Double { max(goal, run.map(\.ml).max() ?? 0) * 1.15 }

    /// Gridlines every 16 oz (stored values are ml).
    private var ozTicks: [Double] { Array(stride(from: 0, through: yMax, by: 16 * LogFormat.mlPerOunce)) }

    private var areaFill: LinearGradient {
        LinearGradient(colors: [Accent.blue.fill(scheme).opacity(0.4), Accent.blue.fill(scheme).opacity(0.02)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        Chart {
            ForEach(run) { p in
                AreaMark(x: .value("Time", p.time), y: .value("Water", p.ml))
                    .foregroundStyle(areaFill)
                LineMark(x: .value("Time", p.time), y: .value("Water", p.ml), series: .value("Line", "You"))
                    .foregroundStyle(Accent.blue.fill(scheme))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            ForEach(pace) { p in
                LineMark(x: .value("Time", p.time), y: .value("Water", p.ml), series: .value("Line", "Pace"))
                    .foregroundStyle(Palette(scheme: scheme).tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            goalRule
            selectionMarks
        }
        .chartScrub($selection)
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let m = value.as(Int.self) { Text(BodyLogStyle.shortTime(m)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: ozTicks) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let ml = value.as(Double.self) { Text("\(LogFormat.ozNumber(ml)) oz") }
                }
            }
        }
    }

    private var goalRule: some ChartContent {
        RuleMark(y: .value("Goal", goal))
            .foregroundStyle(Accent.mint.fill(scheme))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, alignment: .leading) {
                Text("goal").font(.scaled(size: 11, weight: .semibold)).foregroundStyle(Accent.mint.ink(scheme))
            }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selected, let selectedML {
            RuleMark(x: .value("Selected", selected))
                .foregroundStyle(Palette(scheme: scheme).secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
            PointMark(x: .value("Selected", selected), y: .value("Water", selectedML))
                .foregroundStyle(Accent.blue.ink(scheme))
                .symbolSize(70)
        } else if now >= start && now <= end {
            PointMark(x: .value("Now", now), y: .value("Water", run.last?.ml ?? 0))
                .foregroundStyle(Palette(scheme: scheme).primary)
                .symbolSize(40)
        }
    }
}
