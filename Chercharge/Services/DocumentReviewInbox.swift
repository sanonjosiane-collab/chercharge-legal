//
//  DocumentReviewInbox.swift
//  Chercharge
//
//  Device-wide admin inbox for registration / policy document review.
//  Persisted separately from customer BookingStore so submissions remain
//  visible after sign-out / account switch on the same device.
//

import Foundation
import Observation

@Observable
@MainActor
final class DocumentReviewInbox {
    private static let fileName = "chercharge-document-review-inbox.json"

    private(set) var items: [DocumentReviewItem] = []

    var pendingItems: [DocumentReviewItem] {
        items
            .filter { $0.status == .pending }
            .sorted { lhs, rhs in
                if lhs.priorityScore != rhs.priorityScore {
                    return lhs.priorityScore > rhs.priorityScore
                }
                return lhs.submittedAt < rhs.submittedAt
            }
    }

    var pendingCount: Int { pendingItems.count }

    init() {
        // Load photo-heavy inbox JSON off the main thread.
        Task { await self.hydrateFromDisk() }
    }

    private func hydrateFromDisk() async {
        let url = Self.fileURL
        let loaded: [DocumentReviewItem] = await withCheckedContinuation { continuation in
            Self.ioQueue.async {
                guard let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: [])
                    return
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let items = (try? decoder.decode([DocumentReviewItem].self, from: data)) ?? []
                continuation.resume(returning: items)
            }
        }
        items = loaded
    }

    /// Upsert a pending review when the customer submits / updates documents.
    func enqueueSubmission(
        for vehicle: Vehicle,
        customerName: String,
        customerEmail: String
    ) {
        guard vehicle.documentApprovalStatus == .pendingReview else { return }
        guard vehicle.hasRegistrationPhoto || vehicle.hasPolicyNumber else { return }

        if let index = items.firstIndex(where: {
            $0.vehicleId == vehicle.id && $0.status == .pending
        }) {
            let existingID = items[index].id
            items[index] = DocumentReviewItem.make(
                from: vehicle,
                customerName: customerName,
                customerEmail: customerEmail,
                existingID: existingID
            )
        } else {
            // Don't reopen an already-approved item unless docs changed (new pending).
            items.removeAll {
                $0.vehicleId == vehicle.id && $0.status != .pending
            }
            items.insert(
                DocumentReviewItem.make(
                    from: vehicle,
                    customerName: customerName,
                    customerEmail: customerEmail
                ),
                at: 0
            )
        }
        persist()
    }

    /// Ensure any pending vehicles in the customer garage also appear in the admin inbox.
    func backfill(from vehicles: [Vehicle], customerName: String, customerEmail: String) {
        var changed = false
        for vehicle in vehicles where vehicle.documentApprovalStatus == .pendingReview {
            let alreadyPending = items.contains {
                $0.vehicleId == vehicle.id && $0.status == .pending
            }
            if alreadyPending {
                // Refresh photo/policy payload if the customer updated again.
                if let index = items.firstIndex(where: {
                    $0.vehicleId == vehicle.id && $0.status == .pending
                }) {
                    let existing = items[index]
                    // Compare metadata + photo byte counts — never memcmp multi‑MB blobs on MainActor.
                    let photoChanged =
                        existing.registrationPhotoData?.count != vehicle.registrationPhotoData?.count
                        || existing.insuranceCardPhotoData?.count != vehicle.insuranceCardPhotoData?.count
                    let metaChanged =
                        existing.insurancePolicy != vehicle.insurancePolicy
                        || existing.insuranceCompanyName != vehicle.insuranceCompanyName
                        || existing.customerName != customerName
                        || existing.customerEmail != customerEmail
                        || existing.vehicleDisplayName != vehicle.displayName
                    if photoChanged || metaChanged {
                        items[index] = DocumentReviewItem.make(
                            from: vehicle,
                            customerName: customerName,
                            customerEmail: customerEmail,
                            existingID: existing.id
                        )
                        changed = true
                    }
                }
            } else {
                items.insert(
                    DocumentReviewItem.make(
                        from: vehicle,
                        customerName: customerName,
                        customerEmail: customerEmail
                    ),
                    at: 0
                )
                changed = true
            }
        }
        if changed { persist() }
    }

    @discardableResult
    func approve(itemID: UUID) throws -> DocumentReviewItem {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw InboxError.notFound
        }
        guard items[index].status == .pending else {
            throw InboxError.notPending
        }
        items[index].status = .approved
        items[index].reviewedAt = Date()
        items[index].rejectionReason = nil
        persist()
        return items[index]
    }

    @discardableResult
    func reject(itemID: UUID, reason: String) throws -> DocumentReviewItem {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InboxError.reasonRequired }
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw InboxError.notFound
        }
        guard items[index].status == .pending else {
            throw InboxError.notPending
        }
        items[index].status = .rejected
        items[index].reviewedAt = Date()
        items[index].rejectionReason = trimmed
        persist()
        return items[index]
    }

    /// Apply inbox decisions onto matching vehicles in the customer garage.
    func applyDecisions(to vehicles: inout [Vehicle]) -> Bool {
        var changed = false
        let decisions = Dictionary(
            items
                .filter { $0.status == .approved || $0.status == .rejected }
                .map { ($0.vehicleId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for index in vehicles.indices {
            guard let decision = decisions[vehicles[index].id] else { continue }
            let vehicle = vehicles[index]
            switch decision.status {
            case .approved:
                guard vehicle.documentApprovalStatus != .approved else { continue }
                // Don't overwrite a newer customer resubmission still pending in inbox.
                if items.contains(where: {
                    $0.vehicleId == vehicle.id && $0.status == .pending
                }) { continue }
                vehicles[index] = vehicle.withDocumentApproval(
                    status: .approved,
                    submittedAt: vehicle.documentsSubmittedAt,
                    reviewedAt: decision.reviewedAt ?? Date(),
                    rejectionReason: nil
                )
                changed = true
            case .rejected:
                guard vehicle.documentApprovalStatus != .rejected
                        || vehicle.documentRejectionReason != decision.rejectionReason else { continue }
                if items.contains(where: {
                    $0.vehicleId == vehicle.id && $0.status == .pending
                }) { continue }
                vehicles[index] = vehicle.withDocumentApproval(
                    status: .rejected,
                    submittedAt: vehicle.documentsSubmittedAt,
                    reviewedAt: decision.reviewedAt ?? Date(),
                    rejectionReason: decision.rejectionReason
                )
                changed = true
            case .pending:
                continue
            }
        }
        return changed
    }

    private func persist() {
        let snapshot = items
        let url = Self.fileURL
        Self.ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static let ioQueue = DispatchQueue(
        label: "com.chercharge.document-review-inbox",
        qos: .utility
    )

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    enum InboxError: LocalizedError {
        case notFound
        case notPending
        case reasonRequired

        var errorDescription: String? {
            switch self {
            case .notFound: return "That submission could not be found."
            case .notPending: return "That submission is no longer awaiting review."
            case .reasonRequired: return "Add a short reason so the customer knows what to fix."
            }
        }
    }
}

extension Vehicle {
    func withDocumentApproval(
        status: VehicleDocumentApprovalStatus,
        submittedAt: Date?,
        reviewedAt: Date?,
        rejectionReason: String?
    ) -> Vehicle {
        Vehicle(
            id: id,
            name: name,
            make: make,
            model: model,
            year: year,
            licensePlate: licensePlate,
            licensePlateState: licensePlateState,
            registrationExpirationDate: registrationExpirationDate,
            insurancePolicy: insurancePolicy,
            insuranceCompanyName: insuranceCompanyName,
            insurancePolicyExpirationDate: insurancePolicyExpirationDate,
            currentChargePercent: currentChargePercent,
            estimatedRangeMiles: estimatedRangeMiles,
            registrationPhotoData: registrationPhotoData,
            insuranceCardPhotoData: insuranceCardPhotoData,
            teslaVIN: teslaVIN,
            isTeslaLinked: isTeslaLinked,
            paintColor: paintColor,
            smokingInVehicle: smokingInVehicle,
            documentApprovalStatus: status,
            documentsSubmittedAt: submittedAt,
            documentsReviewedAt: reviewedAt,
            documentRejectionReason: rejectionReason
        )
    }
}
