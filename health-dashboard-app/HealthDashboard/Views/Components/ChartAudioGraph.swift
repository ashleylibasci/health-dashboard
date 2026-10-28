import SwiftUI
import Accessibility
import HealthCore

/// What VoiceOver's audio graph (Chart Details) reads for a chart over the
/// day. Swift Charts' own description reads the raw values: minutes since
/// midnight ("1,230") and millilitres. This one reads clock times ("8:30pm")
/// and the unit shown on screen (oz, mg).
struct ClockChartDescriptor: AXChartDescriptorRepresentable {
    var title: String
    var seriesName: String
    var yTitle: String
    /// x is minutes relative to the wake day (as `Clock.format` takes them).
    var points: [(x: Int, y: Double)]
    var yLabel: (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let xs = points.map { Double($0.x) }
        let ys = points.map(\.y)
        let xLow = xs.min() ?? 0
        let yLow = min(ys.min() ?? 0, 0)
        let xAxis = AXNumericDataAxisDescriptor(title: "Time",
                                                range: xLow...max(xs.max() ?? 1, xLow + 1),
                                                gridlinePositions: []) { Clock.format(Int($0.rounded())) }
        let label = yLabel
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle,
                                                range: yLow...max(ys.max() ?? 1, yLow + 1),
                                                gridlinePositions: []) { label($0) }
        let series = AXDataSeriesDescriptor(name: seriesName, isContinuous: true,
                                            dataPoints: points.map { AXDataPoint(x: Double($0.x), y: $0.y) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}
