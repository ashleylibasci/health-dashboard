import SwiftUI

/// Today's energy curve as a small line with a "now" dot, for widgets and
/// complications: the part she's lived through drawn solid, the rest of
/// the day faint.
struct EnergySpark: View {
    var levels: [Int]
    /// The sample the dot sits on.
    var now: Int
    var line: Color
    var dot: Color
    /// A soft fill under the line (full-colour widgets only).
    var fill = false
    var lineWidth: CGFloat = 2
    var dotSize: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            let i = min(max(now, 0), max(pts.count - 1, 0))
            ZStack {
                if fill, pts.count > 1 {
                    area(pts, bottom: geo.size.height)
                        .fill(LinearGradient(colors: [line.opacity(0.3), line.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                }
                stroke(pts).stroke(line.opacity(0.4), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                stroke(Array(pts.prefix(i + 1))).stroke(line, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if pts.indices.contains(i) {
                    Circle().fill(dot)
                        .frame(width: dotSize, height: dotSize)
                        .position(pts[i])
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The day's own range, at least 40 points tall, so the peak and dip
    /// read at this size without small wiggles looking like big swings.
    private func points(in size: CGSize) -> [CGPoint] {
        guard levels.count > 1, let lo = levels.min(), let hi = levels.max() else { return [] }
        let span = CGFloat(max(hi - lo, 40))
        let bottom = CGFloat(lo + hi) / 2 - span / 2
        let inset = dotSize / 2
        let w = size.width - 2 * inset
        let h = size.height - 2 * inset
        return levels.enumerated().map { i, level in
            CGPoint(x: inset + w * CGFloat(i) / CGFloat(levels.count - 1),
                    y: inset + h * (1 - (CGFloat(level) - bottom) / span))
        }
    }

    private func stroke(_ pts: [CGPoint]) -> Path {
        Path { $0.addLines(pts) }
    }

    private func area(_ pts: [CGPoint], bottom: CGFloat) -> Path {
        Path { p in
            p.addLines(pts)
            p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: bottom))
            p.addLine(to: CGPoint(x: pts[0].x, y: bottom))
            p.closeSubpath()
        }
    }
}
