//
//  InspectionComparison.swift
//  Chercharge
//

import Foundation

struct InspectionIssueReport: Identifiable, Hashable, Codable {
    let id: UUID
    let jobID: UUID
    var category: String
    var details: String
    var highlightedDamage: [String]
    let createdAt: Date
}

struct InspectionPhotoPair: Identifiable, Hashable {
    let id: String
    let label: String
    let pickupData: Data
    let returnData: Data
    let isVideo: Bool
}

struct InspectionComparison: Hashable {
    let pickup: VehicleInspection
    let returnInspection: VehicleInspection

    var newDamageItems: [String] {
        returnInspection.damageChecklist.newDamage(comparedTo: pickup.damageChecklist)
    }

    var hasNewDamage: Bool {
        !newDamageItems.isEmpty || tiresWorsened
    }

    var tiresWorsened: Bool {
        returnInspection.tireCondition.isWorse(than: pickup.tireCondition)
    }

    var newDamageNotes: String? {
        let pickupNotes = pickup.damageChecklist.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let returnNotes = returnInspection.damageChecklist.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !returnNotes.isEmpty, returnNotes != pickupNotes else { return nil }
        return returnNotes
    }

    var batteryDelta: Int {
        returnInspection.batteryPercent - pickup.batteryPercent
    }

    var photoPairs: [InspectionPhotoPair] {
        [
            .init(id: "front", label: "Front", pickupData: pickup.frontPhotoData, returnData: returnInspection.frontPhotoData, isVideo: false),
            .init(id: "rear", label: "Rear", pickupData: pickup.rearPhotoData, returnData: returnInspection.rearPhotoData, isVideo: false),
            .init(id: "left", label: "Left side", pickupData: pickup.leftSidePhotoData, returnData: returnInspection.leftSidePhotoData, isVideo: false),
            .init(id: "roof", label: "Roof", pickupData: pickup.roofPhotoData, returnData: returnInspection.roofPhotoData, isVideo: false),
            .init(id: "interior", label: "Interior video", pickupData: pickup.interiorVideoData, returnData: returnInspection.interiorVideoData, isVideo: true),
            .init(id: "odometer", label: "Odometer", pickupData: pickup.odometerPhotoData, returnData: returnInspection.odometerPhotoData, isVideo: false)
        ]
    }

    var highlightSummary: String {
        var parts = newDamageItems
        if tiresWorsened {
            parts.append("Tire condition worsened (\(pickup.tireCondition.title) → \(returnInspection.tireCondition.title))")
        }
        if parts.isEmpty { return "No new damage flagged between pickup and return." }
        return parts.joined(separator: " · ")
    }
}

enum InspectionIssueCategory: String, CaseIterable, Identifiable {
    case newDamage = "New damage"
    case missingItems = "Missing items / belongings"
    case incorrectInspection = "Incorrect inspection"
    case other = "Other"

    var id: String { rawValue }
}
