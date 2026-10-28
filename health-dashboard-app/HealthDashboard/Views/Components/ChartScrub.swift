import SwiftUI
import Charts

extension View {
    /// Makes a chart scrubbable on a scrolling screen: tap a point, or drag
    /// sideways along the chart, and `selection` becomes the x value under
    /// your finger. It stays selected after you lift your finger; tapping
    /// the selected point again clears it.
    ///
    /// Use this instead of `chartXSelection`, which inside a ScrollView only
    /// reacts after a long press, so charts felt dead.
    ///
    /// This form ticks once when a touch starts. Pass `snapped:` (below) so
    /// it ticks on every point instead.
    func chartScrub<X: Plottable & Equatable>(_ selection: Binding<X?>) -> some View {
        modifier(ChartScrubModifier(selection: selection, snapped: nil, steps: [], tracksSnapped: false, feedbackKey: nil))
    }

    /// Scrubbing with a selection tick each time the point the screen shows
    /// changes. `snapped` is that point (the data point nearest `selection`,
    /// or nil), and `steps` the chart's x values in order: VoiceOver users
    /// swipe up or down to step through them, and the readout is spoken.
    /// Without `steps`, VoiceOver steps across the chart in twelfths.
    ///
    /// A chart with more than about 30 points across the plot should pass
    /// `feedbackKey`, a coarser bucket for the tick (`{ $0 / 30 }`: one tick
    /// per half hour on a minutes axis). A tick per point there turned into a
    /// buzz (Weber A6). Ticks are never closer than 40 ms either way.
    ///
    /// For a continuous x (minutes), pass a binding that snaps before it
    /// writes (`Binding.snapping`), so a drag between two points doesn't
    /// redraw the screen.
    func chartScrub<X: Plottable & Equatable>(_ selection: Binding<X?>, snapped: X?, steps: [X] = [],
                                              feedbackKey: ((X) -> Int)? = nil) -> some View {
        modifier(ChartScrubModifier(selection: selection, snapped: snapped, steps: steps, tracksSnapped: true,
                                    feedbackKey: feedbackKey))
    }

    /// Plays a selection tick each time a scrubbed chart's snapped value
    /// changes. For custom scrub surfaces (strips, timelines) and charts
    /// whose snapped value isn't the chart's x type.
    func scrubFeedback<V: Equatable>(_ snapped: V) -> some View {
        sensoryFeedback(.selection, trigger: snapped)
    }

    /// Axis labels grow with the text size up to xxLarge, then stop: at the
    /// accessibility sizes they overprinted each other ("9a12p3p6p9pm").
    /// The readout above each chart and its VoiceOver summary carry the
    /// full-size values.
    func chartAxisTextCapped() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// Donut charts: tap or drag around the ring to pick a slice. `selection`
    /// is the running total at that angle, like `chartAngleSelection`. Add
    /// `.scrubFeedback(_:)` with the selected slice for the haptic tick.
    func chartAngleScrub(_ selection: Binding<Int?>, total: Int) -> some View {
        chartOverlay { _ in
            GeometryReader { geo in
                ScrubSurface { point in
                    let dx = point.x - geo.size.width / 2
                    let dy = point.y - geo.size.height / 2
                    // 0 at 12 o'clock, growing clockwise, like SectorMark.
                    var angle = atan2(dx, -dy)
                    if angle < 0 { angle += 2 * .pi }
                    let value = Int((Double(angle) / (2 * .pi) * Double(total)).rounded())
                    selection.wrappedValue = min(max(value, 0), max(total, 0))
                }
            }
        }
    }
}

extension Binding {
    /// A chart selection that stores the snapped point, not the raw finger
    /// position, and writes only when that point changes. On a minutes axis
    /// the raw value changes every third of a point of finger travel, and
    /// each write redrew the screen (Weber A2):
    /// `.chartScrub($selection.snapping { nearest($0) }, snapped: selection)`.
    func snapping<T: Equatable>(_ snap: @escaping (T) -> T?) -> Binding<T?> where Value == T? {
        Binding<T?>(get: { wrappedValue },
                    set: { raw in
                        let snapped = raw.flatMap(snap)
                        if snapped != wrappedValue { wrappedValue = snapped }
                    })
    }
}

/// When VoiceOver last stepped a chart, so the readout above it knows to
/// speak its new value (and stays quiet when the data just refreshes).
@MainActor
enum ChartScrubVoiceOver {
    private(set) static var lastStep = Date.distantPast
    static func noteStep() { lastStep = .now }
    static var justStepped: Bool { Date.now.timeIntervalSince(lastStep) < 1.5 }
}

/// The chart's proxy and plot frame from the last layout, for VoiceOver
/// stepping and tap-to-clear (a plain box: changing it never redraws).
private final class ScrubChartGeometry {
    var proxy: ChartProxy?
    var plot: CGRect = .zero

    func update(_ proxy: ChartProxy, plot: CGRect) {
        self.proxy = proxy
        self.plot = plot
    }
}

/// When the last scrub tick played, so ticks are at least 40 ms apart (a
/// plain box: changing it never redraws).
private final class ScrubTickClock {
    private var last = Date.distantPast

    func allow() -> Bool {
        let now = Date.now
        guard now.timeIntervalSince(last) >= 0.04 else { return false }
        last = now
        return true
    }
}

/// What a scrub tick follows: the snapped point, or its bucket when the
/// chart has a `feedbackKey`.
private struct ScrubTickKey<X: Equatable>: Equatable {
    var value: X?
    var key: Int?

    static func == (a: Self, b: Self) -> Bool {
        if a.key != nil || b.key != nil { return a.key == b.key }
        return a.value == b.value
    }
}

private struct ChartScrubModifier<X: Plottable & Equatable>: ViewModifier {
    @Binding var selection: X?
    var snapped: X?
    var steps: [X]
    var tracksSnapped: Bool
    var feedbackKey: ((X) -> Int)?
    @State private var geometry = ScrubChartGeometry()
    @State private var tickClock = ScrubTickClock()
    @State private var touchTick = 0

    private var tickKey: ScrubTickKey<X> {
        ScrubTickKey(value: snapped, key: feedbackKey.flatMap { key in snapped.map(key) })
    }

    /// How close (in points) a tap must be to the selected point to clear it.
    private let clearDistance: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let _ = geometry.update(proxy, plot: proxy.plotFrame.map { geo[$0] } ?? .zero)
                    ScrubSurface(onChange: { move(to: $0) },
                                 onTap: { tap(at: $0) },
                                 onBegin: { if !tracksSnapped { touchTick += 1 } })
                }
            }
            .sensoryFeedback(.selection, trigger: touchTick)
            .sensoryFeedback(.selection, trigger: tickKey) { _, _ in tickClock.allow() }
            .chartAxisTextCapped()
            // One VoiceOver element per chart: its summary and audio graph (set
            // after this), never Swift Charts' own per-mark elements, which read
            // raw values like "400 to 500" (minutes) or ml (round 3, A9).
            .accessibilityElement(children: .ignore)
            .accessibilityAdjustableAction { step($0) }
    }

    private var shown: X? { tracksSnapped ? (snapped ?? selection) : selection }

    /// The x value under a point, and its x inside the plot.
    private func value(at point: CGPoint) -> (x: CGFloat, value: X)? {
        guard let proxy = geometry.proxy, geometry.plot.width > 0 else { return nil }
        let frame = geometry.plot
        let x = min(max(point.x - frame.minX, 0), max(frame.width - 0.5, 0))
        guard let value: X = proxy.value(atX: x, as: X.self) else { return nil }
        return (x, value)
    }

    /// No write when the value under the finger hasn't changed, so a still
    /// finger doesn't redraw the screen.
    private func move(to point: CGPoint) {
        if let hit = value(at: point), selection != hit.value { selection = hit.value }
    }

    /// A tap on the selected point (or the same bar) clears the selection;
    /// anywhere else selects.
    private func tap(at point: CGPoint) {
        guard let hit = value(at: point) else { return }
        if selection != nil, let current = shown {
            let samePoint = current == hit.value
                || geometry.proxy?.position(forX: current).map { abs($0 - hit.x) <= clearDistance } == true
            if samePoint {
                selection = nil
                if !tracksSnapped { touchTick += 1 }
                return
            }
        }
        selection = hit.value
        if !tracksSnapped { touchTick += 1 }
    }

    /// VoiceOver's swipe up / down.
    private func step(_ direction: AccessibilityAdjustmentDirection) {
        let forward: Bool
        switch direction {
        case .increment: forward = true
        case .decrement: forward = false
        @unknown default: return
        }
        ChartScrubVoiceOver.noteStep()
        if !steps.isEmpty {
            let index = shown.flatMap { current in steps.firstIndex(of: current) ?? nearestStep(to: current) }
            let next = index.map { forward ? min($0 + 1, steps.count - 1) : max($0 - 1, 0) } ?? (forward ? 0 : steps.count - 1)
            selection = steps[next]
            return
        }
        guard let proxy = geometry.proxy, geometry.plot.width > 0 else { return }
        let width = geometry.plot.width
        let stride = width / 12
        let x: CGFloat
        if let current = shown, let at = proxy.position(forX: current) {
            x = forward ? at + stride : at - stride
        } else {
            x = forward ? 0 : width
        }
        if let value: X = proxy.value(atX: min(max(x, 0), width - 0.5), as: X.self) {
            selection = value
        }
    }

    private func nearestStep(to value: X) -> Int? {
        guard let proxy = geometry.proxy, let at = proxy.position(forX: value) else { return nil }
        return steps.indices.min { a, b in
            abs((proxy.position(forX: steps[a]) ?? .infinity) - at) < abs((proxy.position(forX: steps[b]) ?? .infinity) - at)
        }
    }
}
