import CoreLocation
import SwiftUI

/// The built-in "vampire hours" countdowns: next sunrise, next sunset and next full moon.
enum AutoDateTemplate {
    struct Filled {
        var title: String
        var details: String
        var targetDate: Date
        var auto: AutoDate
        var style: CountdownStyle
    }

    enum Failure: LocalizedError {
        case noSunEvent

        var errorDescription: String? {
            "The sun doesn't rise or set where you are for the next year. Impressive, but there's nothing to count."
        }
    }

    /// Works out the next occurrence, asking for a rough location first if the sun is involved.
    @MainActor
    static func fill(_ kind: AutoDate.Kind, now: Date = Date()) async throws -> Filled {
        var auto = AutoDate(kind: kind)
        if auto.needsLocation {
            let coordinate = try await RoughLocation.current()
            auto = AutoDate(kind: kind, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        guard let target = auto.next(after: now) else { throw Failure.noSunEvent }
        switch kind {
        case .sunrise:
            return Filled(title: "Sunrise", details: "Get to your coffin.", targetDate: target, auto: auto,
                          style: CountdownStyle(background: .scene(.sunset), font: .serif, accent: RGBAColor(hex: 0xFF8A3D)))
        case .sunset:
            return Filled(title: "Sunset", details: "The night is young.", targetDate: target, auto: auto,
                          style: CountdownStyle(background: .scene(.midnight), font: .serif, accent: RGBAColor(hex: 0xC2185B)))
        case .fullMoon:
            return Filled(title: "Full Moon", details: "Mind the wolves.", targetDate: target, auto: auto,
                          style: CountdownStyle(background: .scene(.harvestMoon), font: .serif, accent: RGBAColor(hex: 0xF4D35E)))
        }
    }
}

/// Asks for the device's approximate location once. Reduced accuracy is enough for the sun, and it's
/// all we ask for.
@MainActor
final class RoughLocation: NSObject, CLLocationManagerDelegate {
    enum Failure: LocalizedError {
        case denied, unavailable

        var errorDescription: String? {
            switch self {
            case .denied: "Count Downcula needs your rough location to know when the sun rises and sets. You can allow it in Settings."
            case .unavailable: "Couldn't find your location just now. Try again in a moment."
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var requested = false

    static func current() async throws -> CLLocationCoordinate2D {
        try await RoughLocation().locate()
    }

    private func locate() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.desiredAccuracy = kCLLocationAccuracyReduced
            // Setting the delegate reports the current authorization, which starts things off.
            manager.delegate = self
        }
    }

    private func authorizationChanged() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(Failure.denied))
        default:
            guard !requested else { return }
            requested = true
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        manager.delegate = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            if let location = locations.last { finish(.success(location.coordinate)) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(Failure.unavailable)) }
    }
}
