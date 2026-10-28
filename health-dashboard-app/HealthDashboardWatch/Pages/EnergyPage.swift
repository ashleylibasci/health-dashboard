import SwiftUI
import Charts
import HealthCore

/// Energy right now, today's curve with "now" marked, and what's coming next.
struct EnergyPage: View {
    @EnvironmentObject private var sync: WatchSync

    private var snapshot: WatchSnapshot { sync.snapshot }

    var body: some View {
        WatchPage(title: "Energy", accent: .mint) {
            TimelineView(.everyMinute) { context in
                let now = context.date
                VStack(alignment: .leading, spacing: 8) {
                    SnapshotStatusLine(snapshot: snapshot, now: now)
                    if snapshot.isFromEarlierDay(now: now) {
                        // Yesterday's curve isn't today's.
                        NotTodayView(what: "energy curve")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            nowRow
                            if snapshot.lastNightMissing == true {
                                Text("No sleep recorded last night, so this runs from your last recorded wake-up.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(WatchStyle.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            EnergySparkline(curve: snapshot.energyCurve, start: snapshot.energyCurveStart,
                                            zones: snapshot.energyZones ?? [], now: now)
                            nextZone
                        }
                        .staleStyle(snapshot.isStale(now: now))
                    }
                }
            }
        }
    }

    /// "22% left" (energy left, the battery), then the zone of the day she's
    /// in ("Second wind zone"), so the percentage never reads as a score for
    /// the zone. Same "left" wording as the Recovery page.
    private var nowRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.energyNow)%")
                    .font(WatchStyle.number(.largeTitle))
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText(value: Double(snapshot.energyNow)))
                Text("left")
                    .font(.headline)
                    .foregroundStyle(WatchStyle.secondaryText)
            }
            if !snapshot.energyZoneTitle.isEmpty {
                Text(zoneLine)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(EnergyPage.color(forZone: snapshot.energyZoneTitle, kind: snapshot.energyZoneKind))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energy left \(snapshot.energyNow) percent" + (snapshot.energyZoneTitle.isEmpty ? "" : ". \(zoneLine)"))
    }

    /// "In your dip zone", "Second wind zone".
    private var zoneLine: String {
        let isDip = snapshot.energyZoneKind.map { $0 == "afternoonDip" } ?? (snapshot.energyZoneTitle == "Afternoon dip")
        return isDip ? "In your dip zone" : "\(snapshot.energyZoneTitle) zone"
    }

    @ViewBuilder
    private var nextZone: some View {
        if !snapshot.nextZoneTitle.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: EnergyPage.symbol(forZone: snapshot.nextZoneTitle, kind: snapshot.nextZoneKind))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Accent.mint.ink(.dark))
                    .accessibilityHidden(true)
                Text(nextZoneText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(Capsule().fill(Accent.mint.fill(.dark).opacity(0.16)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Next: \(nextZoneText)")
        }
    }

    /// "Second wind 5:50pm".
    private var nextZoneText: String {
        if let start = snapshot.nextZoneStart {
            return snapshot.nextZoneTitle + " " + WatchStyle.time(start)
        }
        return snapshot.nextZoneTitle
    }

    /// `kind` is an `EnergyDay.Zone.Kind` raw value from newer phone builds;
    /// older ones only send the title.
    private nonisolated static func kind(_ title: String, _ kind: String?) -> String {
        if let kind { return kind }
        switch title {
        case "Grogginess": return "grogginess"
        case "Afternoon dip": return "afternoonDip"
        case "Wind-down": return "windDown"
        case "Melatonin", "Sleep window": return "melatonin"
        default: return "morningPeak"
        }
    }

    /// Energy is mint; the dips are plain text (coral is only for things
    /// that are worse than usual) and the evening zones take sleep's purple.
    nonisolated static func color(forZone title: String, kind k: String? = nil) -> Color {
        switch kind(title, k) {
        case "grogginess", "afternoonDip": WatchStyle.secondaryText
        case "windDown", "melatonin": Accent.purple.ink(.dark)
        default: Accent.mint.ink(.dark)
        }
    }

    nonisolated static func symbol(forZone title: String, kind k: String? = nil) -> String {
        switch kind(title, k) {
        case "afternoonDip", "grogginess": "chart.line.downtrend.xyaxis"
        case "windDown", "melatonin": "moon.fill"
        default: "chart.line.uptrend.xyaxis"
        }
    }
}

/// The day's predicted energy, one sample every 30 minutes from wake: the
/// hours already behind her dimmed, "now" marked, and the peaks dotted.
private struct EnergySparkline: View {
    let curve: [Double]
    let start: Date?
    let zones: [WatchSnapshot.Zone]
    let now: Date
    @State private var selected: Int?
    /// The Digital Crown moves the selection once a point is picked by tap.
    @State private var crown: Double = 0
    @FocusState private var crownFocused: Bool
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private struct Sample: Identifiable {
        let id: Int
        let level: Double
    }

    private var samples: [Sample] {
        curve.enumerated().map { Sample(id: $0.offset, level: min(max($0.element, 0), 100)) }
    }

    /// Up to two local maxima (the morning peak and the second wind).
    private var peaks: [Sample] {
        let s = samples
        guard s.count > 2 else { return [] }
        var found: [Sample] = []
        for i in 1..<(s.count - 1) where s[i].level > s[i - 1].level && s[i].level >= s[i + 1].level {
            found.append(s[i])
        }
        let top = found.sorted { $0.level > $1.level }.prefix(2)
        return top.sorted { $0.id < $1.id }
    }

    /// Where "now" falls on the curve, in samples from wake (nil before wake,
    /// after the last sample, or from an older phone build without a start).
    private var nowPosition: (x: Double, level: Double)? {
        guard let start, samples.count > 1 else { return nil }
        let x = now.timeIntervalSince(start) / (30 * 60)
        guard x >= 0, x <= Double(samples.count - 1) else { return nil }
        let i = min(Int(x), samples.count - 2)
        let t = x - Double(i)
        return (x, samples[i].level + (samples[i + 1].level - samples[i].level) * t)
    }

    private var summary: String {
        guard let best = samples.max(by: { $0.level < $1.level }) else { return "No energy curve yet" }
        let hours = Double(best.id) / 2
        let hoursText = hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
        return "Energy curve for today. Highest, \(Int(best.level.rounded())) out of 100, about \(hoursText) hours after waking."
    }

    var body: some View {
        if samples.count < 2 {
            Text("Your curve appears after the first night of sleep.")
                .font(.footnote)
                .foregroundStyle(WatchStyle.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                chart
                    .frame(height: 84)
                    // The readout sits over the chart's empty top, so picking
                    // a point never moves anything else on the page.
                    .overlay(alignment: readoutAlignment) { readout }
                    // Focusable only while a point is selected, so the crown
                    // otherwise keeps scrolling the page.
                    .focusable(selected != nil)
                    .focused($crownFocused)
                    .focusEffectDisabled()
                    .digitalCrownRotation($crown, from: 0, through: Double(max(samples.count - 1, 1)), by: 1,
                                          sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .onChange(of: crown) { _, value in
                        guard selected != nil else { return }
                        selected = min(max(Int(value.rounded()), 0), samples.count - 1)
                    }
                    .task(id: selected) {
                        // Clear the selection after a while without changes.
                        guard selected != nil else { return }
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        if !Task.isCancelled { clearSelection() }
                    }
                    .onDisappear { clearSelection() }
                    .animation(.snappy(duration: 0.2), value: selected)
                HStack {
                    Text("Wake")
                    Spacer()
                    Text("Night")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchStyle.tertiaryText)
                .accessibilityHidden(true)
            }
        }
    }

    private func select(_ index: Int) {
        selected = index
        crown = Double(index)
        // The chart only becomes focusable once `selected` is set, so focus
        // it on the next turn; otherwise the crown needs a second tap.
        DispatchQueue.main.async { crownFocused = true }
    }

    private func clearSelection() {
        selected = nil
        crownFocused = false
    }

    private func time(of index: Int) -> Date? {
        start.map { $0.addingTimeInterval(Double(index) * 30 * 60) }
    }

    /// Over the left of the chart when the picked point is on the right, and
    /// the other way round, so it never covers the point.
    private var readoutAlignment: Alignment {
        guard let i = selected else { return .topLeading }
        return Double(i) > Double(samples.count - 1) / 2 ? .topLeading : .topTrailing
    }

    /// What's under your finger: time, energy, and the zone it falls in.
    @ViewBuilder
    private var readout: some View {
        if let i = selected, samples.indices.contains(i) {
            let date = time(of: i)
            let zone = date.flatMap { d in zones.first { $0.start <= d && d < $0.end } }
            VStack(alignment: .leading, spacing: 0) {
                Text([date.map { WatchStyle.time($0) }, "\(Int(samples[i].level.rounded()))%"].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(WatchStyle.number(.footnote))
                    .contentTransition(.numericText())
                if let zone {
                    Text(zone.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(EnergyPage.color(forZone: zone.title, kind: zone.kind))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.75)))
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    private struct LinePoint: Identifiable {
        let id: String
        let x: Double
        let level: Double
        let isPast: Bool
    }

    /// The curve as two runs in time order, both through the exact "now"
    /// point: up to now (past), then from now on. All "ahead" without a now.
    private func linePoints(now n: (x: Double, level: Double)?) -> [LinePoint] {
        guard let n else {
            return samples.map { LinePoint(id: "a\($0.id)", x: Double($0.id), level: $0.level, isPast: false) }
        }
        let before = samples.filter { Double($0.id) < n.x }
            .map { LinePoint(id: "p\($0.id)", x: Double($0.id), level: $0.level, isPast: true) }
        let after = samples.filter { Double($0.id) > n.x }
            .map { LinePoint(id: "a\($0.id)", x: Double($0.id), level: $0.level, isPast: false) }
        return before + [LinePoint(id: "pNow", x: n.x, level: n.level, isPast: true),
                         LinePoint(id: "aNow", x: n.x, level: n.level, isPast: false)] + after
    }

    private var chart: some View {
        let nowPoint = nowPosition
        let past = Accent.mint.fill(.dark).opacity(0.4)
        let future = Accent.mint.fill(.dark).opacity(luminanceReduced ? 0.6 : 1)
        return Chart {
            // Two series that meet at "now": the hours behind her dimmed.
            ForEach(linePoints(now: nowPoint)) { p in
                LineMark(x: .value("Time", p.x), y: .value("Energy", p.level), series: .value("Part", p.isPast ? "past" : "ahead"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .foregroundStyle(p.isPast ? past : future)
            }
            ForEach(peaks) { peak in
                PointMark(x: .value("Time", Double(peak.id)), y: .value("Energy", peak.level))
                    .symbolSize(30)
                    .foregroundStyle(nowPoint.map { Double(peak.id) < $0.x } == true ? past : future)
            }
            if let n = nowPoint {
                RuleMark(x: .value("Time", n.x), yStart: .value("Energy", 0), yEnd: .value("Energy", n.level))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("Time", n.x), y: .value("Energy", n.level))
                    .symbolSize(60)
                    .foregroundStyle(Color.white)
                    .annotation(position: .bottom, spacing: 2) {
                        if selected == nil {
                            Text("now")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.white)
                        }
                    }
            }
            if let i = selected, samples.indices.contains(i) {
                RuleMark(x: .value("Time", Double(i)))
                    .foregroundStyle(Color.white.opacity(0.4))
                PointMark(x: .value("Time", Double(i)), y: .value("Energy", samples[i].level))
                    .symbolSize(70)
                    .foregroundStyle(Accent.mint.ink(.dark))
            }
        }
        // Tap to pick a time (a tap never blocks swiping between pages), then
        // turn the crown to move along the curve. Tap the picked point again
        // to clear it; tap elsewhere to move there.
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geo[anchor]
                        let x = min(max(tap.location.x - frame.minX, 0), frame.width)
                        guard let value: Double = proxy.value(atX: x, as: Double.self) else { return }
                        let index = min(max(Int(value.rounded()), 0), samples.count - 1)
                        if let current = selected, current == index {
                            clearSelection()
                        } else {
                            select(index)
                        }
                    })
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // Headroom above 100 for the readout.
        .chartYScale(domain: 0...128)
        .chartXScale(domain: 0...Double(max(samples.count - 1, 1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityHint("Tap the curve, then turn the Digital Crown to move along it.")
    }
}
