import SwiftUI

// D-M3: logging that feels good. A bottle's water sloshes as it fills, a
// drink's cup fills up when it's logged, and reaching the water goal gets a
// small sparkle. Each plays once per log (keyframes, no state on the
// model), and with Reduce Motion the slosh and the cup's fill are off and
// the sparkle only fades.

/// Water in a bottle: the level, with its surface tipped by `tilt`
/// (−1…1) as it sloshes.
struct LiquidSurface: Shape {
    var level: CGFloat
    var tilt: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(level, tilt) }
        set { level = newValue.first; tilt = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let level = min(max(level, 0), 1)
        guard level > 0 else { return Path() }
        let top = rect.maxY - rect.height * level
        // A small wave: higher on one side, lower on the other.
        let amp = min(rect.height * 0.1, 4) * tilt
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: top - amp))
        p.addCurve(to: CGPoint(x: rect.maxX, y: top + amp),
                   control1: CGPoint(x: rect.minX + rect.width / 3, y: top - amp * 1.8),
                   control2: CGPoint(x: rect.minX + rect.width * 2 / 3, y: top + amp * 1.8))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The bottle's water: rises with the `fill` motion and sloshes for about
/// a second whenever `level` changes.
struct SloshingWater: View {
    var level: Double
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        KeyframeAnimator(initialValue: CGFloat(0), trigger: level) { tilt in
            LiquidSurface(level: level, tilt: reduceMotion ? 0 : tilt)
                .fill(color)
                .motion(.fill, value: level)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.18)
                CubicKeyframe(-0.7, duration: 0.24)
                CubicKeyframe(0.4, duration: 0.24)
                CubicKeyframe(-0.15, duration: 0.22)
                CubicKeyframe(0, duration: 0.22)
            }
        }
    }
}

/// A drink's symbol that fills from the bottom each time `trigger`
/// changes, like a cup being poured.
struct FillingSymbol: View {
    var systemName: String
    var color: Color
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        KeyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { level in
            let level = reduceMotion ? 1 : level
            ZStack {
                Image(systemName: systemName).foregroundStyle(color.opacity(0.35))
                Image(systemName: systemName).foregroundStyle(color)
                    .mask {
                        GeometryReader { geo in
                            Rectangle()
                                .frame(height: geo.size.height * level)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.1, duration: 0.01)
                CubicKeyframe(1, duration: 0.7)
            }
        }
    }
}

/// A small sparkle that pops up and fades when `trigger` changes (a goal
/// reached). Decorative: the toast already says it.
struct GoalSparkle: View {
    var trigger: Int
    var accent: Accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Pop {
        var opacity: Double = 0
        var scale: CGFloat = 0.4
        var angle: Double = -25
    }

    var body: some View {
        let still = reduceMotion
        Image(systemName: "sparkles")
            .font(.scaled(size: 18, weight: .semibold))
            .foregroundStyle(accent.ink(scheme))
            .keyframeAnimator(initialValue: Pop(), trigger: trigger) { content, pop in
                content
                    .opacity(pop.opacity)
                    .scaleEffect(still ? 1 : pop.scale)
                    .rotationEffect(.degrees(still ? 0 : pop.angle))
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.15)
                    LinearKeyframe(1, duration: 0.75)
                    LinearKeyframe(0, duration: 0.4)
                }
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.2, duration: 0.3)
                    SpringKeyframe(1, duration: 0.3)
                    LinearKeyframe(1, duration: 0.7)
                }
                KeyframeTrack(\.angle) {
                    CubicKeyframe(8, duration: 0.3)
                    CubicKeyframe(0, duration: 0.3)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
