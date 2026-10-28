import SwiftUI
import Charts
import HealthCore

/// Energy right now, today's curve as a sparkline, and what's coming next.
struct EnergyPage: View {
    @EnvironmentObject private var sync: WatchSync

    private var snapshot: WatchSnapshot { sync.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "Energy", accent: .mint)
                if snapshot == .empty {
                    NotSyncedView()
                } else {
                    SnapshotStatusLine(snapshot: snapshot)
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 8) {
                            nowRow
                            if snapshot.lastNightMissing == true {
                                Text("No sleep recorded last night, so this runs from your last recorded wake-up.")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WatchStyle.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            EnergySparkline(curve: snapshot.energyCurve, start: snapshot.energyCurveStart, zones: snapshot.energyZones ?? [])
                            nextZone
                        }
                        .staleStyle(snapshot.isStale(now: context.date))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// "22% left" (energy left, the battery), then the zone of the day she's
    /// in ("Second wind zone"), so the percentage never reads as a score for
    /// the zone. Same "left" wording as the Recovery page.
    private var nowRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.energyNow)%")
                    .font(.number(34))
                    .minimumScaleFactor(0.7)
                Text("left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WatchStyle.secondaryText)
            }
            if !snapshot.energyZoneTitle.isEmpty {
                Text(zoneLine)
                    .font(.system(size: 14, weight: .bold))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Accent.mint.ink(.dark))
                    .accessibilityHidden(true)
                Text(nextZoneText)
                    .font(.system(size: 14, weight: .semibold))
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
        case "Melatonin": return "melatonin"
        default: return "morningPeak"
        }
    }

    nonisolated static func color(forZone title: String, kind k: String? = nil) -> Color {
        switch kind(title, k) {
        case "grogginess", "afternoonDip": Accent.coral.ink(.dark)
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

/// The day's predicted energy, one sample every 30 minutes from wake, with the
/// peaks marked.
private struct EnergySparkline: View {
    let curve: [Double]
    let start: Date?
    let zones: [WatchSnapshot.Zone]
    @State private var selected: Int?
    /// The Digital Crown moves the selection once a point is picked by tap.
    @State private var crown: Double = 0
    @FocusState private var crownFocused: Bool

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

    private var summary: String {
        guard let best = samples.max(by: { $0.level < $1.level }) else { return "No energy curve yet" }
        let hours = Double(best.id) / 2
        let hoursText = hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours)
        return "Energy curve for today. Highest, \(Int(best.level.rounded())) out of 100, about \(hoursText) hours after waking."
    }

    var body: some View {
        if samples.count < 2 {
            Text("Your curve appears after the first night of sleep.")
                .font(.system(size: 13))
                .foregroundStyle(WatchStyle.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                readout
                chart
                    .frame(height: 70)
                    // Focusable only while a point is selected, so the crown
                    // otherwise keeps scrolling the page.
                    .focusable(selected != nil)
                    .focused($crownFocused)
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
                HStack {
                    Text("Wake")
                    Spacer()
                    Text("Night")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
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

    /// What's under your finger: time, energy, and the zone it falls in.
    @ViewBuilder
    private var readout: some View {
        if let i = selected, samples.indices.contains(i) {
            let date = time(of: i)
            let zone = date.flatMap { d in zones.first { $0.start <= d && d < $0.end } }
            VStack(alignment: .leading, spacing: 0) {
                Text([date.map { WatchStyle.time($0) }, "\(Int(samples[i].level.rounded()))%"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .bold))
                Text(zone?.title ?? " ")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EnergyPage.color(forZone: zone?.title ?? "", kind: zone?.kind))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text("Tap the curve, then turn the crown")
                .font(.system(size: 12))
                .foregroundStyle(WatchStyle.secondaryText)
                .frame(height: 32, alignment: .bottomLeading)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(samples) { sample in
                LineMark(x: .value("Time", sample.id), y: .value("Energy", sample.level))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .foregroundStyle(Accent.mint.fill(.dark))
            }
            ForEach(peaks) { peak in
                PointMark(x: .value("Time", peak.id), y: .value("Energy", peak.level))
                    .symbolSize(30)
                    .foregroundStyle(Accent.mint.fill(.dark))
            }
            if let i = selected, samples.indices.contains(i) {
                RuleMark(x: .value("Time", i))
                    .foregroundStyle(Color.white.opacity(0.4))
                PointMark(x: .value("Time", i), y: .value("Energy", samples[i].level))
                    .symbolSize(70)
                    .foregroundStyle(Color.white)
            }
        }
        // Tap to pick a time (a tap never blocks swiping between pages), then
        // turn the crown to move along the curve. Tap the same spot to clear.
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geo[anchor]
                        let x = min(max(tap.location.x - frame.minX, 0), frame.width)
                        guard let i: Int = proxy.value(atX: x, as: Int.self) else { return }
                        let index = min(max(i, 0), samples.count - 1)
                        if let current = selected, abs(current - index) <= 1 {
                            clearSelection()
                        } else {
                            select(index)
                        }
                    })
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .chartXScale(domain: 0...max(samples.count - 1, 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }
}
