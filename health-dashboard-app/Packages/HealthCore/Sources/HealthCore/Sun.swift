import Foundation

/// Sunrise and sunset worked out on the phone (NOAA's solar calculator,
/// the "General Solar Position" equations), for the Sky theme. Within a
/// minute or two of NOAA's own tables between ±65° latitude; nothing is
/// looked up online.
public enum Sun {
    /// One day's sun where she is.
    public enum Day: Equatable {
        case rises(sunrise: Date, sunset: Date)
        /// Midnight sun: up all day.
        case alwaysUp
        /// Polar night: down all day.
        case alwaysDown
    }

    /// Sunrise and sunset on `day`'s calendar date in `timeZone`.
    /// Longitude is east-positive (New York is −74).
    public static func day(_ day: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> Day {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let parts = cal.dateComponents([.year, .month, .day], from: day)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let midnightUTC = utc.date(from: parts) else { return .alwaysDown }

        // Evaluated at the place's solar noon, which is close enough to
        // sunrise and sunset for the slow-moving terms.
        let julianMidnight = midnightUTC.timeIntervalSince1970 / 86400 + 2_440_587.5
        let century = (julianMidnight + (720 - 4 * longitude) / 1440 - 2_451_545) / 36525
        let solar = Solar(century: century)

        let lat = latitude * .pi / 180
        let decl = solar.declination * .pi / 180
        let cosHour = cos(90.833 * .pi / 180) / (cos(lat) * cos(decl)) - tan(lat) * tan(decl)
        if cosHour > 1 { return .alwaysDown }
        if cosHour < -1 { return .alwaysUp }
        let hourAngle = acos(cosHour) * 180 / .pi

        // Minutes after midnight UTC on that date (can fall outside 0…1440).
        let noon = 720 - 4 * longitude - solar.equationOfTime
        let rise = midnightUTC.addingTimeInterval((noon - 4 * hourAngle) * 60)
        let set = midnightUTC.addingTimeInterval((noon + 4 * hourAngle) * 60)
        return .rises(sunrise: rise, sunset: set)
    }

    /// The NOAA terms that change with the date.
    private struct Solar {
        /// Degrees.
        let declination: Double
        /// Minutes.
        let equationOfTime: Double

        init(century t: Double) {
            func rad(_ d: Double) -> Double { d * .pi / 180 }
            let meanLong = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
            let meanAnom = 357.52911 + t * (35999.05029 - 0.0001537 * t)
            let ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
            let center = sin(rad(meanAnom)) * (1.914602 - t * (0.004817 + 0.000014 * t))
                + sin(rad(2 * meanAnom)) * (0.019993 - 0.000101 * t)
                + sin(rad(3 * meanAnom)) * 0.000289
            let omega = rad(125.04 - 1934.136 * t)
            let appLong = meanLong + center - 0.00569 - 0.00478 * sin(omega)
            let meanObliq = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
            let obliq = meanObliq + 0.00256 * cos(omega)
            declination = asin(sin(rad(obliq)) * sin(rad(appLong))) * 180 / .pi
            let y = pow(tan(rad(obliq / 2)), 2)
            let l0 = rad(meanLong), m = rad(meanAnom)
            equationOfTime = 4 * (y * sin(2 * l0) - 2 * ecc * sin(m) + 4 * ecc * y * sin(m) * cos(2 * l0)
                - 0.5 * y * y * sin(4 * l0) - 1.25 * ecc * ecc * sin(2 * m)) * 180 / .pi
        }
    }

    /// A rough place from the time zone alone, when she hasn't shared her
    /// location: the zone's standard offset × 15° for longitude, and a mid
    /// latitude (40°, or −35° in the southern-hemisphere zones). Sunrise
    /// and sunset come out within about an hour, which is all the Sky
    /// theme needs.
    public static func approximatePlace(for timeZone: TimeZone, at date: Date = .now) -> (latitude: Double, longitude: Double) {
        let standard = Double(timeZone.secondsFromGMT(for: date)) - timeZone.daylightSavingTimeOffset(for: date)
        let longitude = min(max(standard / 3600 * 15, -180), 180)
        let south = ["Australia/", "Pacific/Auckland", "Pacific/Chatham", "America/Argentina", "America/Sao_Paulo",
                     "America/Santiago", "America/Montevideo", "America/Asuncion", "Africa/Johannesburg",
                     "Africa/Maputo", "Africa/Windhoek", "Indian/Antananarivo", "Indian/Mauritius"]
        let isSouth = south.contains { timeZone.identifier.hasPrefix($0) }
        return (isSouth ? -35 : 40, longitude)
    }
}

/// The four looks of the Sky theme, in the order the day passes through them.
public enum SkyPhase: String, CaseIterable, Sendable {
    case night, sunrise, day, sunset
}

/// Where the sky is between two phases: `amount` 0 is all `from`, 1 all `to`.
public struct SkyBlend: Equatable, Sendable {
    public var from: SkyPhase
    public var to: SkyPhase
    public var amount: Double

    public init(from: SkyPhase, to: SkyPhase, amount: Double) {
        self.from = from
        self.to = to
        self.amount = amount
    }

    public static func steady(_ phase: SkyPhase) -> SkyBlend { SkyBlend(from: phase, to: phase, amount: 0) }

    /// The phase that has the most of the look.
    public var nearest: SkyPhase { amount < 0.5 ? from : to }

    /// Rounded to `steps` per blend, so the look only changes a few times an
    /// hour (each change redraws the screen's background once).
    public func quantized(steps: Int) -> SkyBlend {
        guard from != to else { return self }
        let q = (amount * Double(steps)).rounded() / Double(steps)
        if q <= 0 { return .steady(from) }
        if q >= 1 { return .steady(to) }
        return SkyBlend(from: from, to: to, amount: q)
    }
}

extension Sun {
    /// The sky's look at `now`, from that day's sunrise and sunset. Each
    /// change of phase blends over an hour:
    ///
    /// | From | To | Blend |
    /// |---|---|---|
    /// | night | sunrise | the hour before sunrise |
    /// | sunrise | day | 45 to 105 min after sunrise |
    /// | day | sunset | 75 to 15 min before sunset |
    /// | sunset | night | 20 to 80 min after sunset |
    ///
    /// On days too short for all four (far north in winter), the blends
    /// are squeezed into the daylight in proportion.
    public static func sky(at now: Date, sunrise: Date, sunset: Date) -> SkyBlend {
        let r = now.timeIntervalSince(sunrise) / 60
        let daylight = sunset.timeIntervalSince(sunrise) / 60
        let s = now.timeIntervalSince(sunset) / 60
        // Sunrise hold + blend (105) and sunset blend + hold (75) fit in a
        // day of 180 min or more; shorter days scale both.
        let squeeze = min(1, max(daylight, 1) / 180)

        func ramp(_ x: Double, _ start: Double, _ end: Double) -> Double { min(max((x - start) / (end - start), 0), 1) }

        if r < -60 { return .steady(.night) }
        if r < 0 { return SkyBlend(from: .night, to: .sunrise, amount: ramp(r, -60, 0)) }
        if s >= 80 { return .steady(.night) }
        if s >= 20 { return SkyBlend(from: .sunset, to: .night, amount: ramp(s, 20, 80)) }
        if s >= -15 * squeeze { return .steady(.sunset) }
        if s >= -75 * squeeze { return SkyBlend(from: .day, to: .sunset, amount: ramp(s, -75 * squeeze, -15 * squeeze)) }
        if r < 45 * squeeze { return .steady(.sunrise) }
        if r < 105 * squeeze { return SkyBlend(from: .sunrise, to: .day, amount: ramp(r, 45 * squeeze, 105 * squeeze)) }
        return .steady(.day)
    }

    /// The sky's look at `now` where she is.
    public static func sky(at now: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> SkyBlend {
        switch day(now, latitude: latitude, longitude: longitude, timeZone: timeZone) {
        case .alwaysUp: return .steady(.day)
        case .alwaysDown: return .steady(.night)
        case .rises(let sunrise, let sunset): return sky(at: now, sunrise: sunrise, sunset: sunset)
        }
    }
}
