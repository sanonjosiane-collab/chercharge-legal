//
//  LocationPin.swift
//  Chercharge
//

import CoreLocation
import Foundation

struct LocationPin: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var gateCode: String?
    var apartmentUnit: String?
    var parkingSpot: String?
    var pickupInstructions: String?
    var vehicleNotes: String?
    var isDefault: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        gateCode: String? = nil,
        apartmentUnit: String? = nil,
        parkingSpot: String? = nil,
        pickupInstructions: String? = nil,
        vehicleNotes: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.gateCode = Self.nilIfBlank(gateCode)
        self.apartmentUnit = Self.nilIfBlank(apartmentUnit)
        self.parkingSpot = Self.nilIfBlank(parkingSpot)
        self.pickupInstructions = Self.nilIfBlank(pickupInstructions)
        self.vehicleNotes = Self.nilIfBlank(vehicleNotes)
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        address = try c.decode(String.self, forKey: .address)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        gateCode = try c.decodeIfPresent(String.self, forKey: .gateCode)
        apartmentUnit = try c.decodeIfPresent(String.self, forKey: .apartmentUnit)
        parkingSpot = try c.decodeIfPresent(String.self, forKey: .parkingSpot)
        pickupInstructions = try c.decodeIfPresent(String.self, forKey: .pickupInstructions)
        vehicleNotes = try c.decodeIfPresent(String.self, forKey: .vehicleNotes)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    private static func nilIfBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AddressLabelPreset: String, CaseIterable, Identifiable {
    case home = "Home"
    case work = "Work"
    case gym = "Gym"
    case airport = "Airport"
    case custom = "Custom"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .gym: return "figure.run"
        case .airport: return "airplane"
        case .custom: return "pencil"
        }
    }

    static func matching(name: String) -> AddressLabelPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.allCases.first { $0 != .custom && $0.rawValue.lowercased() == trimmed } ?? .custom
    }
}

enum SampleLocations {
    static let pickups: [LocationPin] = [
        LocationPin(
            id: UUID(uuidString: "B1111111-1111-1111-1111-111111111111")!,
            name: "Home",
            address: "24 Willie Mays Plaza, San Francisco",
            latitude: 37.7786,
            longitude: -122.3893,
            isDefault: true
        ),
        LocationPin(
            id: UUID(uuidString: "B2222222-2222-2222-2222-222222222222")!,
            name: "Office",
            address: "1 Market St, San Francisco",
            latitude: 37.7936,
            longitude: -122.3950
        ),
        LocationPin(
            id: UUID(uuidString: "B3333333-3333-3333-3333-333333333333")!,
            name: "Mission",
            address: "2999 Mission St, San Francisco",
            latitude: 37.7499,
            longitude: -122.4183
        )
    ]

    static let station = LocationPin(
        id: UUID(uuidString: "B4444444-4444-4444-4444-444444444444")!,
        name: "Supercharger — Folsom",
        address: "500 Folsom St, San Francisco",
        latitude: 37.7879,
        longitude: -122.3910
    )
}
