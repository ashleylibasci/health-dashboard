import SwiftUI

/// An app-wide change to the surfaces only: the screen background and the
/// plain card colour. Set once at the app root (evening dim, D-M6; the
/// Sky theme) and read by `Screen`, `Card` and `tileSurface()`. Text, rings
/// and metric colours never change with it. `nil`, the default, is the
/// plain Light or Dark look, drawn exactly as before.
struct SurfaceLook: Equatable {
    /// Top to bottom, behind every screen.
    var background: Gradient
    var card: Color
    var cardBorder: Color
    /// Tinted cards sit on `card` rather than straight on the background,
    /// so a tint over a bright sky keeps its contrast.
    var tintsOnCard = false
    /// The accent glow at the top of each screen.
    var glow = true
}

private struct SurfaceLookKey: EnvironmentKey {
    static let defaultValue: SurfaceLook? = nil
}

extension EnvironmentValues {
    var surfaceLook: SurfaceLook? {
        get { self[SurfaceLookKey.self] }
        set { self[SurfaceLookKey.self] = newValue }
    }
}

/// An sRGB colour that can be blended, for looks that move with the clock.
struct RGB: Equatable {
    var r, g, b: Double
    var a: Double = 1

    init(_ hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    private init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Blended with premultiplied alpha, so a see-through card fades into
    /// an opaque one without a grey step in between.
    func mixed(with other: RGB, by t: Double) -> RGB {
        let a = self.a + (other.a - self.a) * t
        guard a > 0 else { return self }
        func mix(_ x: Double, _ y: Double) -> Double { (x * self.a + (y * other.a - x * self.a) * t) / a }
        return RGB(r: mix(r, other.r), g: mix(g, other.g), b: mix(b, other.b), a: a)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}
