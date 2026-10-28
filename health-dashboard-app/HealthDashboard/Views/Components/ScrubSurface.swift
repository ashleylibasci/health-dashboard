import SwiftUI

/// The touch layer every chart uses. Charts sit on scrolling screens, where
/// a plain SwiftUI drag either blocks scrolling or loses to it, so this uses
/// UIKit directly:
/// - a tap picks the point under your finger (`onTap`, or `onChange` when
///   there's no `onTap`),
/// - dragging sideways moves along the chart,
/// - dragging up or down still scrolls the page.
/// The point is in the surface's own coordinates.
///
/// It plays no haptics itself: the chart plays a selection tick each time
/// the snapped value changes (`chartScrub(_:snapped:steps:)` or
/// `.scrubFeedback(_:)`), so the ticks match the points you pass.
struct ScrubSurface: UIViewRepresentable {
    var onChange: (CGPoint) -> Void
    var onEnd: () -> Void = {}
    /// A tap. Defaults to `onChange`.
    var onTap: ((CGPoint) -> Void)? = nil
    /// A sideways drag starting.
    var onBegin: () -> Void = {}

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ScrubSurface

        init(parent: ScrubSurface) { self.parent = parent }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            if let onTap = parent.onTap { onTap(point) } else { parent.onChange(point) }
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.onBegin()
                parent.onChange(gesture.location(in: gesture.view))
            case .changed:
                parent.onChange(gesture.location(in: gesture.view))
            case .ended, .cancelled, .failed:
                parent.onEnd()
            default:
                break
            }
        }

        /// Only claim mostly-sideways drags, so the page keeps scrolling.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }
    }
}
