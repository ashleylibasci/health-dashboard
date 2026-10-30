import SwiftUI
import HealthCore

/// The surfaces that follow the clock: the evening dim (D-M6) and the Sky
/// theme (sunrise and sunset where she is). Worked out
/// every two minutes while the app is open and whenever it comes forward,
/// and published only when the (stepped) look changes, so a screen redraws
/// its background a few times an evening at most. Lives beside the model,
/// never on it.
@MainActor
final class AmbientLook: ObservableObject {
    /// How far into the evening dim, 0…1 in steps of 1/6.
    @Published private(set) var dim: Double = 0
    /// Where the sky is, with Sky picked in Settings › Appearance (in
    /// steps of 5 minutes of a blend).
    @Published private(set) var sky: SkyBlend?

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
        SkyLocation.shared.onChange = { [weak self] in self?.update() }
        if Self.skyOn { SkyLocation.shared.refresh() }
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
        let sky = Self.skyOn ? Self.skyNow() : nil
        // Sky replaces the evening dim: sunset and night already do it.
        let next = sky == nil && Self.eveningDimOn ? Self.dimAmount(now: model.now, windDown: Self.windDownStart(model)) : 0
        // A slow cross-fade of colour only (fine with Reduce Motion too).
        guard next != dim || sky != self.sky else { return }
        withAnimation(.easeInOut(duration: 1.5)) {
            dim = next
            self.sky = sky
        }
    }

    /// Sky picked in Settings › Appearance (or `-demoSkyPhase`).
    static var skyOn: Bool { DemoMode.skyPhase != nil || UserDefaults.standard.string(forKey: "appearance") == "sky" }

    private static func skyNow() -> SkyBlend {
        if let phase = DemoMode.skyPhase { return .steady(phase) }
        let place = SkyLocation.shared.place
        return Sun.sky(at: .now, latitude: place.latitude, longitude: place.longitude, timeZone: .current).quantized(steps: 12)
    }

    /// Today's sunrise and sunset where she is, for Settings.
    static func todaysSun() -> Sun.Day {
        let place = SkyLocation.shared.place
        return Sun.day(.now, latitude: place.latitude, longitude: place.longitude, timeZone: .current)
    }

    /// The text style the sky asks for, while Sky is on.
    var skyScheme: ColorScheme? { sky.map { SkyTheme.look($0).scheme } }

    /// Fades in over the 30 minutes after wind-down starts and stays until
    /// the app day rolls over at 4am.
    static func dimAmount(now: Minutes, windDown: Minutes?) -> Double {
        if DemoMode.eveningDim { return 1 }
        guard let windDown, now >= windDown else { return 0 }
        return min(Double((now - windDown) / 5) / 6, 1)
    }

    /// The look for the colour scheme on screen.
    func look(for scheme: ColorScheme) -> SurfaceLook? {
        if let sky { return SkyTheme.look(sky).look }
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
