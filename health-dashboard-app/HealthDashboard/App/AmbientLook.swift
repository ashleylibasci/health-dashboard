import SwiftUI
import HealthCore

/// The surfaces that follow the clock: the evening dim (D-M6). Worked out
/// every two minutes while the app is open and whenever it comes forward,
/// and published only when the (stepped) look changes, so a screen redraws
/// its background a few times an evening at most. Lives beside the model,
/// never on it.
@MainActor
final class AmbientLook: ObservableObject {
    /// How far into the evening dim, 0…1 in steps of 1/6.
    @Published private(set) var dim: Double = 0

    private let model: AppModel
    private var timer: Timer?

    init(model: AppModel) {
        self.model = model
    }

    /// Evening dim on (the default) or off, from Settings › Appearance.
    static var eveningDimOn: Bool {
        UserDefaults.standard.object(forKey: "eveningDim") == nil || UserDefaults.standard.bool(forKey: "eveningDim")
    }

    /// The minute her wind-down starts (app-day minutes), from her energy curve.
    static func windDownStart(_ model: AppModel) -> Minutes? { model.energyToday.zone(.windDown)?.range.start }

    /// While the app is in front.
    func start() {
        update()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func update() {
        let next = Self.eveningDimOn ? Self.dimAmount(now: model.now, windDown: Self.windDownStart(model)) : 0
        // A slow cross-fade of colour only (fine with Reduce Motion too).
        if next != dim { withAnimation(.easeInOut(duration: 1.5)) { dim = next } }
    }

    /// Fades in over the 30 minutes after wind-down starts and stays until
    /// the app day rolls over at 4am.
    static func dimAmount(now: Minutes, windDown: Minutes?) -> Double {
        if DemoMode.eveningDim { return 1 }
        guard let windDown, now >= windDown else { return 0 }
        return min(Double((now - windDown) / 5) / 6, 1)
    }

    /// The look for the colour scheme on screen.
    func look(for scheme: ColorScheme) -> SurfaceLook? {
        guard dim > 0 else { return nil }
        return EveningDim.look(scheme, amount: dim)
    }
}

/// Evening dim (D-M6): after her wind-down the backgrounds turn slightly
/// warmer and darker. It follows the clock only, never a score. Text keeps
/// its contrast: light mode's warm background still gives the tertiary
/// grey 4.5:1, and dark mode only gets darker.
enum EveningDim {
    static func look(_ scheme: ColorScheme, amount t: Double) -> SurfaceLook {
        if scheme == .dark {
            return SurfaceLook(background: Gradient(colors: [RGB(0x000000).mixed(with: RGB(0x0E0905), by: t).color]),
                               card: RGB(0xFFFFFF, alpha: 0.07).mixed(with: RGB(0xFFEEDD, alpha: 0.065), by: t).color,
                               cardBorder: RGB(0xFFFFFF, alpha: 0.09).mixed(with: RGB(0xFFEEDD, alpha: 0.08), by: t).color)
        }
        return SurfaceLook(background: Gradient(colors: [RGB(0xF6F6FA).mixed(with: RGB(0xF8F3EC), by: t).color]),
                           card: RGB(0xFFFFFF).mixed(with: RGB(0xFFFBF5), by: t).color,
                           cardBorder: RGB(0xE6E6EF).mixed(with: RGB(0xE9E3DA), by: t).color)
    }
}

/// Hands the clock's surface look to every screen, resolved for the
/// colour scheme on screen.
struct AmbientSurface: ViewModifier {
    @ObservedObject var ambient: AmbientLook
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.surfaceLook, ambient.look(for: scheme))
    }
}
