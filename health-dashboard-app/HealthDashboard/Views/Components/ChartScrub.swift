import SwiftUI
import Charts

extension View {
    /// Makes a chart scrubbable on a scrolling screen: tap a point, or drag
    /// sideways along the chart, and `selection` becomes the x value under
    /// your finger. It stays selected after you lift your finger.
    ///
    /// Use this instead of `chartXSelection`, which inside a ScrollView only
    /// reacts after a long press, so charts felt dead.
    func chartScrub<X: Plottable>(_ selection: Binding<X?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                ScrubSurface { point in
                    guard let anchor = proxy.plotFrame else { return }
                    let frame = geo[anchor]
                    let x = min(max(point.x - frame.minX, 0), max(frame.width - 0.5, 0))
                    if let value: X = proxy.value(atX: x, as: X.self) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }

    /// Donut charts: tap or drag around the ring to pick a slice. `selection`
    /// is the running total at that angle, like `chartAngleSelection`.
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
