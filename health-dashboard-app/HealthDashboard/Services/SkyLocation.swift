import CoreLocation
import HealthCore

/// Where the Sky theme works out the sun: her rough location (reduced
/// accuracy, when in use, asked once when she picks Sky), rounded to 0.1°
/// (about 10 km) and kept on the phone. Without it, her time zone's
/// approximate place (`Sun.approximatePlace`). Nothing is sent anywhere.
@MainActor
final class SkyLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SkyLocation()

    /// Settings › Appearance › Use my location (on by default).
    @Published var usesLocation: Bool {
        didSet {
            UserDefaults.standard.set(usesLocation, forKey: Keys.uses)
            if usesLocation { refresh(asking: true) }
            onChange?()
        }
    }
    /// The last rough fix, if she allowed it.
    @Published private(set) var fix: (latitude: Double, longitude: Double)?
    @Published private(set) var status: CLAuthorizationStatus

    /// Called when the place the sun is worked out from changes.
    var onChange: (() -> Void)?

    private let manager = CLLocationManager()

    private enum Keys {
        static let uses = "skyUsesLocation"
        static let latitude = "skyLatitude"
        static let longitude = "skyLongitude"
        static let fixedAt = "skyFixedAt"
    }

    private override init() {
        let d = UserDefaults.standard
        usesLocation = d.object(forKey: Keys.uses) == nil || d.bool(forKey: Keys.uses)
        if d.object(forKey: Keys.latitude) != nil {
            fix = (d.double(forKey: Keys.latitude), d.double(forKey: Keys.longitude))
        }
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// The place the sun is worked out from, and whether it's her location.
    var place: (latitude: Double, longitude: Double, isLocation: Bool) {
        if usesLocation, let fix, status == .authorizedWhenInUse || status == .authorizedAlways {
            return (fix.latitude, fix.longitude, true)
        }
        let rough = Sun.approximatePlace(for: .current)
        return (rough.latitude, rough.longitude, false)
    }

    /// Asks for permission only when `asking` (she just picked Sky or
    /// turned the switch on) and iOS hasn't asked before; otherwise a new
    /// rough fix at most once a day.
    func refresh(asking: Bool = false) {
        guard usesLocation, !DemoMode.isOn else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            if asking { manager.requestWhenInUseAuthorization() }
        case .authorizedWhenInUse, .authorizedAlways:
            let fixedAt = UserDefaults.standard.double(forKey: Keys.fixedAt)
            if fix == nil || Date.now.timeIntervalSince1970 - fixedAt > 86_400 { manager.requestLocation() }
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.status = status
            self.refresh()
            self.onChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        // City level only.
        let lat = (c.latitude * 10).rounded() / 10, lon = (c.longitude * 10).rounded() / 10
        Task { @MainActor in
            let d = UserDefaults.standard
            d.set(lat, forKey: Keys.latitude)
            d.set(lon, forKey: Keys.longitude)
            d.set(Date.now.timeIntervalSince1970, forKey: Keys.fixedAt)
            self.fix = (lat, lon)
            self.onChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
