import SwiftUI
import UIKit

/// Fonts that follow the iPhone's text size (Settings › Display & Brightness ›
/// Text Size, and Accessibility › Larger Text).
///
/// The designs use exact point sizes, so every screen asks for
/// `.scaled(size:)` with the design size, and this scales it like body text.
/// Very large accessibility sizes are capped at 2.2× so layouts stay usable.
/// Changing the text size takes the app through inactive → active, and the
/// refresh that follows re-renders the screens with the new sizes. No forced
/// rebuild, so open screens and onboarding progress survive.
extension Font {
    static func scaled(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: scaledSize(size), weight: weight, design: design)
    }

    /// The rounded bold numerals used for big numbers, scaled.
    static func scaledNumber(_ size: CGFloat) -> Font {
        .system(size: scaledSize(size), weight: .bold, design: .rounded)
    }

    static func scaledSize(_ size: CGFloat) -> CGFloat {
        min(UIFontMetrics(forTextStyle: .body).scaledValue(for: size), size * 2.2)
    }
}

