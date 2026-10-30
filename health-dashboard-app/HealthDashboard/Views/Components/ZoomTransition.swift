import SwiftUI

// D-M1: a card on Today grows into the screen it opens and shrinks back
// into the card on Back, so she always sees where she came from. iOS 18's
// zoom transition; on iOS 17, and with Reduce Motion (which iOS turns into
// a cross-fade), the usual push.
//
//     @Namespace private var zoom
//     NavigationLink { RecoveryView().zoomDestination("recovery", in: zoom) }
//         label: { … }.zoomSource("recovery", in: zoom)

extension View {
    /// The card a detail screen grows out of.
    func zoomSource(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(ZoomSource(id: id, namespace: namespace))
    }

    /// A detail screen that grows out of its `zoomSource`.
    func zoomDestination(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(ZoomDestination(id: id, namespace: namespace))
    }
}

private struct ZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct ZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
