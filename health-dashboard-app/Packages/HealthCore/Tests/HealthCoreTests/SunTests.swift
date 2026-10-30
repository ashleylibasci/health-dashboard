import XCTest
@testable import HealthCore

/// Sunrise and sunset against NOAA's published times (Sky theme).
final class SunTests: XCTestCase {
    private func date(_ text: String, _ zone: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: zone)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    private func assertSun(_ day: String, lat: Double, lon: Double, zone: String, rise: String, set: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        let result = Sun.day(date("\(day) 12:00", zone), latitude: lat, longitude: lon, timeZone: TimeZone(identifier: zone)!)
        guard case .rises(let sunrise, let sunset) = result else {
            return XCTFail("expected a sunrise, got \(result)", file: file, line: line)
        }
        // Within 3 minutes of NOAA.
        XCTAssertEqual(sunrise.timeIntervalSince(date("\(day) \(rise)", zone)), 0, accuracy: 180, file: file, line: line)
        XCTAssertEqual(sunset.timeIntervalSince(date("\(day) \(set)", zone)), 0, accuracy: 180, file: file, line: line)
    }

    func testNewYorkMidsummer() {
        assertSun("2024-06-21", lat: 40.7128, lon: -74.0060, zone: "America/New_York", rise: "05:25", set: "20:31")
    }

    func testLondonMidwinter() {
        assertSun("2024-12-21", lat: 51.5074, lon: -0.1278, zone: "Europe/London", rise: "08:04", set: "15:53")
    }

    func testSydneyNewYear() {
        // Far from UTC: sunrise falls on the previous UTC day.
        assertSun("2025-01-01", lat: -33.8688, lon: 151.2093, zone: "Australia/Sydney", rise: "05:48", set: "20:09")
    }

    func testPolarDays() {
        let zone = TimeZone(identifier: "Europe/Oslo")!
        XCTAssertEqual(Sun.day(date("2024-12-21 12:00", "Europe/Oslo"), latitude: 69.65, longitude: 18.96, timeZone: zone), .alwaysDown)
        XCTAssertEqual(Sun.day(date("2024-06-21 12:00", "Europe/Oslo"), latitude: 69.65, longitude: 18.96, timeZone: zone), .alwaysUp)
    }

    func testApproximatePlaceFromTimeZone() {
        let ny = Sun.approximatePlace(for: TimeZone(identifier: "America/New_York")!, at: date("2024-07-01 12:00", "UTC"))
        XCTAssertEqual(ny.longitude, -75)   // standard time, not daylight time
        XCTAssertEqual(ny.latitude, 40)
        XCTAssertEqual(Sun.approximatePlace(for: TimeZone(identifier: "Australia/Sydney")!).latitude, -35)
        // Close enough for the sky: within about 45 min of New York's real sunrise.
        let real = Sun.day(date("2024-06-21 12:00", "America/New_York"), latitude: 40.71, longitude: -74.01,
                           timeZone: TimeZone(identifier: "America/New_York")!)
        let rough = Sun.day(date("2024-06-21 12:00", "America/New_York"), latitude: ny.latitude, longitude: ny.longitude,
                            timeZone: TimeZone(identifier: "America/New_York")!)
        guard case .rises(let a, _) = real, case .rises(let b, _) = rough else { return XCTFail() }
        XCTAssertEqual(a.timeIntervalSince(b), 0, accuracy: 45 * 60)
    }

    func testSkyThroughTheDay() {
        let rise = date("2026-10-29 07:30", "America/New_York")
        let set = date("2026-10-29 18:15", "America/New_York")
        func at(_ t: String) -> SkyBlend { Sun.sky(at: date("2026-10-29 \(t)", "America/New_York"), sunrise: rise, sunset: set) }

        XCTAssertEqual(at("03:00"), .steady(.night))
        XCTAssertEqual(at("07:00"), SkyBlend(from: .night, to: .sunrise, amount: 0.5))
        XCTAssertEqual(at("07:41"), .steady(.sunrise))
        XCTAssertEqual(at("08:45"), SkyBlend(from: .sunrise, to: .day, amount: 0.5))
        XCTAssertEqual(at("13:15"), .steady(.day))
        XCTAssertEqual(at("17:30"), SkyBlend(from: .day, to: .sunset, amount: 0.5))
        XCTAssertEqual(at("18:20"), .steady(.sunset))
        XCTAssertEqual(at("19:05"), SkyBlend(from: .sunset, to: .night, amount: 0.5))
        XCTAssertEqual(at("23:05"), .steady(.night))
    }

    func testSkyBlendsNeverJump() {
        // Minute by minute, no phase change skips its blend.
        let rise = date("2026-10-29 07:30", "America/New_York")
        let set = date("2026-10-29 18:15", "America/New_York")
        let order = SkyPhase.allCases
        var last = Sun.sky(at: rise.addingTimeInterval(-6 * 3600), sunrise: rise, sunset: set)
        for minute in stride(from: -360, through: 1080, by: 1) {
            let now = Sun.sky(at: rise.addingTimeInterval(Double(minute) * 60), sunrise: rise, sunset: set)
            // Position on the day's loop: night 0, sunrise 1, day 2, sunset 3 (and back to 0).
            func position(_ b: SkyBlend) -> Double { Double(order.firstIndex(of: b.from)!) + (b.from == b.to ? 0 : b.amount) }
            let step = abs(position(now) - position(last)).truncatingRemainder(dividingBy: 4)
            XCTAssertLessThanOrEqual(min(step, 4 - step), 0.05, "jump at minute \(minute)")
            last = now
        }
    }

    func testShortWinterDaySqueezesTheBlends() {
        let rise = date("2026-12-21 10:30", "UTC")
        let set = date("2026-12-21 12:00", "UTC")   // 90 min of daylight
        let noonish = Sun.sky(at: date("2026-12-21 11:15", "UTC"), sunrise: rise, sunset: set)
        XCTAssertNotEqual(noonish, .steady(.night))
        XCTAssertEqual(Sun.sky(at: date("2026-12-21 12:05", "UTC"), sunrise: rise, sunset: set), .steady(.sunset))
    }

    func testQuantizedBlend() {
        let b = SkyBlend(from: .day, to: .sunset, amount: 0.37)
        XCTAssertEqual(b.quantized(steps: 12).amount, 4.0 / 12, accuracy: 1e-9)
        XCTAssertEqual(SkyBlend(from: .day, to: .sunset, amount: 0.98).quantized(steps: 12), .steady(.sunset))
        XCTAssertEqual(b.nearest, .day)
    }
}
