import SwiftUI
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

/// The app's named motions, so the same kind of change always moves the
/// same way. Each one falls back to a short fade when Reduce Motion is on
/// (Settings › Accessibility › Motion): no springs, scaling or sliding.
///
/// | Motion | Used for | Animation |
/// |---|---|---|
/// | press | a button or tile under your finger | spring 0.25 s, damping 0.7 (scale 0.96) |
/// | log | a drink, water or check-in being saved | spring 0.45 s, damping 0.8 |
/// | fill | rings, bottles and bars filling up | spring 0.6 s, damping 0.85 |
/// | select | a chip, segment or chart point picked | snappy 0.2 s |
/// | reveal | a row or section appearing or hiding | snappy 0.3 s |
/// | dataSwap | a chart's range or data changing | smooth 0.45 s |
/// | page | moving between onboarding steps or pages | spring 0.42 s, damping 0.88 |
/// | commit | finishing a flow, switching sample → real data | smooth 0.5 s |
/// | undo | a toast arriving or an undo putting things back | spring 0.35 s, damping 0.85 |
///
/// Use `.motion(.fill, value: x)` in place of `.animation(_:value:)`,
/// `withMotion(.log) { … }` in place of `withAnimation`, `.motionTransition(.reveal)`
/// for views that come and go, and `PressableStyle` for tappable cards.
enum Motion: CaseIterable {
    case press, log, fill, select, reveal, dataSwap, page, commit, undo

    /// The full animation.
    var animation: Animation {
        switch self {
        case .press: .spring(response: 0.25, dampingFraction: 0.7)
        case .log: .spring(response: 0.45, dampingFraction: 0.8)
        case .fill: .spring(response: 0.6, dampingFraction: 0.85)
        case .select: .snappy(duration: 0.2)
        case .reveal: .snappy(duration: 0.3)
        case .dataSwap: .smooth(duration: 0.45)
        case .page: .spring(response: 0.42, dampingFraction: 0.88)
        case .commit: .smooth(duration: 0.5)
        case .undo: .spring(response: 0.35, dampingFraction: 0.85)
        }
    }

    /// What plays instead when Reduce Motion is on: a short ease, which
    /// reads as a cross-fade for colour and opacity changes and as a quick
    /// settle for anything that has to change size.
    var reducedAnimation: Animation? {
        switch self {
        case .press: nil
        case .select, .dataSwap: .easeOut(duration: 0.15)
        default: .easeInOut(duration: 0.2)
        }
    }

    func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? reducedAnimation : animation
    }

    /// How a view arrives and leaves with this motion. Slides only when
    /// Reduce Motion is off; otherwise it fades.
    func transition(edge: Edge = .bottom, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        switch self {
        case .press, .select, .fill, .dataSwap: return .opacity
        case .commit: return .opacity.combined(with: .scale(scale: 0.98))
        default: return .move(edge: edge).combined(with: .opacity)
        }
    }

    /// Reduce Motion, read outside a view (for `withMotion`).
    static var isReduced: Bool {
        #if os(watchOS)
        WKAccessibilityIsReduceMotionEnabled()
        #else
        UIAccessibility.isReduceMotionEnabled
        #endif
    }
}

/// `withAnimation` with a named motion that respects Reduce Motion.
@discardableResult
func withMotion<Result>(_ motion: Motion, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(motion.animation(reduceMotion: Motion.isReduced), body)
}

extension View {
    /// `.animation(_:value:)` with a named motion that respects Reduce Motion.
    func motion<V: Equatable>(_ motion: Motion, value: V) -> some View {
        modifier(MotionModifier(motion: motion, value: value))
    }

    /// `.transition(_:)` with a named motion: slides in from `edge`, or
    /// fades when Reduce Motion is on.
    func motionTransition(_ motion: Motion, edge: Edge = .bottom) -> some View {
        modifier(MotionTransitionModifier(motion: motion, edge: edge))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    var motion: Motion
    var value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
    }
}

private struct MotionTransitionModifier: ViewModifier {
    var motion: Motion
    var edge: Edge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(motion.transition(edge: edge, reduceMotion: reduceMotion))
    }
}

/// A button that sinks a little under your finger (scale 0.96 with the
/// `press` spring), for tappable cards, tiles and drink buttons. With
/// Reduce Motion it dims instead of scaling.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, scale: scale)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
                .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
                .animation(Motion.press.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// `.buttonStyle(.pressable)`
    static var pressable: PressableStyle { PressableStyle() }
}
