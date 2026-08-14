//
//  UserLocationService.swift
//  Chercharge
//
//  Requests When-In-Use location and publishes the latest GPS fix for Home map centering.
//

import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class UserLocationService: NSObject {
    private let manager = CLLocationManager()

    /// Latest device GPS coordinate, if authorized and available.
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastError: String?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    /// Starts permission / updates when the in-app location preference is on.
    func refresh(preferenceEnabled: Bool) {
        guard preferenceEnabled else {
            manager.stopUpdatingLocation()
            return
        }

        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            // One-shot fix is enough for Home map centering; continuous updates
            // publish @Observable changes that re-render the whole Home screen.
            manager.requestLocation()
        case .denied, .restricted:
            lastError = "Location access is off. Enable it in Settings to center the map on you."
            manager.stopUpdatingLocation()
        @unknown default:
            break
        }
    }
}

extension UserLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                lastError = nil
                manager.requestLocation()
            case .denied, .restricted:
                lastError = "Location access is off. Enable it in Settings to center the map on you."
                manager.stopUpdatingLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            coordinate = location.coordinate
            lastError = nil
            manager.stopUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }
}
