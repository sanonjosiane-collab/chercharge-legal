//
//  CustomerAppNotification.swift
//  Chercharge
//
//  In-app notifications shown from the Home bell (admin document decisions, etc.).
//

import Foundation

enum CustomerAppNotificationKind: String, Codable, Hashable {
    case documentsApproved
    case documentsRejected
}

struct CustomerAppNotification: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: CustomerAppNotificationKind
    let title: String
    let body: String
    let vehicleID: UUID?
    let createdAt: Date
    var isRead: Bool

    static func documentsDecision(
        vehicleID: UUID,
        vehicleName: String,
        approved: Bool,
        reason: String?
    ) -> CustomerAppNotification {
        if approved {
            return CustomerAppNotification(
                id: UUID(),
                kind: .documentsApproved,
                title: "Documents approved",
                body: "\(vehicleName) is cleared for concierge charging. You can book a charge when ready.",
                vehicleID: vehicleID,
                createdAt: Date(),
                isRead: false
            )
        }
        let detail: String
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detail = "\(vehicleName): \(reason)"
        } else {
            detail =
                "\(vehicleName) documents were not approved. Update your registration photo or policy and resubmit."
        }
        return CustomerAppNotification(
            id: UUID(),
            kind: .documentsRejected,
            title: "Documents need revision",
            body: detail,
            vehicleID: vehicleID,
            createdAt: Date(),
            isRead: false
        )
    }
}
