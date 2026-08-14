//
//  DocumentReviewItem.swift
//  Chercharge
//
//  Admin inbox row for vehicle documents. Survives customer sign-out so
//  an admin on the same device can still review submissions.
//

import Foundation

enum DocumentReviewItemStatus: String, Codable, Hashable {
    case pending
    case approved
    case rejected
}

struct DocumentReviewItem: Identifiable, Hashable, Codable {
    let id: UUID
    let vehicleId: UUID
    var customerName: String
    var customerEmail: String
    var vehicleDisplayName: String
    var licensePlateDisplay: String
    var make: String
    var model: String
    var year: Int
    /// High priority
    var registrationPhotoData: Data?
    /// High priority
    var insurancePolicy: String
    var insuranceCompanyName: String
    var registrationExpirationDate: Date?
    var insurancePolicyExpirationDate: Date?
    var insuranceCardPhotoData: Data?
    var submittedAt: Date
    var status: DocumentReviewItemStatus
    var reviewedAt: Date?
    var rejectionReason: String?

    var hasRegistrationPhoto: Bool {
        !(registrationPhotoData?.isEmpty ?? true)
    }

    var hasPolicyNumber: Bool {
        !insurancePolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var highPriorityItems: [String] {
        var items: [String] = []
        if hasRegistrationPhoto { items.append("Registration photo") }
        if hasPolicyNumber { items.append("Policy number") }
        return items
    }

    /// Registration photo + policy number weigh heaviest.
    var priorityScore: Int {
        guard status == .pending else { return 0 }
        var score = 100
        if hasRegistrationPhoto { score += 50 }
        if hasPolicyNumber { score += 50 }
        if !(insuranceCardPhotoData?.isEmpty ?? true) { score += 10 }
        return score
    }

    static func make(
        from vehicle: Vehicle,
        customerName: String,
        customerEmail: String,
        existingID: UUID? = nil
    ) -> DocumentReviewItem {
        DocumentReviewItem(
            id: existingID ?? UUID(),
            vehicleId: vehicle.id,
            customerName: customerName,
            customerEmail: customerEmail,
            vehicleDisplayName: vehicle.displayName,
            licensePlateDisplay: vehicle.licensePlateDisplay,
            make: vehicle.make,
            model: vehicle.model,
            year: vehicle.year,
            registrationPhotoData: vehicle.registrationPhotoData,
            insurancePolicy: vehicle.insurancePolicy,
            insuranceCompanyName: vehicle.insuranceCompanyName,
            registrationExpirationDate: vehicle.registrationExpirationDate,
            insurancePolicyExpirationDate: vehicle.insurancePolicyExpirationDate,
            insuranceCardPhotoData: vehicle.insuranceCardPhotoData,
            submittedAt: vehicle.documentsSubmittedAt ?? Date(),
            status: .pending,
            reviewedAt: nil,
            rejectionReason: nil
        )
    }
}
