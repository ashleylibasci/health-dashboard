import SwiftUI
import Charts
import HealthCore

/// Water today, summary first: how far to the goal and the Log tab's add
/// buttons. Today's entries open in place; the running total through the
/// day and the bottle size and goal are pages one tap down.
struct WaterView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var editing: AppData.WaterEntry?
    @State private var toast: UndoToast?
    @State private var showsAdd = false
    @State private var goalCount = 0
    @State private var logCount = 0

    var body: some View {
        Screen(title: "Water", accent: .blue) {
            SampleDataBanner()
            header
            WaterQuickLog(toast: $toast, showsTotal: false) { showsAdd = true }
            rows
            if !hidesGoal {
                Card(density: .compact) {
                    LearnMoreRow("Learn more about water", article: .waterGoal, accent: .blue)
                }
            }
        }
        .sheet(item: $editing) { entry in
            editor(entry)
        }
        .bottomSheet(isPresented: $showsAdd, title: "Add water") {
            WaterAddSheet { ml, label, time in add(ml: ml, label: label, time: time) }
                .environmentObject(model)
                .environmentObject(store)
        }
        .undoToast($toast)
        .sensoryFeedback(.increase, trigger: logCount)
        .sensoryFeedback(.success, trigger: goalCount)
    }

    /// "8", "8.5" or "8,5" as a number; nil if it isn't one.
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private var bottleML: Double { store.data.bottleSizeML }
    private var goalML: Double { model.waterGoalTodayML }
    /// Eating-disorder history: no goal, percentage, "goal reached" or pace
    /// anywhere, just the total (Cole 5, Ruiz F13).
    private var hidesGoal: Bool { model.hidesEffortTargets }

    // MARK: Summary

    /// The same answer, short: a chip and one line for the summary.
    private var pace: (status: SummaryStatus?, line: String) {
        let have = model.waterTodayML
        if have >= goalML { return (nil, "Goal reached. Nice.") }
        let steady = model.waterPace(at: model.now)
        let gap = steady - have
        if gap <= bottleML * 0.25 {
            return (SummaryStatus(text: "On track", accent: .mint), "A steady pace would be about \(LogFormat.oz(steady)) by now.")
        }
        if gap < min(bottleML, 1000) {
            return (SummaryStatus(text: "A little behind", accent: .yellow), "About \(LogFormat.oz(gap)) to catch up over the next hour or two.")
        }
        let behind = gap / bottleML
        return (SummaryStatus(text: "Behind pace", accent: .yellow),
                "About \(LogFormat.bottles(behind)) bottle\((behind * 2).rounded() / 2 > 1 ? "s" : "") behind. Spread it out: no more than about 34 oz an hour.")
    }

    private var lastPair: StatPair {
        StatPair(label: "Last drink", value: model.todaysWater.last.map { LogFormat.time($0.date) } ?? "None yet")
    }

    @ViewBuilder
    private var header: some View {
        let have = model.waterTodayML
        if hidesGoal {
            // With an eating-disorder history: the total only, no goal or bar.
            SummaryHeader(eyebrow: "Water today", value: LogFormat.ozNumber(have), unit: "oz",
                          line: "\(LogFormat.bottlesPhrase(model.waterBottlesToday)) logged today.", pairs: [lastPair],
                          accent: .blue,
                          info: Explanation(id: "waterToday", title: "Water today",
                                            meaning: "The water you logged today, added up. Bottles are counted with your own bottle size, which you can change in Bottle and goal.",
                                            forYou: "Drink to thirst, and a bit more on hot days. Drinks like tea, milk and juice count too, and food adds more."))
        } else {
            let p = pace
            let toGo = max(goalML - have, 0)
            SummaryHeader(eyebrow: "Water today", value: LogFormat.ozNumber(have), unit: "of \(LogFormat.oz(goalML))",
                          status: p.status, line: p.line,
                          pairs: [lastPair, StatPair(label: "To go", value: toGo > 0 ? LogFormat.oz(toGo) : "Done")],
                          accent: .blue, info: CaffeineWaterCopy.waterGoal) {
                SummaryMeter(fraction: goalML > 0 ? have / goalML : 0, accent: .blue,
                             caption: "\(LogFormat.bottles(model.waterBottlesToday)) of \(LogFormat.bottlesPhrase(model.waterGoalBottles))")
            }
        }
    }

    // MARK: Add

    private func add(ml: Double, label: String, time: LogTime) {
        let id = UUID()
        let wasUnderGoal = model.waterTodayML < model.waterGoalTodayML
        withMotion(.log) { model.addWater(ml: ml, at: time.date, id: id) }
        let when = store.data.waterLog.first { $0.id == id }?.date ?? .now
        var message = LogFormat.loggedLine(label, time: time, at: when).replacingOccurrences(of: "Logged ", with: "Added ")
        if !model.hidesEffortTargets, wasUnderGoal, model.waterTodayML >= model.waterGoalTodayML {
            message += " That\u{2019}s today\u{2019}s goal."
            goalCount += 1
        } else {
            logCount += 1
        }
        toast = UndoToast(message) { withMotion(.undo) { model.deleteWater(id) } }
    }

    // MARK: Rows

    /// "88 oz · +16 oz for training", or "72 oz · your usual goal".
    private var goalSummary: String {
        let extra = model.waterExtraToday
        guard extra.ml > 0 else { return "\(LogFormat.oz(goalML)) \u{00B7} your usual goal" }
        return "\(LogFormat.oz(goalML)) \u{00B7} +\(LogFormat.oz(extra.ml)) for \(extra.reasons.joined(separator: " and "))"
    }

    /// Why today's goal is higher, and the hot-day switch (D6).
    @ViewBuilder
    private var goalDetail: some View {
        if model.hardTrainingToday {
            Text("Today counts as a hard training day from your Watch, so your goal has \(LogFormat.oz(AppModel.trainingExtraML)) extra for the sweat.")
        } else {
            Text("On a hard training day (from your Watch) your goal goes up \(LogFormat.oz(AppModel.trainingExtraML)) by itself.")
        }
        Toggle(isOn: Binding(get: { model.hotDayToday },
                             set: { store.data.hotDay = $0 ? .now : nil })) {
            Text("Hot day today (+\(LogFormat.oz(AppModel.hotDayExtraML)))").font(.bodyEmphasis)
        }
        .tint(Accent.blue.fill(scheme))
        Text("Sweat losses vary a lot. Drink to thirst, and spread it out: no more than about 34 oz an hour.")
            .font(.secondary)
    }

    private var entriesSummary: String {
        guard let last = model.todaysWater.last else { return "None yet" }
        return "\(model.todaysWater.count) logged \u{00B7} last \(LogFormat.time(last.date))"
    }

    private var rows: some View {
        RowCard {
            MetricRow(title: "Water through the day",
                      note: hidesGoal ? "Your total, hour by hour" : "Pace: \(LogFormat.oz(model.waterPace(at: model.now))) by now",
                      systemImage: "chart.xyaxis.line", accent: .blue) {
                WaterDayView()
            }
            RowDivider()
            ExpandRow(title: "Today\u{2019}s entries", summary: entriesSummary, systemImage: "list.bullet", accent: .blue) {
                if model.todaysWater.isEmpty {
                    Text("Nothing logged yet today.")
                } else {
                    LogEntryList(items: model.todaysWater.reversed(), onTap: { editing = $0 },
                                 onDelete: { model.deleteWater($0.id) }) { entry in
                        LogEntryRow(systemImage: "drop.fill", accent: .blue, title: LogFormat.oz(entry.ml),
                                    detail: LogFormat.bottlesPhrase(entry.ml / max(bottleML, 1)),
                                    time: LogFormat.time(entry.date))
                    }
                    .foregroundStyle(Palette(scheme: scheme).primary)
                    Text("Tap an entry to change its time or amount. Swipe left to delete.")
                        .font(.secondary)
                }
            }
            if !hidesGoal {
                RowDivider()
                ExpandRow(title: "Today\u{2019}s goal", summary: goalSummary, systemImage: "figure.run", accent: .blue) {
                    goalDetail
                }
            }
            RowDivider()
            MetricRow(title: hidesGoal ? "Your bottle" : "Bottle and goal",
                      note: hidesGoal ? "\(LogFormat.oz(bottleML)) bottle" : "\(LogFormat.oz(bottleML)) bottle \u{00B7} \(LogFormat.oz(store.data.waterGoalML)) goal",
                      systemImage: "waterbottle.fill", accent: .blue) {
                WaterBottleGoalView()
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
}

// MARK: - Water through the day

/// The running total through today against a steady pace to the goal,
/// scrubbable hour by hour. One tap down from Water.
struct WaterDayView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selected: Int?

    private var bottleML: Double { store.data.bottleSizeML }
    private var goalML: Double { model.waterGoalTodayML }
    /// Eating-disorder history: no goal, percentage or pace (Cole 5, Ruiz F13).
    private var hidesGoal: Bool { model.hidesEffortTargets }

    var body: some View {
        Screen(title: "Water through the day", accent: .blue) {
            SampleDataBanner()
            chartCard
        }
    }

    /// Where she is against a steady pace, in full (the chart's readout).
    private var status: String {
        let have = model.waterTodayML
        // No goal or "behind" with an eating-disorder history: just what's logged.
        if hidesGoal { return "\(LogFormat.oz(have)) logged so far today." }
        if have >= goalML { return "Goal reached. Nice." }
        let pace = model.waterPace(at: model.now)
        let gap = pace - have
        if gap <= bottleML * 0.25 { return "On track for this time of day." }
        // Never a catch-up faster than about 34 oz (1 liter) an hour (Ruiz F10).
        if gap < min(bottleML, 1000) { return "A little behind a steady pace. About \(LogFormat.oz(gap)) to catch up over the next hour or two." }
        let behind = gap / bottleML
        return "About \(LogFormat.bottles(behind)) bottle\((behind * 2).rounded() / 2 > 1 ? "s" : "") behind a steady pace for this time of day. No need to catch up at once: spread it out, no more than about 34 oz an hour."
    }

    private var chartStart: Minutes {
        let first = model.todaysWater.first.map { model.appDayMinutes($0.date) } ?? model.lastNight.wake
        return (min(first, model.lastNight.wake) / 60) * 60
    }

    private var chartEnd: Minutes { max(1440 + model.tonightBedtime, model.now + 30) }

    private var run: [WaterRunPoint] { model.waterRun(from: chartStart, to: min(model.now, chartEnd)) }

    private var paceLine: [WaterRunPoint] {
        // No pace to keep up with under eating-disorder history: the line
        // was the "behind a steady pace" nag as a picture (round 3, H6).
        guard !model.hidesActivityNumbers else { return [] }
        let start = model.lastNight.wake
        let end = 1440 + model.tonightBedtime - 60
        return [WaterRunPoint(time: start, ml: 0), WaterRunPoint(time: end, ml: goalML)]
    }

    /// Snap to a drink if one is close, otherwise to the quarter hour.
    private func snap(_ t: Int) -> Int {
        let clamped = min(max(t, chartStart), chartEnd)
        let times = model.todaysWater.map { model.appDayMinutes($0.date) }
        if let near = times.min(by: { abs($0 - clamped) < abs($1 - clamped) }), abs(near - clamped) <= 20 { return near }
        return (clamped / 15) * 15
    }

    /// The readout at a snapped time, or for now when nothing is selected.
    private func readout(at time: Int?) -> (title: String, value: String, detail: String) {
        guard let t = time else {
            let have = model.waterTodayML
            return ("Now \u{00B7} \(Clock.format(model.now))", "\(LogFormat.oz(have)) \u{00B7} \(LogFormat.bottlesPhrase(model.waterBottlesToday))", status)
        }
        let have = model.waterML(by: t)
        let pct = goalML > 0 ? Int((have / goalML * 100).rounded()) : 0
        let atThatTime = model.todaysWater.filter { model.appDayMinutes($0.date) == t }.map(\.ml).reduce(0, +)
        var detail = hidesGoal ? "Your total by then." : "\(pct)% of your goal."
        if atThatTime > 0 { detail = "You drank \(LogFormat.oz(atThatTime)) here. " + detail }
        if hidesGoal {
            if t > model.now { detail = "Later today." }
        } else if t > model.now {
            detail = "Later today. A steady pace reaches \(LogFormat.oz(model.waterPace(at: t))) by then."
        } else {
            detail += " A steady pace would be about \(LogFormat.oz(model.waterPace(at: t))) by then."
        }
        return ("By \(Clock.format(t))", "\(LogFormat.oz(have)) \u{00B7} \(LogFormat.bottlesPhrase(have / max(bottleML, 1)))", detail)
    }

    /// Every note the readout can show today, so it keeps one height.
    private var detailSlots: [String] {
        let times = Set(stride(from: chartStart, through: chartEnd, by: 15).map(snap) + model.todaysWater.map { model.appDayMinutes($0.date) })
        return [readout(at: nil).detail] + times.map { readout(at: $0).detail }
    }

    private var chartCard: some View {
        Card(accent: .blue) {
            Text("Today").font(.bodyEmphasis).accessibilityAddTraits(.isHeader)
            let r = readout(at: selected)
            ChartReadout(title: r.title, value: r.value, detail: r.detail, accent: .blue,
                         onClear: selected == nil ? nil : { selected = nil },
                         detailSlots: detailSlots)
            WaterDayChart(run: run, pace: paceLine, goal: hidesGoal ? nil : goalML, start: chartStart, end: chartEnd,
                          now: model.now, selected: selected, selectedML: selected.map { model.waterML(by: $0) },
                          selection: $selected.snapping { snap($0) })
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hidesGoal ? "Water today: \(LogFormat.oz(model.waterTodayML)) so far."
                                    : "Water today: \(LogFormat.oz(model.waterTodayML)) so far of a \(LogFormat.oz(goalML)) goal. \(status)")
                .accessibilityChartDescriptor(ClockChartDescriptor(
                    title: "Water today", seriesName: "Water so far", yTitle: "Ounces",
                    points: run.map { ($0.time, $0.ml / LogFormat.mlPerOunce) },
                    yLabel: { "\(Int($0.rounded())) oz" }))
            ScrubHint(each: "hour")
            if !hidesGoal {
                // The goal is named here, not on the plot (Arai 4).
                HStack(spacing: 14) {
                    legend("You", color: Accent.blue.fill(scheme), dashed: false)
                    legend("Steady pace", color: Palette(scheme: scheme).tertiary, dashed: true)
                    legend("Goal", color: Accent.blue.ink(scheme), dashed: true)
                }
                .accessibilityHidden(true)
            }
            HowWeGotThisLink(title: "Water through the day",
                             method: hidesGoal
                                ? "The blue line adds up every drink you log, at the time you logged it."
                                : "The blue line adds up every drink you log, at the time you logged it. The dashed steady-pace line spreads your daily goal evenly from when you woke up to an hour before your bedtime, so you can see whether you're ahead or behind for the time of day.")
        }
    }

    private func legend(_ text: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 16, height: dashed ? 2 : 4)
            Text(text)
        }
        .font(.secondary)
        .secondaryText()
    }

}

// MARK: - Add water at another time or amount

/// The Water screen's "Earlier, or another amount" sheet: when she had it,
/// a bottle or half, or any amount in ounces. Closes after adding, so the
/// Undo toast shows on the screen.
private struct WaterAddSheet: View {
    var onAdd: (_ ml: Double, _ label: String, _ time: LogTime) -> Void
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var time: LogTime = .now
    /// What she typed, parsed only when she taps Add, so the button always
    /// uses the number on screen.
    @State private var customOz = ""
    /// Why a typed amount wasn't used (out of range), instead of a silent change.
    @State private var amountNote: String?
    @FocusState private var focused: Bool

    private var bottleML: Double { store.data.bottleSizeML }

    var body: some View {
        Card {
            LogTimeSelector(time: $time, accent: .blue)
        }
        HStack(spacing: 10) {
            addButton(title: "1 bottle", detail: LogFormat.oz(bottleML)) { add(bottleML, label: "1 bottle") }
            addButton(title: "\u{00BD} bottle", detail: LogFormat.oz(bottleML / 2)) { add(bottleML / 2, label: "half a bottle") }
        }
        Card {
            LabeledControlRow(spacing: 10) {
                Text("Other amount").font(.bodyEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
            } control: {
                HStack(spacing: 10) {
                    TextField("8", text: $customOz)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.bodyEmphasis)
                        .focused($focused)
                        .padding(.horizontal, 10)
                        .frame(width: Font.scaledSize(80))
                        .frame(minHeight: 44)
                        .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                        .accessibilityLabel("Other amount in ounces")
                    Text("oz").font(.bodyText).secondaryText()
                    Button(action: addTyped) {
                        Text("Add")
                            .font(.bodyEmphasis)
                            .fixedSize()   // never squeezed into letters (round 3)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .foregroundStyle(Color(hex: 0x00111F))
                            .background(Accent.blue.fill(scheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled((WaterView.parse(customOz) ?? 0) <= 0)
                    .accessibilityLabel("Add \(customOz.isEmpty ? "the amount you typed" : customOz + " ounces"), \(time.phrase)")
                }
            }
            if let amountNote { WaterRangeNote(text: amountNote) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private func add(_ ml: Double, label: String) {
        onAdd(ml, label, time)
        dismiss()
    }

    private func addTyped() {
        focused = false
        guard let oz = WaterView.parse(customOz), oz > 0 else { return }
        guard oz <= 100 else {
            amountNote = "\(customOz) oz is more than 100 oz at once, so it wasn\u{2019}t added. Log it in parts, or check the number."
            return
        }
        let ml = max(oz, 1) * LogFormat.mlPerOunce
        add(ml, label: LogFormat.oz(ml))
    }

    private func addButton(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Label(title, systemImage: "plus").font(.bodyEmphasis)
                Text(detail).font(.secondary).fontWeight(.semibold).secondaryText()
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(Accent.blue.ink(scheme))
            .background(Accent.blue.fill(scheme).opacity(0.18), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).strokeBorder(Accent.blue.fill(scheme).opacity(0.35)))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Add \(title), \(detail), \(time.phrase)")
    }
}

/// Why a typed amount wasn't used, in orange.
private struct WaterRangeNote: View {
    var text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.secondary).fontWeight(.semibold)
            .foregroundStyle(Accent.orange.ink(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Bottle and goal

/// Her bottle size and daily water goal: settings, not data, so a page one
/// tap down from Water (and Settings' Water bottle row).
struct WaterBottleGoalView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var customBottle = ""
    @State private var bottleNote: String?
    @FocusState private var focused: Bool

    /// Common bottles in fluid ounces: a can-size cup, a store water bottle, 24, 32 and 40 oz tumblers.
    private static let bottlePresetsOz: [Double] = [12, 16.9, 24, 32, 40]
    /// Over about 135 oz (4 L) a day is a lot for most women (Ruiz F10).
    private static let highGoalOz = 135.0

    private var bottleML: Double { store.data.bottleSizeML }
    /// Her usual goal (the setting), not today's with any extra.
    private var goalML: Double { store.data.waterGoalML }

    var body: some View {
        Screen(title: model.hidesEffortTargets ? "Your bottle" : "Bottle and goal", accent: .blue) {
            bottleCard
            if !model.hidesEffortTargets { goalCard }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

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
                Text("Your bottle").font(.cardTitle).accessibilityAddTraits(.isHeader)
                InfoButton(title: "Bottle size",
                           meaning: "How much your usual water bottle holds. Every \u{201C}1 bottle\u{201D} button and bottle count in the app uses it.",
                           forYou: "Check the label or the bottom of your bottle. If you switch bottles, change it here; entries you already logged keep their amounts.")
                    .padding(.vertical, -12)
                Spacer()
                Text(LogFormat.oz(bottleML))
                    .font(.bodyEmphasis).foregroundStyle(Accent.blue.ink(scheme))
                    .fixedSize()
            }
            HStack(spacing: 8) {
                ForEach(Self.bottlePresetsOz, id: \.self) { oz in
                    presetButton(oz * LogFormat.mlPerOunce)
                }
            }
            Stepper(value: bottleBinding, in: 4...68, step: 1) {
                Text("Adjust by 1 oz").font(.bodyEmphasis)
            }
            .frame(minHeight: 44)
            // "Bottle size, 24 oz", not "Adjust by 1 oz" (Ortiz F8).
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bottle size")
            .accessibilityValue("\(LogFormat.ozNumber(bottleML)) ounces")
            LabeledControlRow(spacing: 10) {
                Text("Exact size").font(.bodyEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
            } control: {
              HStack(spacing: 10) {
                TextField("\(LogFormat.ozNumber(bottleML))", text: $customBottle)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.bodyEmphasis)
                    .focused($focused)
                    .padding(.horizontal, 10)
                    .frame(width: Font.scaledSize(80))
                    .frame(minHeight: 44)
                    .background(Palette(scheme: scheme).chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityLabel("Exact bottle size in ounces")
                Text("oz").font(.bodyText).secondaryText()
                Button {
                    focused = false
                    guard let oz = WaterView.parse(customBottle), oz >= 4 else { return }
                    guard oz <= 68 else {
                        bottleNote = "\(customBottle) oz is bigger than the 68 oz limit, so your bottle size didn\u{2019}t change."
                        return
                    }
                    bottleNote = nil
                    bottleBinding.wrappedValue = oz
                    customBottle = ""
                } label: {
                    Text("Set")
                        .font(.bodyEmphasis)
                        .fixedSize()   // never squeezed into letters (round 3)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .foregroundStyle(Accent.blue.onTint(scheme))
                        .background(Accent.blue.tint(scheme), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled((WaterView.parse(customBottle) ?? 0) < 4)
              }
            }
            if let bottleNote { WaterRangeNote(text: bottleNote) }
            Text("Between 4 and 68 oz.").font(.secondary).secondaryText()
        }
    }

    private func presetButton(_ ml: Double) -> some View {
        let p = Palette(scheme: scheme)
        let on = abs(bottleML - ml) < 1
        return Button { store.data.bottleSizeML = ml } label: {
            VStack(spacing: 2) {
                Text(LogFormat.ozNumber(ml)).font(.bodyEmphasis).keepsOnOneLine()
                Text("oz").font(.small).fontWeight(.semibold)
                    .foregroundStyle(on ? Color(hex: 0x00111F).opacity(0.75) : p.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(on ? Color(hex: 0x00111F) : p.primary)
            .background(on ? Accent.blue.fill(scheme) : p.chip, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).strokeBorder(on ? Accent.blue.fill(scheme) : p.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LogFormat.ozNumber(ml)) ounce bottle")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var goalCard: some View {
        Card {
            HStack(spacing: 0) {
                Text("Daily goal").font(.cardTitle).accessibilityAddTraits(.isHeader)
                InfoButton(explanation: CaffeineWaterCopy.waterGoal).padding(.vertical, -12)
            }
            Stepper(value: goalBinding, in: 16...170, step: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LogFormat.oz(goalML)).font(.numberM)
                    Text(LogFormat.bottlesPhrase(bottleML > 0 ? goalML / bottleML : 0))
                        .font(.secondary).secondaryText()
                }
            }
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily goal")
            .accessibilityValue("\(LogFormat.ozNumber(goalML)) ounces, \(LogFormat.bottlesPhrase(bottleML > 0 ? goalML / bottleML : 0))")
            if goalML / LogFormat.mlPerOunce > Self.highGoalOz {
                WaterRangeNote(text: CaffeineWaterCopy.highGoal)
            }
        }
    }
}

// MARK: - Chart

private struct WaterDayChart: View {
    let run: [WaterRunPoint]
    let pace: [WaterRunPoint]
    /// Nil with an eating-disorder history: no goal line.
    let goal: Double?
    let start: Minutes
    let end: Minutes
    let now: Minutes
    let selected: Int?
    @Environment(\.dynamicTypeSize) private var typeSize
    let selectedML: Double?
    @Binding var selection: Int?
    @Environment(\.colorScheme) private var scheme

    /// Every 3 hours, or every 6 (about three labels) at accessibility sizes.
    private var ticks: [Int] {
        let step = typeSize.isAccessibilitySize ? 360 : 180
        let first = ((start + step - 1) / step) * step
        return Array(stride(from: first, through: end, by: step))
    }

    private var yMax: Double { max(goal ?? 16 * LogFormat.mlPerOunce, run.map(\.ml).max() ?? 0) * 1.15 }

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
        // VoiceOver reads the chart's summary (chartScrub makes it one
        // element), so no mark-level hiding (Weber A8).
        .chartScrub($selection, snapped: selected, feedbackKey: { $0 / 30 })
        .chartXScale(domain: start...end)
        // The last x label ("12am") ran past the plot's edge (Weber C11).
        .chartXScale(range: .plotDimension(endPadding: 10))
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

    @ChartContentBuilder
    private var goalRule: some ChartContent {
        if let goal {
            // Water is blue on this screen, goal included (Tanaka F4); its
            // label is in the legend under the chart, off the plot.
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(Accent.blue.ink(scheme))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
