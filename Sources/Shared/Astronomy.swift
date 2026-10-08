import Foundation

/// Sunrise, sunset and full moon times, computed on device. Accurate to a minute or two, which is
/// plenty for a countdown.
enum Astronomy {
    enum SunEvent { case rise, set }

    /// The first sunrise or sunset after `date` at a place. Near the poles the sun can stay up or
    /// down for weeks, so this looks up to a year ahead; nil only if it never happens.
    static func nextSunEvent(_ event: SunEvent, after date: Date, latitude: Double, longitude: Double) -> Date? {
        let today = (julianDay(date) - j2000).rounded(.down)
        for offset in -1...370 {
            if let time = sunEvent(event, day: today + Double(offset), latitude: latitude, longitude: longitude),
               time > date {
                return time
            }
        }
        return nil
    }

    /// The first full moon after `date`.
    static func nextFullMoon(after date: Date) -> Date {
        // Lunations since the full moon of January 2000, rounded to land on a full moon (k + 0.5).
        var k = ((julianDay(date) - 2451550.09766) / synodicMonth).rounded(.down) - 1
        while true {
            let moon = fullMoon(lunation: k + 0.5)
            if moon > date { return moon }
            k += 1
        }
    }

    // MARK: - Sun

    private static let j2000 = 2451545.0
    private static let synodicMonth = 29.530588861

    /// The sunrise equation (as used by NOAA's simpler calculator) for one solar day counted from J2000.
    private static func sunEvent(_ event: SunEvent, day: Double, latitude: Double, longitude: Double) -> Date? {
        let meanSolarNoon = day - longitude / 360
        let anomaly = normalized(357.5291 + 0.98560028 * meanSolarNoon)
        let center = 1.9148 * sin(radians(anomaly)) + 0.02 * sin(radians(2 * anomaly))
            + 0.0003 * sin(radians(3 * anomaly))
        let eclipticLongitude = normalized(anomaly + center + 180 + 102.9372)
        let transit = j2000 + meanSolarNoon + 0.0053 * sin(radians(anomaly))
            - 0.0069 * sin(radians(2 * eclipticLongitude))
        let declination = asin(sin(radians(eclipticLongitude)) * sin(radians(23.4397)))
        // -0.833° allows for refraction and the sun's radius: the top edge touching the horizon.
        let cosHourAngle = (sin(radians(-0.833)) - sin(radians(latitude)) * sin(declination))
            / (cos(radians(latitude)) * cos(declination))
        guard (-1...1).contains(cosHourAngle) else { return nil }  // polar day or night
        let hourAngle = degrees(acos(cosHourAngle))
        return date(julianDay: event == .rise ? transit - hourAngle / 360 : transit + hourAngle / 360)
    }

    // MARK: - Moon

    /// Meeus, Astronomical Algorithms, chapter 49: the full moon of lunation `k` (k ends in .5).
    private static func fullMoon(lunation k: Double) -> Date {
        let t = k / 1236.85
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t
        var jde = 2451550.09766 + synodicMonth * k + 0.00015437 * t2 - 0.000000150 * t3 + 0.00000000073 * t4

        let e = 1 - 0.002516 * t - 0.0000074 * t2
        let m = radians(2.5534 + 29.10535670 * k - 0.0000014 * t2 - 0.00000011 * t3)
        let mp = radians(201.5643 + 385.81693528 * k + 0.0107582 * t2 + 0.00001238 * t3 - 0.000000058 * t4)
        let f = radians(160.7108 + 390.67050284 * k - 0.0016118 * t2 - 0.00000227 * t3 + 0.000000011 * t4)
        let omega = radians(124.7746 - 1.56375588 * k + 0.0020672 * t2 + 0.00000215 * t3)

        jde += -0.40614 * sin(mp)
            + 0.17302 * e * sin(m)
            + 0.01614 * sin(2 * mp)
            + 0.01043 * sin(2 * f)
            + 0.00734 * e * sin(mp - m)
            - 0.00515 * e * sin(mp + m)
            + 0.00209 * e * e * sin(2 * m)
            - 0.00111 * sin(mp - 2 * f)
            - 0.00057 * sin(mp + 2 * f)
            + 0.00056 * e * sin(2 * mp + m)
            - 0.00042 * sin(3 * mp)
            + 0.00042 * e * sin(m + 2 * f)
            + 0.00038 * e * sin(m - 2 * f)
            - 0.00024 * e * sin(2 * mp - m)
            - 0.00017 * sin(omega)
            - 0.00007 * sin(mp + 2 * m)
            + 0.00004 * sin(2 * mp - 2 * f)
            + 0.00004 * sin(3 * m)
            + 0.00003 * sin(mp + m - 2 * f)
            + 0.00003 * sin(2 * mp + 2 * f)
            - 0.00003 * sin(mp + m + 2 * f)
            + 0.00003 * sin(mp - m + 2 * f)
            - 0.00002 * sin(mp - m - 2 * f)
            - 0.00002 * sin(3 * mp + m)
            + 0.00002 * sin(4 * mp)

        // Small pulls from the planets.
        let planetary: [(Double, Double, Double)] = [
            (299.77, 0.107408, 0.000325), (251.88, 0.016321, 0.000165), (251.83, 26.651886, 0.000164),
            (349.42, 36.412478, 0.000126), (84.66, 18.206239, 0.000110), (141.74, 53.303771, 0.000062),
            (207.14, 2.453732, 0.000060), (154.84, 7.306860, 0.000056), (34.52, 27.261239, 0.000047),
            (207.19, 0.121824, 0.000042), (291.34, 1.844379, 0.000040), (161.72, 24.198154, 0.000037),
            (239.56, 25.513099, 0.000035), (331.55, 3.592518, 0.000023),
        ]
        for (index, (base, rate, coefficient)) in planetary.enumerated() {
            var argument = base + rate * k
            if index == 0 { argument -= 0.009173 * t2 }
            jde += coefficient * sin(radians(argument))
        }
        // Ephemeris time runs about 69 seconds ahead of UTC.
        return date(julianDay: jde - 69.0 / 86_400)
    }

    // MARK: - Helpers

    private static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2440587.5 }
    private static func date(julianDay: Double) -> Date { Date(timeIntervalSince1970: (julianDay - 2440587.5) * 86_400) }
    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
