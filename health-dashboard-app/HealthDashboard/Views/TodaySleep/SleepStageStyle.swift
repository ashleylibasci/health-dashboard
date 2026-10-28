import SwiftUI
import Charts
import HealthCore

// Small pieces shared by the Today, Sleep and stage screens.

/// Names and colors for sleep stages, from the designs.
enum StageStyle {
    /// Top to bottom in a hypnogram.
    static let lanes: [SleepStage] = [.awake, .rem, .core, .deep]
    /// Order for legends and stacked bars.
    static let legend: [SleepStage] = [.deep, .rem, .core, .awake]

    static func name(_ stage: SleepStage) -> String {
        switch stage {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Core"
        case .deep: return "Deep"
        }
    }

    /// Bar and segment fill.
    static func color(_ stage: SleepStage, _ scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch stage {
        case .deep: return Color(hex: dark ? 0x5B6BE8 : 0x2E3AA8)
        case .core: return Color(hex: dark ? 0x7C8BFF : 0x6574EA)
        case .rem: return Color(hex: dark ? 0xB9A9FF : 0xB79BF5)
        case .awake: return Color(hex: dark ? 0xFF9A7A : 0xF08A68)
        }
    }

    /// The explanation topic for each stage.
    static func topic(_ stage: SleepStage) -> Topic {
        switch stage {
        case .awake: return .awake
        case .rem: return .rem
        case .core: return .core
        case .deep: return .deep
        }
    }

    /// One plain sentence on what the stage does.
    static func oneLiner(_ stage: SleepStage) -> String {
        switch stage {
        case .deep: return "Deep sleep: your body repairs itself. Most of it comes early in the night."
        case .rem: return "REM: the dreaming stage, when your brain sorts memories and what you learned."
        case .core: return "Core (light) sleep: about half the night, and the easiest stage to wake from."
        case .awake: return "Awake: a brief stir. A few are normal and you usually won't remember them."
        }
    }

    static func accent(_ stage: SleepStage) -> Accent {
        switch stage {
        case .deep, .core: return .indigo
        case .rem: return .purple
        case .awake: return .coral
        }
    }

    /// Text color for stage labels.
    static func ink(_ stage: SleepStage, _ scheme: ColorScheme) -> Color {
        switch stage {
        case .deep, .core: return Accent.indigo.ink(scheme)
        case .rem: return Accent.purple.ink(scheme)
        case .awake: return Accent.coral.ink(scheme)
        }
    }
}

/// Number formats used on these screens.
enum SleepText {
    /// "−6", "+2", "+1.5" with a true minus sign; "0" for zero.
    static func signed(_ value: Double, decimals: Int = 0) -> String {
        let magnitude = decimals == 0 ? String(Int(abs(value).rounded())) : String(format: "%.\(decimals)f", abs(value))
        if (Double(magnitude) ?? 0) == 0 { return magnitude }
        return (value < 0 ? "\u{2212}" : "+") + magnitude
    }

    /// "14m", "1h 12m".
    static func compact(_ minutes: Int) -> String {
        let m = abs(minutes)
        return m < 60 ? "\(m)m" : Clock.duration(m)
    }

    /// "−29m", "+2m", "0m".
    static func signedCompact(_ minutes: Int) -> String {
        if minutes == 0 { return "0m" }
        return (minutes < 0 ? "\u{2212}" : "+") + compact(minutes)
    }

    /// Where the sleep need comes from: "learned from 42 nights", or while the
    /// numbers are still examples, "example until 14 nights (3 of 14 so far)".
    @MainActor
    static func needSource(_ model: AppModel) -> String {
        if model.sleepNeedIsExample {
            let n = min(model.realNightCount, AppModel.nightsNeeded)
            return "example until \(AppModel.nightsNeeded) nights (\(n) of \(AppModel.nightsNeeded) so far)"
        }
        let n = model.sleepNeedNightsUsed
        return "learned from \(n) \(n == 1 ? "night" : "nights")"
    }

    /// "am" or "pm" for a clock time.
    static func meridiem(_ minutes: Minutes) -> String {
        String(Clock.format(minutes).suffix(2))
    }
}

/// A 12-hour clock dial with the sleep window drawn as an arc.
struct SleepArcDial: View {
    var start: Minutes
    var end: Minutes
    var size: CGFloat
    var lineWidth: CGFloat
    var colors: [Color]
    var label: String
    var labelSize: CGFloat
    var caption: String? = nil
    var showHours = false
    @Environment(\.colorScheme) private var scheme

    /// Hour digits grow with the text size, but only up to 15pt so they stay on the dial.
    private var hourFontSize: CGFloat { min(Font.scaledSize(11), 15) }

    private var startFraction: Double { Double(((start % 720) + 720) % 720) / 720 }
    private var lengthFraction: Double { min(max(Double(end - start) / 720, 0.01), 1) }

    var body: some View {
        let p = Palette(scheme: scheme)
        ZStack {
            Circle().stroke(p.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: lengthFraction)
                .stroke(AngularGradient(colors: colors, center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * lengthFraction)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90 + 360 * startFraction))
            if showHours {
                ForEach([12, 3, 6, 9], id: \.self) { hour in
                    let angle = Double(hour % 12) / 12 * 2 * Double.pi
                    let radius = size / 2 - lineWidth - hourFontSize * 0.9
                    Text("\(hour)")
                        .font(.system(size: hourFontSize, weight: .semibold))
                        .foregroundStyle(p.tertiary)
                        .offset(x: CGFloat(sin(angle)) * radius, y: -CGFloat(cos(angle)) * radius)
                        .accessibilityHidden(true)
                }
            }
            // The number and caption shrink to stay inside the dial at large text sizes.
            VStack(spacing: 1) {
                Text(label).font(.scaledNumber(labelSize)).minimumScaleFactor(0.35).lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.scaled(size: 12, weight: .semibold))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                }
            }
            .padding(.horizontal, lineWidth + (showHours ? hourFontSize * 1.8 : 4))
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)\(caption.map { " " + $0 } ?? ""), from \(Clock.format(start)) to \(Clock.format(end))")
    }
}

/// Last night's stages as one row per stage: names in a fixed column on the
/// left (each with an info button), bars in the remaining width. Touch and
/// drag across the bars to see the time, the stage and what it does.
struct StageTimeline: View {
    var segments: [StageSegment]
    @State private var selected: Date? = nil
    @Environment(\.colorScheme) private var scheme

    // The label column and rows grow with the text size so stage names aren't cut off.
    private var labelWidth: CGFloat { min(max(84, Font.scaledSize(84)), 150) }
    private var rowHeight: CGFloat { min(max(28, Font.scaledSize(24)), 48) }
    private let rowGap: CGFloat = 6
    private var barHeight: CGFloat { max(18, rowHeight - 10) }

    private struct Item: Identifiable {
        let id: Int
        let segment: StageSegment
    }

    private var items: [Item] { segments.enumerated().map { Item(id: $0.offset, segment: $0.element) } }
    private var start: Date { segments.first?.start ?? .now }
    private var end: Date { segments.last?.end ?? .now }
    private var span: TimeInterval { max(end.timeIntervalSince(start), 60) }
    private var lanesHeight: CGFloat { CGFloat(StageStyle.lanes.count) * rowHeight + CGFloat(StageStyle.lanes.count - 1) * rowGap }

    private func laneIndex(_ stage: SleepStage) -> Int { StageStyle.lanes.firstIndex(of: stage) ?? 0 }
    private func laneY(_ stage: SleepStage) -> CGFloat { CGFloat(laneIndex(stage)) * (rowHeight + rowGap) }

    private func x(_ date: Date, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(start) / span, 0), 1)) * width
    }

    private func date(atX x: CGFloat, _ width: CGFloat) -> Date {
        let f = Double(min(max(x / max(width, 1), 0), 1))
        return start.addingTimeInterval(f * span)
    }

    private func segment(at date: Date) -> StageSegment? {
        segments.first { $0.start <= date && date < $0.end } ?? segments.last
    }

    private func clock(_ date: Date) -> String { Clock.format(Clock.minutesOfDay(date)) }

    private var summary: String {
        let parts = StageStyle.legend.map { stage -> String in
            let minutes = segments.filter { $0.stage == stage }.map(\.minutes).reduce(0, +)
            return "\(StageStyle.name(stage)) \(Clock.duration(minutes))"
        }
        return "Sleep stages from \(clock(start)) to \(clock(end)): " + parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var readout: some View {
        if let selected, let seg = segment(at: selected) {
            ChartReadout(title: "\(clock(selected)) \u{00B7} \(SleepText.compact(seg.minutes)) stretch",
                         value: StageStyle.name(seg.stage),
                         detail: StageStyle.oneLiner(seg.stage),
                         accent: StageStyle.accent(seg.stage))
        } else {
            ChartReadout(title: "Last night \u{00B7} \(clock(start)) to \(clock(end))",
                         value: "Touch a bar",
                         detail: "Deep sleep comes early in the night, REM toward morning. Brief wake-ups are normal.",
                         accent: .purple)
        }
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: rowGap) {
            ForEach(StageStyle.lanes, id: \.self) { stage in
                HStack(spacing: 0) {
                    Text(StageStyle.name(stage))
                        .font(.scaled(size: 13, weight: .bold))
                        .foregroundStyle(StageStyle.ink(stage, scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    InfoButton(topic: StageStyle.topic(stage))
                        .padding(.vertical, -8)
                        .padding(.horizontal, -6)
                }
                .frame(width: labelWidth, height: rowHeight)
            }
        }
        .frame(width: labelWidth)
    }

    private func bars(_ width: CGFloat) -> some View {
        let p = Palette(scheme: scheme)
        return ZStack(alignment: .topLeading) {
            ForEach(StageStyle.lanes, id: \.self) { stage in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(p.track.opacity(0.6))
                    .frame(width: width, height: barHeight)
                    .offset(y: laneY(stage) + (rowHeight - barHeight) / 2)
            }
            ForEach(items) { item in
                let seg = item.segment
                let x0 = x(seg.start, width)
                let w = max(x(seg.end, width) - x0, 2)
                let dim = selected != nil && segment(at: selected ?? .now) != seg
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(StageStyle.color(seg.stage, scheme))
                    .opacity(dim ? 0.45 : 1)
                    .frame(width: w, height: barHeight)
                    .offset(x: x0, y: laneY(seg.stage) + (rowHeight - barHeight) / 2)
            }
            if let selected, let seg = segment(at: selected) {
                let sx = x(selected, width)
                Rectangle()
                    .fill(p.primary.opacity(0.7))
                    .frame(width: 2, height: lanesHeight)
                    .offset(x: sx - 1)
                Circle()
                    .fill(StageStyle.color(seg.stage, scheme))
                    .overlay(Circle().strokeBorder(p.primary, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: sx - 7, y: laneY(seg.stage) + (rowHeight - 14) / 2)
            }
        }
        .frame(width: width, height: lanesHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay(ScrubSurface { location in selected = date(atX: location.x, width) })
        .scrubFeedback(selected.flatMap { segment(at: $0) })
    }

    private var axis: some View {
        let mid = start.addingTimeInterval(span / 2)
        return HStack {
            Text(clock(start))
            Spacer()
            Text(clock(mid))
            Spacer()
            Text(clock(end))
        }
        .font(.scaled(size: 11, weight: .semibold))
        .secondaryText()
        .padding(.leading, labelWidth + 8)
        .accessibilityHidden(true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            readout
            HStack(alignment: .top, spacing: 8) {
                labelColumn
                GeometryReader { geo in
                    bars(geo.size.width)
                }
                .frame(height: lanesHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
            }
            axis
            ScrubHint(text: "Touch and drag across the bars to see each stage")
        }
    }
}

/// Stage minutes as one stacked bar, used when there are no segments.
struct StageStackBar: View {
    var minutes: [SleepStage: Int]
    var height: CGFloat = 20
    @Environment(\.colorScheme) private var scheme

    private struct Part: Identifiable {
        var id: SleepStage { stage }
        let stage: SleepStage
        let minutes: Int
    }

    private var parts: [Part] {
        StageStyle.legend.map { Part(stage: $0, minutes: minutes[$0] ?? 0) }.filter { $0.minutes > 0 }
    }

    var body: some View {
        let total = max(parts.map(\.minutes).reduce(0, +), 1)
        GeometryReader { geo in
            let usable = max(geo.size.width - CGFloat(max(parts.count - 1, 0)) * 3, 0)
            HStack(spacing: 3) {
                ForEach(parts) { part in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(StageStyle.color(part.stage, scheme))
                        .frame(width: max(6, usable * CGFloat(part.minutes) / CGFloat(total)))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.map { "\(StageStyle.name($0.stage)) \(Clock.duration($0.minutes))" }.joined(separator: ", "))
    }
}

/// The four stage legend items: one row when they fit, two rows of two at large text sizes.
struct StageLegendRow: View {
    var minutes: [SleepStage: Int]

    private func item(_ stage: SleepStage) -> some View {
        StageLegendItem(stage: stage, minutes: minutes[stage] ?? 0)
    }

    var body: some View {
        let stages = StageStyle.legend
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(stages, id: \.self) { item($0) }
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: stages.count, by: 2)), id: \.self) { i in
                    GridRow {
                        item(stages[i])
                        if i + 1 < stages.count { item(stages[i + 1]) }
                    }
                }
            }
        }
    }
}

/// A stage name, color dot and duration, for legends.
struct StageLegendItem: View {
    var stage: SleepStage
    var minutes: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(StageStyle.color(stage, scheme)).frame(width: 8, height: 8)
                Text(StageStyle.name(stage)).font(.scaled(size: 12, weight: .bold)).foregroundStyle(StageStyle.ink(stage, scheme))
                    .fixedSize()
            }
            Text(SleepText.compact(minutes)).font(.scaled(size: 15, weight: .bold)).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
