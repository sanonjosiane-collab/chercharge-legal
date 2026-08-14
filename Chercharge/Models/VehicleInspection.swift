//
//  VehicleInspection.swift
//  Chercharge
//

import Foundation

enum InspectionPhase: String, Codable, Hashable {
    case preTrip
    case postTrip

    var title: String {
        switch self {
        case .preTrip: return "Pre-trip inspection"
        case .postTrip: return "Post-trip inspection"
        }
    }
}

enum TireCondition: String, CaseIterable, Identifiable, Hashable, Codable {
    case good
    case fair
    case poor
    case flat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .flat: return "Flat / unsafe"
        }
    }
}

struct DamageChecklist: Hashable, Codable {
    var scratches = false
    var dents = false
    var crackedGlass = false
    var missingParts = false
    var other = false
    var notes = ""

    var flaggedLabels: [String] {
        var items: [String] = []
        if scratches { items.append("Scratches") }
        if dents { items.append("Dents") }
        if crackedGlass { items.append("Cracked glass") }
        if missingParts { items.append("Missing parts") }
        if other { items.append("Other") }
        return items
    }

    var summary: String {
        let joined = flaggedLabels.isEmpty ? "None noted" : flaggedLabels.joined(separator: ", ")
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? joined : "\(joined). \(trimmed)"
    }

    /// Damage flags present on return that were not present at pickup.
    func newDamage(comparedTo pickup: DamageChecklist) -> [String] {
        flaggedLabels.filter { !pickup.flaggedLabels.contains($0) }
    }

    var hasNotesChange: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension TireCondition {
    var severity: Int {
        switch self {
        case .good: return 0
        case .fair: return 1
        case .poor: return 2
        case .flat: return 3
        }
    }

    func isWorse(than other: TireCondition) -> Bool {
        severity > other.severity
    }
}

struct InspectionMediaURLs: Hashable, Codable {
    var frontPhotoURL: String?
    var rearPhotoURL: String?
    var leftSidePhotoURL: String?
    var roofPhotoURL: String?
    var interiorVideoURL: String?
    var odometerPhotoURL: String?
}

struct VehicleInspection: Identifiable, Hashable, Codable {
    let id: UUID
    let jobID: UUID
    let phase: InspectionPhase
    let driverName: String
    var frontPhotoData: Data
    var rearPhotoData: Data
    var leftSidePhotoData: Data
    var roofPhotoData: Data
    var interiorVideoData: Data
    var odometerPhotoData: Data
    var batteryPercent: Int
    var damageChecklist: DamageChecklist
    var tireCondition: TireCondition
    var capturedAt: Date
    var latitude: Double
    var longitude: Double
    var storageURLs: InspectionMediaURLs
    var uploadedAt: Date?

    var isComplete: Bool {
        !frontPhotoData.isEmpty
            && !rearPhotoData.isEmpty
            && !leftSidePhotoData.isEmpty
            && !roofPhotoData.isEmpty
            && !interiorVideoData.isEmpty
            && !odometerPhotoData.isEmpty
            && (0...100).contains(batteryPercent)
    }

    var pickupCoordinateLabel: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}
