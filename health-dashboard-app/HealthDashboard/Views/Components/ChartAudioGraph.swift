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

/// What VoiceOver's audio graph (Chart Details) reads for a chart over
/// days or nights: each point by its date ("Tue, Oct 27") with the value in
/// the unit shown on screen, instead of raw seconds since 1970 (Ortiz F2).
struct DateChartDescriptor: AXChartDescriptorRepresentable {
    var title: String
    var seriesName: String
    var yTitle: String
    var points: [(x: Date, y: Double)]
    var yLabel: (Double) -> String
    /// Bars (discrete days) rather than a continuous line.
    var isContinuous = true

    func makeChartDescriptor() -> AXChartDescriptor {
        let xs = points.map { $0.x.timeIntervalSinceReferenceDate }
        let ys = points.map(\.y)
        let xLow = xs.min() ?? 0
        let yLow = min(ys.min() ?? 0, 0)
        let xAxis = AXNumericDataAxisDescriptor(title: "Date",
                                                range: xLow...max(xs.max() ?? 1, xLow + 1),
                                                gridlinePositions: []) {
            Date(timeIntervalSinceReferenceDate: $0).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        let label = yLabel
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle,
                                                range: yLow...max(ys.max() ?? 1, yLow + 1),
                                                gridlinePositions: []) { label($0) }
        let series = AXDataSeriesDescriptor(name: seriesName, isContinuous: isContinuous,
                                            dataPoints: points.map { AXDataPoint(x: $0.x.timeIntervalSinceReferenceDate, y: $0.y) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}

/// The audio graph for a chart over named categories (pack days, weekdays,
/// drink groups): each point read by its label.
struct CategoryChartDescriptor: AXChartDescriptorRepresentable {
    var title: String
    var seriesName: String
    var yTitle: String
    var points: [(label: String, y: Double)]
    var yLabel: (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let ys = points.map(\.y)
        let yLow = min(ys.min() ?? 0, 0)
        let xAxis = AXCategoricalDataAxisDescriptor(title: seriesName, categoryOrder: points.map(\.label))
        let label = yLabel
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle,
                                                range: yLow...max(ys.max() ?? 1, yLow + 1),
                                                gridlinePositions: []) { label($0) }
        let series = AXDataSeriesDescriptor(name: seriesName, isContinuous: false,
                                            dataPoints: points.map { AXDataPoint(x: $0.label, y: $0.y) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}

/// The audio graph for a chart with a plain numeric x (hours asleep, pack
/// day): both axes read through the labels the screen uses.
struct ValueChartDescriptor: AXChartDescriptorRepresentable {
    var title: String
    var seriesName: String
    var xTitle: String
    var yTitle: String
    var points: [(x: Double, y: Double)]
    var xLabel: (Double) -> String
    var yLabel: (Double) -> String
    var isContinuous = false

    func makeChartDescriptor() -> AXChartDescriptor {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let xLow = xs.min() ?? 0
        let yLow = min(ys.min() ?? 0, 0)
        let xl = xLabel, yl = yLabel
        let xAxis = AXNumericDataAxisDescriptor(title: xTitle, range: xLow...max(xs.max() ?? 1, xLow + 1),
                                                gridlinePositions: []) { xl($0) }
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle, range: yLow...max(ys.max() ?? 1, yLow + 1),
                                                gridlinePositions: []) { yl($0) }
        let series = AXDataSeriesDescriptor(name: seriesName, isContinuous: isContinuous,
                                            dataPoints: points.map { AXDataPoint(x: $0.x, y: $0.y) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}
