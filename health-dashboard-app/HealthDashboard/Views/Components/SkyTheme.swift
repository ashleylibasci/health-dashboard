import SwiftUI
import HealthCore

/// The Sky theme's surfaces (Settings › Appearance › Sky): dark at night,
/// peach and lilac at sunrise, light in the day, ember to plum at sunset.
/// Only the background, cards and text style change; rings, metric and
/// accent colours are the usual Light or Dark ones.
///
/// Contrast (WCAG, checked for every stop, card and tinted card, with the
/// app's text greys and all nine accent inks): 4.5:1 or more below the top
/// stop in every phase and all through the blends (orange on its tinted
/// card 4.43:1, as plain Light's 4.45:1). The top stop, behind the status
/// bar and header, holds primary and secondary text to 4.5:1 and the
/// tertiary grey and inks to 3.8:1, as plain Light and Dark's own top glow
/// does. That's why sunset is a deeper ember than the mockup's bright
/// orange, which put white text at 2.3:1.
enum SkyTheme {
    struct Phase {
        /// Top to bottom at `locations`.
        var stops: [RGB]
        var card: RGB
        var cardBorder: RGB
        var scheme: ColorScheme
    }

    static let locations: [CGFloat] = [0, 0.22, 0.45, 0.7, 1]

    static func phase(_ phase: SkyPhase) -> Phase {
        switch phase {
        case .night:
            Phase(stops: [RGB(0x1A1D48), RGB(0x10122C), RGB(0x0A0B18), RGB(0x070710), RGB(0x050508)],
                  card: RGB(0xFFFFFF, alpha: 0.07), cardBorder: RGB(0xFFFFFF, alpha: 0.09), scheme: .dark)
        case .sunrise:
            Phase(stops: [RGB(0xFBDCCD), RGB(0xFFF3EE), RGB(0xFAF4FA), RGB(0xF7F5FA), RGB(0xF5F5FA)],
                  card: RGB(0xFFFFFF, alpha: 0.96), cardBorder: RGB(0xEADFE4), scheme: .light)
        case .day:
            Phase(stops: [RGB(0xDDEBFA), RGB(0xF0F5FC), RGB(0xF2F6FC), RGB(0xF5F7FB), RGB(0xF6F7FB)],
                  card: RGB(0xFFFFFF), cardBorder: RGB(0xE3E7F0), scheme: .light)
        case .sunset:
            Phase(stops: [RGB(0x6E270C), RGB(0x4A1408), RGB(0x3A1236), RGB(0x22103C), RGB(0x110A1C)],
                  card: RGB(0x12061A, alpha: 0.55), cardBorder: RGB(0xFFFFFF, alpha: 0.12), scheme: .dark)
        }
    }

    /// The look and text style for a point in the day. Text can't fade
    /// between dark and light, so a blend that changes text style (night →
    /// sunrise, day → sunset) warms its own side first (night toward the
    /// sunset glow, day toward the sunrise peach), switches text style at
    /// the halfway point, and carries on from the other side's warm look:
    /// every frame stays readable.
    static func look(_ blend: SkyBlend) -> (look: SurfaceLook, scheme: ColorScheme) {
        let from = phase(blend.from), to = phase(blend.to)
        if from.scheme == to.scheme { return (surface(from, to, blend.amount), from.scheme) }
        func warm(_ scheme: ColorScheme) -> Phase { phase(scheme == .dark ? .sunset : .sunrise) }
        if blend.amount < 0.5 { return (surface(from, warm(from.scheme), blend.amount * 2), from.scheme) }
        return (surface(warm(to.scheme), to, (blend.amount - 0.5) * 2), to.scheme)
    }

    private static func surface(_ a: Phase, _ b: Phase, _ t: Double) -> SurfaceLook {
        let stops = zip(zip(a.stops, b.stops), locations).map { pair, location in
            Gradient.Stop(color: pair.0.mixed(with: pair.1, by: t).color, location: location)
        }
        return SurfaceLook(background: Gradient(stops: stops),
                           card: a.card.mixed(with: b.card, by: t).color,
                           cardBorder: a.cardBorder.mixed(with: b.cardBorder, by: t).color,
                           tintsOnCard: true, glow: false)
    }
}
