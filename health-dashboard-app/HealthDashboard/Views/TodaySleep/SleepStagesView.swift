import SwiftUI
import Charts
import HealthCore

/// Last night, stage by stage, against her usual.
struct SleepStagesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedAngle: Int? = nil

    var body: some View {
        Screen(title: "Sleep stages", accent: .purple) {
            SampleDataBanner()
            Text("Last night, stage by stage")
                .font(.scaled(size: 28, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if model.lastNightIsFresh {
                donutCard
                lanesCard
                stageRows
                meaningCard
            } else {
                Card {
                    Text("No sleep recorded last night").font(.scaled(size: 17, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Wear your Watch to bed and turn on Sleep Focus, and tomorrow's stages show up here.")
                        .font(.scaled(size: 14)).secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                    LinkRow(title: "How to get your sleep recorded", systemImage: "applewatch", accent: .purple) {
                        AccuracyTipsView()
                    }
                }
            }
            NavigationLink {
                SleepHistoryView()
            } label: {
                HStack(spacing: 6) {
                    Text("See your week and month").font(.scaled(size: 15, weight: .semibold))
                    Image(systemName: "chevron.right").font(.scaled(size: 12, weight: .bold)).accessibilityHidden(true)
                }
                .foregroundStyle(Accent.purple.ink(scheme))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Data

    private func minutes(_ stage: SleepStage) -> Int { model.lastNight.stageMinutes[stage] ?? 0 }

    /// Her usual minutes per stage: the average of tracked nights when there
    /// are at least a week of them, otherwise typical values for her.
    private func usual(_ stage: SleepStage) -> Int? {
        let tracked = model.sessions.suffix(30)
        if tracked.count >= 7 {
            let total = tracked.map { $0.minutes(in: stage) }.reduce(0, +)
            return Int((Double(total) / Double(tracked.count)).rounded())
        }
        switch stage {
        case .deep: return 70
        case .rem: return 105
        case .core: return 290
        case .awake: return nil
        }
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

    private var donutReadout: some View {
        let night = model.lastNight
        let total = max(slices.map(\.minutes).reduce(0, +), 1)
        return Group {
            if let slice = selectedSlice {
                ChartReadout(title: "\(StageStyle.name(slice.stage)) \u{00B7} \(Int((Double(slice.minutes) / Double(total) * 100).rounded()))% of the night",
                             value: Clock.duration(slice.minutes),
                             detail: StageStyle.oneLiner(slice.stage),
                             accent: StageStyle.accent(slice.stage),
                             onClear: { selectedAngle = nil })
            } else {
                ChartReadout(title: "Last night", value: "\(Clock.duration(night.asleep)) asleep",
                             detail: "Touch a slice to see each stage.", accent: .purple)
            }
        }
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
        .scrubFeedback(selectedSlice?.stage)
        .accessibilityLabel("Sleep stages last night: " + slices.map { "\(StageStyle.name($0.stage)) \(Clock.duration($0.minutes))" }.joined(separator: ", "))
    }

    private var donutCard: some View {
        let p = Palette(scheme: scheme)
        let night = model.lastNight
        let summary = slices.map { "\(StageStyle.name($0.stage)) \(Clock.duration($0.minutes))" }.joined(separator: ", ")
        let donut = ZStack {
            donutChart
            VStack(spacing: 0) {
                Text(Clock.duration(night.asleep)).font(.scaledNumber(20)).minimumScaleFactor(0.7).lineLimit(1)
                Text("asleep").font(.scaled(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
            }
            .padding(.horizontal, 30)
            .allowsHitTesting(false)
        }
        .frame(width: 150, height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Clock.duration(night.asleep)) asleep: \(summary)")
        let times = VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Fell asleep")
                Text(Clock.format(night.onset)).font(.scaledNumber(22))
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Woke up")
                Text(Clock.format(night.wake)).font(.scaledNumber(22))
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
            ScrubHint(text: "Touch a slice to see that stage")
        }
    }

    // MARK: Lanes

    private var lanesCard: some View {
        let night = model.lastNight
        let timeline = model.lastNightTimeline
        return Card {
            ExplainedTitle(text: "Through the night", topic: .sleepStages)
            if timeline.isEmpty {
                StageStackBar(minutes: night.stageMinutes, height: 24)
                Text("Stage-by-stage timing shows up once your Watch records a night in Apple Health.")
                    .font(.scaled(size: 13))
                    .secondaryText()
            } else {
                StageTimeline(segments: timeline)
            }
        }
    }

    // MARK: Rows

    private var stageRows: some View {
        VStack(spacing: 10) {
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
        } else {
            note = typical.map { "usual \(SleepText.compact($0))" } ?? ""
        }
        let deltaGood = (delta ?? 0) >= -10
        return HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(StageStyle.color(stage, scheme))
                .frame(width: 6, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text(StageStyle.name(stage).uppercased())
                            .font(.scaled(size: 12, weight: .bold))
                            .foregroundStyle(StageStyle.ink(stage, scheme))
                        InfoButton(topic: StageStyle.topic(stage)).padding(.vertical, -14).padding(.horizontal, -8)
                    }
                    if let delta, stage != .awake {
                        // Under 10 minutes is within the Watch's error (N16).
                        Text(abs(delta) < 10 ? "about usual" : SleepText.signedCompact(delta))
                            .font(.scaled(size: 12, weight: .bold))
                            .foregroundStyle((deltaGood ? Accent.mint : Accent.coral).ink(scheme))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background((deltaGood ? Accent.mint : Accent.coral).tint(scheme), in: Capsule())
                    }
                }
                Text(note).font(.scaled(size: 13)).foregroundStyle(p.secondary)
                Text(StageStyle.oneLiner(stage))
                    .font(.scaled(size: 12))
                    .foregroundStyle(p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(SleepText.compact(value)).font(.scaledNumber(22))
        }
        .padding(14)
        .background(p.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.cardBorder))
        .accessibilityElement(children: .contain)
    }

    // MARK: Meaning

    private var meaning: String {
        var text = "Deep sleep repairs your body; REM sorts what you learned."
        let deepOK = usual(.deep).map { minutes(.deep) >= $0 - 10 } ?? true
        let remOK = usual(.rem).map { minutes(.rem) >= $0 - 10 } ?? true
        switch (deepOK, remOK) {
        case (true, true): text += " Both held up last night."
        case (false, false): text += " Both ran short last night."
        case (true, false): text += " Deep sleep held up, but REM ran short. REM comes late in the night, so a short night cuts it first."
        case (false, true): text += " REM held up, but deep sleep ran short."
        }
        if let usualCore = usual(.core) {
            let gap = usualCore - minutes(.core)
            if gap >= 15 {
                let later = model.lastNight.bedtime > store.data.bedtime + 15
                text += " Core sleep ran \(gap) minutes short" + (later ? ", mostly from the later bedtime." : ".")
            }
        }
        return text
    }

    private var meaningCard: some View {
        Card(accent: .purple) {
            SectionLabel(text: "What it means", accent: .purple)
            Text(meaning)
                .font(.scaled(size: 15))
                .fixedSize(horizontal: false, vertical: true)
            HowWeGotThisLink(title: "Your usual stages",
                             method: "Your usual for each stage is the average of your last 30 tracked nights once you have at least a week of them. Before that we use typical values for someone your age. The Watch estimates stages from movement and heart rate, so treat single nights as rough and look at the trend.")
        }
    }
}
