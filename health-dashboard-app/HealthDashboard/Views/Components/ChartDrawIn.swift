import SwiftUI
import Charts

// D-M4: a chart's lines and bars trace in from the left the first time it
// appears, so it reads as drawn rather than loaded. Only the plot area is
// revealed (the axes are there from the start), it's a mask that the
// render server animates (no chart redraw per frame), and with Reduce
// Motion the chart is simply there.

extension View {
    /// Trace this chart's plot in from the left when it first appears.
    func drawsIn() -> some View { modifier(ChartDrawIn()) }
}

private struct ChartDrawIn: ViewModifier {
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = drawn || reduceMotion
        content
            .chartPlotStyle { plot in
                plot.mask(alignment: .leading) {
                    Rectangle().scaleEffect(x: shown ? 1 : 0.001, anchor: .leading)
                }
            }
            .onAppear {
                guard !drawn else { return }
                withAnimation(.easeOut(duration: 0.8).delay(0.1)) { drawn = true }
            }
    }
}
