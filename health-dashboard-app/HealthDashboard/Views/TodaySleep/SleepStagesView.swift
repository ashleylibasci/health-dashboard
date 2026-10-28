import SwiftUI
import Charts
import HealthCore

/// Last night, stage by stage, against her usual.
struct SleepStagesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedAngle: Int? = nil
    @State private var explaining: Explanation? = nil

    var body: some View {
        Screen(title: "Sleep stages", accent: .purple) {
            SampleDataBanner()
            // One title: the inline nav title, then the hero (Valtonen F8).
            if model.lastNightIsFresh {
                donutCard
                RowCard {
                    ExpandRow(title: "Through the night",
                              summary: "\(Clock.format(model.lastNight.onset)) to \(Clock.format(model.lastNight.wake)), stage by stage",
                              systemImage: "waveform.path", accent: .purple) {
                        lanes
                    }
                    RowDivider()
                    ExpandRow(title: "Each stage against your usual", summary: "Deep, REM, core and awake",
                              systemImage: "list.bullet", accent: .purple) {
                        stageRows
                    }
                    RowDivider()
                    ExpandRow(title: "What it means", summary: meaningSummary,
                              systemImage: "text.bubble.fill", accent: .purple) {
                        meaningContent
                    }
                }
            } else {
                Card {
                    Text("No sleep recorded last night").font(.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("Wear your Watch to bed and turn on Sleep Focus, and tomorrow's stages show up here.")
                        .font(.bodyText).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                    LinkRow(title: "How to get your sleep recorded", systemImage: "applewatch", accent: .purple) {
                        AccuracyTipsView()
                    }
                }
            }
        }
        .sheet(item: $explaining) { ExplanationSheet(explanation: $0) }
    }

    // MARK: Data

    private func minutes(_ stage: SleepStage) -> Int { model.lastNight.stageMinutes[stage] ?? 0 }

    /// Her usual minutes per stage: the average of her tracked nights once
    /// there are at least a week of them. Nil before that: fixed "typical"
    /// minutes don't fit everyone (women tend to get more deep sleep, the
    /// pill a little less), so until then a stage is shown as a share of the
    /// night against a typical range (Park 11, Liu 3).
    private func usual(_ stage: SleepStage) -> Int? {
        let tracked = model.sessions.suffix(30)
        guard tracked.count >= 7, stage != .awake else { return nil }
        let total = tracked.map { $0.minutes(in: stage) }.reduce(0, +)
        return Int((Double(total) / Double(tracked.count)).rounded())
    }

    /// A gap smaller than this is within the Watch's error for a single
    /// night, so it reads "about usual" (Park 11: 25 minutes).
    private let meaningfulGap = 25

    /// A typical share of the night for adults in their late teens and
    /// twenties, as a percentage range.
    private func typicalShare(_ stage: SleepStage) -> ClosedRange<Int>? {
        switch stage {
        case .deep: return 13...25
        case .rem: return 20...25
        case .core: return 50...60
        case .awake: return nil
        }
    }

    /// Last night's share of sleep in a stage, as a whole percentage.
    private func share(_ stage: SleepStage) -> Int? {
        let asleep = model.lastNight.asleep
        guard asleep > 0 else { return nil }
        return Int((Double(minutes(stage)) / Double(asleep) * 100).rounded())
    }

    private var wakeUps: Int? {
        let segments = model.lastNight.segments
        guard !segments.isEmpty else { return nil }
        return segments.filter { $0.stage == .awake }.count
    }

    private struct Slice: Identifiable {
        var id: SleepStage { stage }
        let stage: SleepStage
        let minutes: Int
    }

    private var slices: [Slice] {
        [SleepStage.core, .rem, .deep, .awake].map { Slice(stage: $0, minutes: minutes($0)) }.filter { $0.minutes > 0 }
    }

    // MARK: Donut

    /// The slice under the finger: SectorMark selection reports a running
    /// total of minutes, so walk the slices until it's reached.
    private var selectedSlice: Slice? {
        guard let selectedAngle else { return nil }
        var running = 0
        for slice in slices {
            running += slice.minutes
            if selectedAngle <= running { return slice }
        }
        return slices.last
    }

    private var donutSlots: [String] { [inBedSummary] + SleepStage.allCases.map(StageStyle.oneLiner) }

    private var donutReadout: some View {
        let night = model.lastNight
        let total = max(slices.map(\.minutes).reduce(0, +), 1)
        return Group {
            if let slice = selectedSlice {
                ChartReadout(title: "\(StageStyle.name(slice.stage)) \u{00B7} \(Int((Double(slice.minutes) / Double(total) * 100).rounded()))% of the night",
                             value: Clock.duration(slice.minutes),
                             detail: StageStyle.oneLiner(slice.stage),
                             accent: StageStyle.accent(slice.stage),
                             onClear: { selectedAngle = nil }, detailSlots: donutSlots)
            } else {
                // At rest: the night's total and its shape (Valtonen F13).
                ChartReadout(title: "Last night \u{00B7} asleep", value: Clock.duration(night.asleep),
                             detail: inBedSummary,
                             accent: .purple, detailSlots: donutSlots)
            }
        }
    }

    /// "Asleep for 94% of your 7h 49m in bed." (the timeline below says
    /// where the stages fall, so the two readouts don't repeat each other).
    private var inBedSummary: String {
        let night = model.lastNight
        let inBed = night.wake - night.bedtime
        guard inBed > 0, night.asleep > 0 else { return "Each slice is one stage of last night\u{2019}s sleep." }
        let pct = min(Int((Double(night.asleep) / Double(inBed) * 100).rounded()), 100)
        return "Asleep for \(pct)% of your \(Clock.duration(inBed)) in bed. Each slice is one stage."
    }

    private var donutChart: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value("Minutes", slice.minutes), innerRadius: .ratio(0.7), angularInset: 1.5)
                .foregroundStyle(StageStyle.color(slice.stage, scheme))
                .opacity(selectedSlice == nil || selectedSlice?.stage == slice.stage ? 1 : 0.4)
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .chartAngleScrub($selectedAngle, total: slices.reduce(0) { $0 + $1.minutes })
        .accessibilityChartDescriptor(CategoryChartDescriptor(
            title: "Sleep stages last night", seriesName: "Stage", yTitle: "Minutes",
            points: slices.map { (StageStyle.name($0.stage), Double($0.minutes)) },
            yLabel: { Clock.duration(Int($0.rounded())) }))
        .scrubFeedback(selectedSlice?.stage)
        .accessibilityLabel("Sleep stages last night: " + slices.map { "\(StageStyle.name($0.stage)) \(Clock.duration($0.minutes))" }.joined(separator: ", "))
    }

    private var donutCard: some View {
        let p = Palette(scheme: scheme)
        let night = model.lastNight
        let summary = slices.map { "\(StageStyle.name($0.stage)) \(Clock.duration($0.minutes))" }.joined(separator: ", ")
        // The total sits in the hole only while it fits there; at the
        // accessibility sizes it moves under the ring, never cut off to
        // "7h 2…" (Ortiz F1).
        let totalInside = !typeSize.isAccessibilitySize
        let donut = VStack(spacing: Space.xs) {
            ZStack {
                donutChart
                if totalInside {
                    VStack(spacing: 0) {
                        Text(Clock.duration(night.asleep)).font(.numberM).minimumScaleFactor(0.7).lineLimit(1)
                        Text("asleep").font(.secondary).fontWeight(.semibold).foregroundStyle(p.secondary)
                    }
                    .padding(.horizontal, 30)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: 150, height: 150)
            if !totalInside {
                Text("\(Clock.duration(night.asleep)) asleep").font(.numberM)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Clock.duration(night.asleep)) asleep: \(summary)")
        let times = VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                CapsLabel("Fell asleep", isHeader: false)
                Text(Clock.format(night.onset)).font(.numberM)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 2) {
                CapsLabel("Woke up", isHeader: false)
                Text(Clock.format(night.wake)).font(.numberM)
            }
            .accessibilityElement(children: .combine)
        }
        return Card {
            donutReadout
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    donut
                    times
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 14) {
                    donut.frame(maxWidth: .infinity)
                    times
                }
            }
            // The slices' names and minutes (Tanaka F10): the ring alone
            // left you matching colours to the rows further down.
            StageLegendRow(minutes: night.stageMinutes)
            ScrubHint(each: "stage")
        }
    }

    // MARK: Lanes

    @ViewBuilder
    private var lanes: some View {
        let timeline = model.lastNightTimeline
        if timeline.isEmpty {
            StageStackBar(minutes: model.lastNight.stageMinutes, height: 24)
            Text("Stage-by-stage timing shows up once your Watch records a night in Apple Health.")
                .font(.secondary)
        } else {
            StageTimeline(segments: timeline)
        }
    }

    // MARK: Rows

    private var stageRows: some View {
        VStack(spacing: Space.m) {
            ForEach([SleepStage.deep, .rem, .core, .awake], id: \.self) { stage in
                stageRow(stage)
            }
        }
    }

    private func stageRow(_ stage: SleepStage) -> some View {
        let p = Palette(scheme: scheme)
        let value = minutes(stage)
        let typical = usual(stage)
        let delta = typical.map { value - $0 }
        let note: String
        if stage == .awake {
            if let count = wakeUps {
                note = count == 1 ? "1 brief wake-up" : "\(count) brief wake-ups"
            } else {
                note = "Short stirs are normal"
            }
        } else if let typical {
            note = "your usual \(SleepText.compact(typical))"
        } else if let range = typicalShare(stage), let pct = share(stage) {
            note = "\(pct)% of your sleep \u{00B7} typical \(range.lowerBound)\u{2013}\(range.upperBound)%"
        } else {
            note = ""
        }
        // Coral only for a shortfall worth acting on (45 min or more);
        // smaller gaps are neutral, gains mint (Tanaka F10, Valtonen F4).
        let pillAccent: Accent? = delta.map { $0 <= -45 ? .coral : ($0 >= meaningfulGap ? .mint : nil) } ?? nil
        let pillText = delta.map { abs($0) < meaningfulGap ? "about usual" : SleepText.signedCompact($0) }
        let spokenDelta = delta.map { d -> String in
            abs(d) < meaningfulGap ? "about usual" : "\(Clock.duration(abs(d))) \(d < 0 ? "less" : "more") than usual"
        }
        return HStack(alignment: .center, spacing: Space.m) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(StageStyle.color(stage, scheme))
                .frame(width: 6, height: 40)
            VStack(alignment: .leading, spacing: Space.xs) {
                FlowLayout(spacing: Space.s, lineSpacing: Space.xs) {
                    Text(StageStyle.name(stage).uppercased())
                        .font(.caps)
                        .foregroundStyle(StageStyle.ink(stage, scheme))
                    if let pillText, stage != .awake {
                        // Under 25 minutes is within the Watch's error for one night.
                        Text(pillText)
                            .font(.secondary).fontWeight(.bold)
                            .foregroundStyle(pillAccent?.onTint(scheme) ?? p.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(pillAccent?.tint(scheme) ?? p.chip, in: Capsule())
                    }
                }
                Text(note).font(.secondary).foregroundStyle(p.secondary)
                Text(StageStyle.oneLiner(stage))
                    .font(.secondary)
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Text(SleepText.compact(value)).font(.numberM).keepsOnOneLine(minimumScale: 0.7)
        }
        // One element per stage; its explanation is an action, not a
        // separate ⓘ stop (Valtonen F5, Ortiz F9).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([StageStyle.name(stage), Clock.duration(value), stage == .awake ? nil : spokenDelta,
                             note.replacingOccurrences(of: "\u{2013}", with: " to "), StageStyle.oneLiner(stage)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAction(named: "Explain") { explaining = StageStyle.topic(stage).explanation }
    }

    // MARK: Meaning

    private var meaning: String {
        var text = "Deep sleep repairs your body; REM sorts what you learned."
        guard usual(.deep) != nil || usual(.rem) != nil else {
            return text + " After a week of tracked nights, each stage is compared with your own usual. Until then it's shown as a share of your sleep next to a typical range, which varies a lot from person to person."
        }
        let deepOK = usual(.deep).map { minutes(.deep) > $0 - meaningfulGap } ?? true
        let remOK = usual(.rem).map { minutes(.rem) > $0 - meaningfulGap } ?? true
        switch (deepOK, remOK) {
        case (true, true): text += " Both held up last night."
        case (false, false): text += " Both ran short last night."
        case (true, false): text += " Deep sleep held up, but REM ran short. REM comes late in the night, so a short night cuts it first."
        case (false, true): text += " REM held up, but deep sleep ran short."
        }
        if let usualCore = usual(.core) {
            let gap = usualCore - minutes(.core)
            if gap >= meaningfulGap {
                let later = model.lastNight.bedtime > store.data.bedtime + 15
                text += " Core sleep ran \(gap) minutes short" + (later ? ", mostly from the later bedtime." : ".")
            }
        }
        return text
    }

    /// The first verdict for the collapsed row: "Both held up last night."
    private var meaningSummary: String {
        guard usual(.deep) != nil || usual(.rem) != nil else { return "Deep sleep, REM and what they do" }
        let deepOK = usual(.deep).map { minutes(.deep) > $0 - meaningfulGap } ?? true
        let remOK = usual(.rem).map { minutes(.rem) > $0 - meaningfulGap } ?? true
        switch (deepOK, remOK) {
        case (true, true): return "Deep sleep and REM held up"
        case (false, false): return "Deep sleep and REM ran short"
        case (true, false): return "REM ran short"
        case (false, true): return "Deep sleep ran short"
        }
    }

    @ViewBuilder
    private var meaningContent: some View {
        Text(meaning)
            .fixedSize(horizontal: false, vertical: true)
        HowWeGotThisLink(title: "Your usual stages",
                         method: "Your usual for each stage is the average of your last 30 tracked nights once you have at least a week of them. Before that, each stage is shown as a share of your sleep next to a typical range for adults your age; women tend to get a little more deep sleep, and the pill can mean a little less. A difference under 25 minutes is called about usual: the Watch estimates stages from movement and heart rate, so single nights are rough. Look at the trend.")
    }
}
