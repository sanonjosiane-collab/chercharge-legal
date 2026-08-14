//
//  MapModels.swift
//  Chercharge
//

import CoreLocation
import Foundation

struct ChargingStation: Identifiable, Hashable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let stallCount: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum DriverAvailability: String, Hashable {
    case available
    case enRoute

    var title: String {
        switch self {
        case .available: return "Available"
        case .enRoute: return "En route"
        }
    }
}

struct NearbyDriver: Identifiable, Hashable {
    let id: UUID
    let label: String
    let latitude: Double
    let longitude: Double
    let status: DriverAvailability
    let etaMinutes: Int
    var rating: Double = 4.9
    var tier: String = "Concierge"

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var firstName: String {
        let head = label.components(separatedBy: "·").first ?? label
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ")
            .first ?? label
    }

    /// Single initial for the avatar circle (matches home mockup).
    var initials: String {
        String(firstName.prefix(1)).uppercased()
    }
}

enum SampleMapData {
    static let chargingStations: [ChargingStation] = [
        ChargingStation(
            id: UUID(uuidString: "E1111111-1111-1111-1111-111111111111")!,
            name: "Supercharger — Folsom",
            address: "500 Folsom St, San Francisco",
            latitude: 37.7879,
            longitude: -122.3910,
            stallCount: 12
        ),
        ChargingStation(
            id: UUID(uuidString: "E2222222-2222-2222-2222-222222222222")!,
            name: "Supercharger — Pierce St",
            address: "2110 Pierce St, San Francisco",
            latitude: 37.7896,
            longitude: -122.4365,
            stallCount: 8
        ),
        ChargingStation(
            id: UUID(uuidString: "E3333333-3333-3333-3333-333333333333")!,
            name: "Supercharger — Bryant",
            address: "998 Bryant St, San Francisco",
            latitude: 37.7726,
            longitude: -122.4058,
            stallCount: 10
        ),
        ChargingStation(
            id: UUID(uuidString: "E4444444-4444-4444-4444-444444444444")!,
            name: "Supercharger — Cesar Chavez",
            address: "2500 Cesar Chavez St, San Francisco",
            latitude: 37.7490,
            longitude: -122.4005,
            stallCount: 6
        )
    ]

    static let nearbyDrivers: [NearbyDriver] = [
        NearbyDriver(
            id: UUID(uuidString: "F3333333-3333-3333-3333-333333333333")!,
            label: "Jordan · Concierge",
            latitude: 37.7921,
            longitude: -122.4082,
            status: .available,
            etaMinutes: 3,
            rating: 4.99,
            tier: "Elite Concierge"
        ),
        NearbyDriver(
            id: UUID(uuidString: "F1111111-1111-1111-1111-111111111111")!,
            label: "Alex · Concierge",
            latitude: 37.7812,
            longitude: -122.3991,
            status: .available,
            etaMinutes: 5,
            rating: 4.92,
            tier: "Concierge"
        ),
        NearbyDriver(
            id: UUID(uuidString: "F2222222-2222-2222-2222-222222222222")!,
            label: "Sam · Concierge",
            latitude: 37.7764,
            longitude: -122.4148,
            status: .available,
            etaMinutes: 8,
            rating: 4.87,
            tier: "Concierge"
        )
    ]

    /// Camera center for the home map (SOMA / downtown SF).
    static let homeMapCenter = CLLocationCoordinate2D(latitude: 37.7786, longitude: -122.4050)
}
