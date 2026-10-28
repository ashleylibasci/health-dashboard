import SwiftUI
import Charts
import HealthCore

/// The cost of a late night: nights in bed well after her usual bedtime
/// (90 minutes past it, or 2am until it's known) compared with her other
/// nights, the night itself and the two days after.
struct LateNightView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme

    @State private var selectedDay: Date? = nil

    /// "2:00am"
    private var thresholdText: String { Clock.format(model.lateBedtimeThreshold) }
    /// "in bed at 2:00am or later (90 minutes past your usual 12:30am)"
    private var lateDefinition: String {
        if let usual = model.usualBedtime {
            return "in bed at \(thresholdText) or later, \(LateNights.marginMinutes) minutes past your usual \(Clock.format(usual))"
        }
        return "in bed at \(thresholdText) or later (until we know your usual bedtime from \(LateNights.minimumNights) nights)"
    }
    private var needed: Int { HabitEffect.minimumNights }

    var body: some View {
        let effect = model.lateNightEffect
        Screen(title: "Late nights", accent: .purple) {
            SampleDataBanner()
            heroCard(effect)
            if effect.enoughData {
                costTiles(effect)
                splitCard
            } else {
                notEnoughCard(effect)
            }
            chartCard
            if !model.lateNights.isEmpty { recentCard }
            tonightCard
        }
    }

    // MARK: Hero

    private func heroCard(_ effect: HabitEffect) -> some View {
        let total = model.nights.count
        let late = effect.withCount
        let sub = late == 0
            ? "No late nights in your last \(total). A late night here means \(lateDefinition)."
            : "\(late) late \(late == 1 ? "night" : "nights") in your last \(total), compared like for like with your \(effect.withoutCount) other nights: alarm mornings with alarm mornings, free mornings with free mornings. Late means \(lateDefinition)."
        return Card(accent: .purple) {
            HStack(spacing: 0) {
                SectionLabel(text: "Late nights", accent: .purple)
                InfoButton(topic: .lateNight).padding(.vertical, -12)
            }
            Text("What a late night costs you").font(.scaled(size: 26, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(sub).font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Text("A late night can cost more than that night's sleep. Your resting heart rate and HRV the next day or two show how hard your body is working to recover.")
                .font(.scaled(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            HowWeGotThisLink(title: "Late-night cost",
                             method: "A late night is a bedtime \(LateNights.marginMinutes) minutes or more past your usual (middle) bedtime over your last 60 nights, or 2am until there are \(LateNights.minimumNights) nights to learn it from. We compare like for like over the same 60 nights: late nights before an alarm morning with your other alarm mornings, and late nights before a free morning with your other free mornings, so weekend sleep-ins don't skew it. We look at how long you slept, and your resting heart rate and HRV the next morning and the morning after, each against your own usual. We need at least \(needed) late nights and \(needed) other nights before showing a comparison.")
        }
    }

    private func notEnoughCard(_ effect: HabitEffect) -> some View {
        Card {
            Label("Not enough data yet", systemImage: "hourglass")
                .font(.scaled(size: 17, weight: .bold))
            Text("To show what late nights do to you, we need at least \(needed) late nights and \(needed) other nights. So far: \(effect.withCount) late, \(effect.withoutCount) other.")
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            Text("The chart below still shows your recent bedtimes, so you can see how close you get to \(thresholdText).")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Cost

    private func costTiles(_ effect: HabitEffect) -> some View {
        let after = model.lateNightDayAfterEffect
        let afterOK = after.enoughData
        return VStack(alignment: .leading, spacing: 10) {
            Text("From \(effect.withCount) late nights and \(effect.withoutCount) other nights.")
                .font(.scaled(size: 13)).secondaryText()
            HStack(alignment: .top, spacing: 10) {
                LateCostTile(eyebrow: "That night", value: signedDuration(effect.asleepDelta), unit: "sleep",
                             lines: [], accent: .purple)
                LateCostTile(eyebrow: "Next day", value: bpm(effect.restingHRDelta), unit: "resting heart rate",
                             lines: [hrvText(effect.hrvDeltaPct)].compactMap { $0 }, accent: .coral)
                LateCostTile(eyebrow: "Day after", value: afterOK ? bpm(after.restingHRDelta) : "\u{2013}",
                             unit: afterOK ? "resting heart rate" : "not enough nights yet (\(after.withCount) of \(needed))",
                             lines: afterOK ? [hrvText(after.hrvDeltaPct)].compactMap { $0 } : [], accent: .orange)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                Text("Resting heart rate up and HRV down mean your body is working harder than usual to recover.")
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                InfoButton(topic: .restingHR)
                InfoButton(topic: .hrv)
            }
            if let c = effect.checkInDelta {
                Text(c < 0
                     ? "You also rate your mornings \(String(format: "%.1f", -c)) points lower (out of 5) after a late night."
                     : "Your morning check-ins aren't lower after late nights, but your body numbers are.")
                    .font(.scaled(size: 13)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var splitCard: some View {
        let split = model.lateNightSleepCost
        return Card {
            Text("Alarm mornings vs free mornings").font(.scaled(size: 17, weight: .bold))
            if let a = split.alarm {
                splitRow("Alarm the next morning", value: signedDuration(a), accent: .coral)
            }
            if let f = split.free {
                splitRow("Free next morning", value: signedDuration(f), accent: .purple)
            }
            Text("Sleep lost on a late night compared with your other nights, split by whether an alarm woke you the next morning. Late nights before an alarm cost more because you can't sleep in afterward.")
                .font(.scaled(size: 13)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func splitRow(_ label: String, value: String, accent: Accent) -> some View {
        HStack {
            Text(label).font(.scaled(size: 15, weight: .semibold))
            Spacer()
            Text(value).font(.scaledNumber(20)).foregroundStyle(accent.ink(scheme))
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    private var chartCard: some View {
        let points = model.recentBedtimes
        let selected = nearest(selectedDay, in: points) ?? points.last { $0.isLate } ?? points.last
        return Card {
            Text("Your recent bedtimes").font(.scaled(size: 17, weight: .bold))
            Text("Each dot is a night. On or above the dashed line (\(thresholdText)) counts as a late night.")
                .font(.scaled(size: 13)).secondaryText()
            if let selected {
                readout(selected)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            }
            BedtimeChart(points: points, threshold: model.lateBedtimeThreshold,
                         selected: selectedDay == nil ? nil : selected?.day, selection: $selectedDay,
                         summary: chartSummary(points))
                .frame(height: 180)
            ScrubHint()
        }
    }

    private func nearest(_ day: Date?, in points: [AppModel.BedtimePoint]) -> AppModel.BedtimePoint? {
        guard let day else { return nil }
        return points.min { abs($0.day.timeIntervalSince(day)) < abs($1.day.timeIntervalSince(day)) }
    }

    private func readout(_ p: AppModel.BedtimePoint) -> some View {
        let night = Calendar.current.date(byAdding: .day, value: -1, to: p.day) ?? p.day
        var next: [String] = []
        if let h = p.hrvDeltaPct { next.append("HRV \(signedPct(h)) vs usual") }
        if let r = p.restingHRDelta { next.append("resting heart rate \(signedBpm(r))") }
        if let c = p.checkIn { next.append("check-in \(Int(c.rounded())) of 5") }
        let nextText = next.isEmpty ? "" : " Next day: " + next.joined(separator: ", ") + "."
        let lead = p.isLate ? "A late night." : "A normal night."
        return ChartReadout(title: "\(night.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) night",
                            value: "Bed \(Clock.format(p.bedtime))",
                            detail: "\(lead) Slept \(Clock.duration(p.asleep)).\(nextText)",
                            accent: p.isLate ? .coral : .purple)
    }

    private func chartSummary(_ points: [AppModel.BedtimePoint]) -> String {
        let late = points.filter(\.isLate).count
        return "Bedtimes for the last \(points.count) nights. \(late) late, at \(thresholdText) or later."
    }

    // MARK: Recent

    private var recentCard: some View {
        let recent = Array(model.lateNights.prefix(5))
        return Card {
            SectionLabel(text: "Recent late nights")
            ForEach(recent, id: \.wakeDay) { n in
                let night = Calendar.current.date(byAdding: .day, value: -1, to: n.wakeDay) ?? n.wakeDay
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(night.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(Clock.format(n.bedtime))")
                            .font(.scaled(size: 15, weight: .bold))
                        Text(n.outcome.hrvDeltaPct.map { "HRV \(signedPct($0)) the next day" } ?? "Slept \(Clock.duration(n.asleepMinutes))")
                            .font(.scaled(size: 13)).secondaryText()
                    }
                    Spacer()
                    Text(n.alarmUsed ? "Alarm next day" : "Free morning")
                        .font(.scaled(size: 12, weight: .bold))
                        .foregroundStyle((n.alarmUsed ? Accent.coral : Accent.purple).ink(scheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((n.alarmUsed ? Accent.coral : Accent.purple).tint(scheme), in: Capsule())
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var tonightCard: some View {
        Card(accent: .indigo) {
            Text("Got a late one coming up?").font(.scaled(size: 17, weight: .bold))
            Text("Keep the next night at your planned \(Clock.format(store.data.bedtime)) bedtime and get morning daylight. That usually helps you bounce back faster than sleeping in.")
                .font(.scaled(size: 14)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            // Moreno F7: 24 hours awake impairs driving about as much as a
            // 0.10% blood alcohol level.
            Label("Up all night or only a few hours' sleep? Don't drive the next day. Being awake 24 hours affects driving about as much as being drunk. Get a ride.",
                  systemImage: "car.fill")
                .font(.scaled(size: 14, weight: .semibold))
                .foregroundStyle(Accent.coral.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: "Why do I feel off?", subtitle: "Your likeliest reasons today", systemImage: "questionmark.circle.fill", accent: .coral) { WhyOffView() }
            LinkRow(title: "Plan your wake time", systemImage: "sunrise.fill", accent: .orange) { WakePlanView() }
        }
    }

    // MARK: Formatting

    private func signedDuration(_ m: Int) -> String {
        if m == 0 { return "0 min" }
        return (m < 0 ? "\u{2212}" : "+") + Clock.duration(m)
    }
    private func bpm(_ v: Double?) -> String { v.map { signedBpm($0) } ?? "–" }
    private func signedBpm(_ v: Double) -> String {
        let r = Int(v.rounded())
        return (r < 0 ? "\u{2212}" : "+") + "\(abs(r)) bpm"
    }
    private func signedPct(_ v: Double) -> String {
        let r = Int(v.rounded())
        return (r < 0 ? "\u{2212}" : "+") + "\(abs(r))%"
    }
    private func hrvText(_ v: Double?) -> String? { v.map { "HRV \(signedPct($0))" } }
}

// MARK: - Subviews

private struct LateCostTile: View {
    var eyebrow: String
    var value: String
    var unit: String
    var lines: [String]
    var accent: Accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: eyebrow, accent: accent)
            Text(value).font(.scaledNumber(19)).minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).font(.scaled(size: 12)).secondaryText()
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { l in
                Text(l).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(accent.ink(scheme))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.tint(scheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct BedtimeChart: View {
    var points: [AppModel.BedtimePoint]
    var threshold: Minutes
    var selected: Date?
    @Binding var selection: Date?
    var summary: String
    @Environment(\.colorScheme) private var scheme

    private var lo: Int { min((points.map(\.bedtime).min() ?? 0) - 30, 0) }
    private var hi: Int { max((points.map(\.bedtime).max() ?? threshold) + 30, threshold + 60) }
    private var ticks: [Int] { Array(stride(from: (lo / 60) * 60, through: hi, by: 60)) }

    var body: some View {
        Chart {
            lateLine
            dots
            selectionMarks
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine().foregroundStyle(Palette(scheme: scheme).track)
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(Clock.format(m)).font(.chartLabel(size: 10)).foregroundStyle(Palette(scheme: scheme).tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartScrub($selection)
        .accessibilityLabel(summary)
    }

    @ChartContentBuilder private var lateLine: some ChartContent {
        RuleMark(y: .value("Late", threshold))
            .foregroundStyle(Accent.coral.fill(scheme).opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                Text("Late: \(Clock.format(threshold))").font(.chartLabel(size: 10, weight: .bold)).foregroundStyle(Accent.coral.ink(scheme))
            }
    }

    @ChartContentBuilder private var dots: some ChartContent {
        ForEach(points) { p in
            PointMark(x: .value("Night", p.day, unit: .day), y: .value("Bedtime", p.bedtime))
                .symbolSize(p.day == selected ? 140 : 45)
                .foregroundStyle(p.isLate ? Accent.coral.fill(scheme) : Accent.purple.fill(scheme).opacity(selected == nil || p.day == selected ? 1 : 0.5))
        }
    }

    @ChartContentBuilder private var selectionMarks: some ChartContent {
        if let selected {
            RuleMark(x: .value("Night", selected, unit: .day))
                .foregroundStyle(Palette(scheme: scheme).primary.opacity(0.5))
        }
    }
}
