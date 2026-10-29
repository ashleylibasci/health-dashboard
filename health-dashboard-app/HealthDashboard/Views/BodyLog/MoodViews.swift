import SwiftUI
import Charts
import HealthCore

// Mood dots (H-B1): three one-tap 1–5 scales under the stress check-in on
// the Log tab, and "Your mood by pack day" on the combined pill.

/// "Mood, anxiety, irritability" folded under the stress rating: three rows
/// of five dots, one tap each, under 10 seconds. Stays open once she opens
/// it.
struct MoodScalesToggle: View {
    @Binding var toast: UndoToast?
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @AppStorage("moodScalesOpen") private var open = false
    @State private var tapCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                withMotion(.reveal) { open.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Text(open ? "Mood, anxiety, irritability" : summary)
                    Image(systemName: "chevron.down")
                        .font(.scaled(size: 11, weight: .bold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .accessibilityHidden(true)
                    Spacer()
                }
                .font(.bodyEmphasis)
                .foregroundStyle(Accent.orange.ink(scheme))
                .frame(minHeight: Sizes.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open {
                ForEach(AppModel.MoodScale.allCases, id: \.self) { scale in
                    MoodDotsRow(scale: scale, value: model.moodToday[scale]) { value in log(scale, value) }
                }
                .motionTransition(.reveal, edge: .top)
            }
        }
        .sensoryFeedback(.selection, trigger: tapCount)
    }

    /// "Mood, anxiety, irritability (2 of 3 today)".
    private var summary: String {
        let done = model.moodToday.count
        return done == 0 ? "Add mood, anxiety, irritability" : "Mood, anxiety, irritability (\(done) of 3 today)"
    }

    private func log(_ scale: AppModel.MoodScale, _ value: Int) {
        let entry = withMotion(.select) { model.logMood(scale, value) }
        toast = UndoToast("Logged \(AppModel.moodTitle(scale).lowercased()): \(AppModel.moodWord(scale, value).lowercased()).") {
            withMotion(.undo) { model.removeMood(entry.id) }
        }
        tapCount += 1
    }
}

/// One scale: its name, five dots and the word for the chosen one.
struct MoodDotsRow: View {
    let scale: AppModel.MoodScale
    let value: Int?
    let pick: (Int) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppModel.moodTitle(scale)).font(.secondary).fontWeight(.semibold)
                Spacer(minLength: Space.s)
                Text(value.map { AppModel.moodWord(scale, $0) } ?? (scale == .mood ? "Very low \u{2192} very good" : "None \u{2192} a lot"))
                    .font(.secondary).foregroundStyle(p.secondary)
            }
            HStack(spacing: Space.s) {
                ForEach(1...5, id: \.self) { n in
                    let on = value == n
                    Button { pick(n) } label: {
                        Circle()
                            .fill(on ? MoodColor.fill(scale, n, scheme) : p.chip)
                            .overlay(Circle().strokeBorder(on ? MoodColor.fill(scale, n, scheme) : p.cardBorder, lineWidth: 1.5))
                            .overlay(Text("\(n)").font(.secondary).fontWeight(.bold)
                                .foregroundStyle(on ? Color(hex: 0x1A0E00) : p.secondary))
                            .frame(width: 40, height: 40)
                            .frame(maxWidth: .infinity, minHeight: Sizes.minTap)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("\(AppModel.moodTitle(scale)) \(n), \(AppModel.moodWord(scale, n))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// Mood colours: mint for a good mood or little anxiety, coral the other
/// way, yellow in the middle.
enum MoodColor {
    /// 0 (worst) … 1 (best) for a value on `scale`.
    static func goodness(_ scale: AppModel.MoodScale, _ value: Double) -> Double {
        let x = (value - 1) / 4
        return scale == .mood ? x : 1 - x
    }

    static func fill(_ scale: AppModel.MoodScale, _ value: Int, _ scheme: ColorScheme) -> Color {
        let g = goodness(scale, Double(value))
        if g >= 0.7 { return Accent.mint.fill(scheme) }
        if g >= 0.4 { return Accent.yellow.fill(scheme) }
        return Accent.coral.fill(scheme)
    }
}

// MARK: - Mood by pack day

/// "Your mood by pack day": every rated day as a dot on its pack day, the
/// average across packs as a line, the break week shaded. Shows after two
/// packs of ratings; until then says how far along she is.
struct MoodByPackDayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var scale: AppModel.MoodScale = .mood
    /// The pack day picked on the chart (a whole number, as a Double like the axis).
    @State private var selected: Double?

    var body: some View {
        Screen(title: "Mood by pack day", accent: .orange) {
            SampleDataBanner()
            if let pack = model.pillPack, let data = model.moodByPackDay(scale) {
                header(data, pack: pack)
                Picker("Scale", selection: $scale) {
                    ForEach(AppModel.MoodScale.allCases, id: \.self) { Text(AppModel.moodTitle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: scale) { _, _ in selected = nil }
                if data.isReady {
                    chartCard(data, pack: pack)
                } else {
                    Card {
                        Label("Rate \(AppModel.moodTitle(scale).lowercased()) most days on the Log tab. The chart fills in after \(MoodByPackDay.packsNeeded) packs.",
                              systemImage: "chart.dots.scatter")
                            .font(.bodyText).secondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(CycleCare.moodOnHormones)
                    .font(.secondary).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func header(_ data: MoodByPackDay, pack: PillPack) -> some View {
        let split = data.split(activeDays: pack.activeDays)
        var pairs: [StatPair] = []
        if let a = split.active { pairs.append(StatPair(label: "Active pills", value: String(format: "%.1f", a))) }
        if pack.hasBreak, let b = split.breakDays { pairs.append(StatPair(label: model.packBreakName, value: String(format: "%.1f", b))) }
        return SummaryHeader(eyebrow: "\(AppModel.moodTitle(scale)), 1 to 5",
                             value: data.isReady ? verdict(split, pack: pack) : "\(data.packsCovered) of \(MoodByPackDay.packsNeeded) packs",
                             line: data.isReady ? "Each dot is a day you rated, placed on its pack day. The line is your average." : "A pack counts once you\u{2019}ve rated \(MoodByPackDay.daysPerPack) days of it.",
                             pairs: data.isReady ? pairs : [], accent: .orange, info: Self.explanation)
    }

    /// "Lower in your break week", "About the same all pack".
    private func verdict(_ split: (active: Double?, breakDays: Double?), pack: PillPack) -> String {
        guard pack.hasBreak, let a = split.active, let b = split.breakDays else { return "Your pattern" }
        let worse = scale == .mood ? a - b : b - a
        if worse >= MoodPattern.meaningfulShift { return scale == .mood ? "Lower in your break" : "Higher in your break" }
        if worse <= -MoodPattern.meaningfulShift { return scale == .mood ? "Higher in your break" : "Lower in your break" }
        return "About the same all pack"
    }

    static let explanation = Explanation(
        id: "moodByPackDay", title: "Mood by pack day",
        meaning: "Your daily 1 to 5 ratings, placed on the day of your pack they fell on. Rating every day for a few packs is the standard way to tell a pattern from one bad week.",
        forYou: "Mood changes on hormonal birth control are real for some people, and many notice nothing. If your break week stands out, a shorter break or skipping it is something to ask about at your pill visit.")

    private func chartCard(_ data: MoodByPackDay, pack: PillPack) -> some View {
        let days = Array(1...pack.packLength)
        let shown = selected.map { Int($0) }
        return Card {
            readout(data, day: shown, pack: pack)
            Chart {
                if pack.hasBreak {
                    RectangleMark(xStart: .value("Break start", Double(pack.activeDays) + 0.5),
                                  xEnd: .value("Break end", Double(pack.packLength) + 0.5))
                        .foregroundStyle(Accent.pink.fill(scheme).opacity(0.14))
                }
                ForEach(data.points, id: \.self) { pt in
                    PointMark(x: .value("Pack day", Double(pt.day)), y: .value("Rating", pt.value))
                        .foregroundStyle(MoodColor.fill(scale, pt.value, scheme).opacity(0.55))
                        .symbolSize(28)
                }
                ForEach(days.filter { data.averages[$0] != nil }, id: \.self) { d in
                    LineMark(x: .value("Pack day", Double(d)), y: .value("Average", data.averages[d] ?? 0))
                        .foregroundStyle(Accent.orange.ink(scheme))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                if let d = shown {
                    RuleMark(x: .value("Pack day", Double(d)))
                        .foregroundStyle(Palette(scheme: scheme).tertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: 0.5...(Double(pack.packLength) + 0.5))
            .chartYScale(domain: 0.5...5.5)
            .chartYAxis { AxisMarks(values: [1, 3, 5]) }
            .chartXAxis { AxisMarks(values: [1, 7, 14, 21, pack.packLength].map(Double.init)) { v in
                AxisGridLine()
                AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))") }
            } }
            .chartScrub($selected.snapping { raw in Self.nearestDay(raw, in: pack) }, snapped: selected, steps: days.map(Double.init))
            .frame(height: 190)
            .accessibilityChartDescriptor(ValueChartDescriptor(
                title: "\(AppModel.moodTitle(scale)) by pack day", seriesName: "Average", xTitle: "Pack day", yTitle: "Rating",
                points: days.compactMap { d in data.averages[d].map { (Double(d), $0) } },
                xLabel: { "Day \(Int($0))" }, yLabel: { String(format: "%.1f", $0) }))
            HStack(spacing: Space.m) {
                legendSwatch(Accent.pink.fill(scheme).opacity(0.3), model.packBreakName)
                legendSwatch(Accent.orange.ink(scheme), "Average")
            }
            ScrubHint(each: "pack day")
        }
    }

    private static func nearestDay(_ raw: Double, in pack: PillPack) -> Double { Double(min(max(Int(raw.rounded()), 1), pack.packLength)) }

    private func readout(_ data: MoodByPackDay, day: Int?, pack: PillPack) -> some View {
        let slots = (1...pack.packLength).map { detail(data, day: $0, pack: pack) }
        if let day {
            let avg = data.averages[day]
            return ChartReadout(title: "Pack day \(day)\(day > pack.activeDays ? " \u{00B7} \(model.packBreakName.lowercased())" : "")",
                                value: avg.map { String(format: "%.1f", $0) } ?? "No ratings",
                                detail: detail(data, day: day, pack: pack), accent: .orange,
                                onClear: { selected = nil }, detailSlots: slots)
        }
        return ChartReadout(title: "All \(data.points.count) days you rated", value: "\(data.packsCovered) packs",
                            detail: "Drag to see a pack day\u{2019}s average.", accent: .orange, detailSlots: slots)
    }

    /// "4 ratings: okay to good."
    private func detail(_ data: MoodByPackDay, day: Int, pack: PillPack) -> String {
        let values = data.points.filter { $0.day == day }.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return "No ratings on this day of a pack yet." }
        let range = lo == hi ? AppModel.moodWord(scale, lo).lowercased()
            : "\(AppModel.moodWord(scale, lo).lowercased()) to \(AppModel.moodWord(scale, hi).lowercased())"
        return "\(values.count) rating\(values.count == 1 ? "" : "s"): \(range)."
    }

    private func legendSwatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 10).accessibilityHidden(true)
            Text(text).font(.secondary).fontWeight(.semibold).secondaryText()
        }
    }
}

/// The smallest gap between break-week and active-pill averages (on the 1–5
/// scale) the app calls a difference.
enum MoodPattern {
    static let meaningfulShift = 0.5
}
