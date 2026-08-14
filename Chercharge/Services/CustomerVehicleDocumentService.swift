//
//  CustomerVehicleDocumentService.swift
//  Chercharge
//
//  Submits customer registration photo + policy to Chercharge Admin via
//  Edge Function (works even when the user only has Firebase / local auth).
//

import Foundation
import UIKit

struct CustomerVehicleDocumentSubmitResponse: Decodable {
    let ok: Bool?
    let message: String?
    let error: String?
    let document: SubmittedDocument?

    struct SubmittedDocument: Decodable {
        let id: UUID?
        let status: String?
    }
}

struct CustomerVehicleDocumentDTO: Hashable, Identifiable {
    let id: UUID
    let customerId: UUID?
    let localVehicleId: UUID
    var status: String
    var submittedAt: Date?
    var reviewedAt: Date?
    var reviewerNote: String?

    var approvalStatus: VehicleDocumentApprovalStatus {
        switch status {
        case "approved": return .approved
        case "rejected": return .rejected
        case "pendingReview": return .pendingReview
        default: return .incomplete
        }
    }

    /// Lenient decode — admin status sync must not fail the whole batch on one bad date.
    init?(json: [String: Any]) {
        guard let localRaw = json["local_vehicle_id"] as? String,
              let localVehicleId = UUID(uuidString: localRaw) else { return nil }
        let id = (json["id"] as? String).flatMap(UUID.init(uuidString:)) ?? localVehicleId
        let customerId = (json["customer_id"] as? String).flatMap(UUID.init(uuidString:))
        let status = (json["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "pendingReview"
        self.id = id
        self.customerId = customerId
        self.localVehicleId = localVehicleId
        self.status = status
        self.submittedAt = Self.parseDate(json["submitted_at"])
        self.reviewedAt = Self.parseDate(json["reviewed_at"])
        self.reviewerNote = json["reviewer_note"] as? String

    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let raw = value as? String, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        // Postgres style: "2026-07-29 18:00:00.123456+00"
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ssxxxxx"
        if let date = fallback.date(from: raw) { return date }
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSxxxxx"
        return fallback.date(from: raw)
    }
}

final class CustomerVehicleDocumentService {
    static let shared = CustomerVehicleDocumentService()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var isAvailable: Bool {
        SupabaseConfig.isConfigured
    }

    /// Submit registration photo + policy to the Chercharge Admin Customers queue.
    @discardableResult
    func submitForAdminReview(
        vehicle: Vehicle,
        customerID: UUID?,
        customerName: String,
        customerEmail: String
    ) async throws -> CustomerVehicleDocumentSubmitResponse {
        try SupabaseConfig.validate()

        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), !email.hasSuffix("@chercharge.local") else {
            throw ServiceError.needsEmailAccount
        }
        guard vehicle.hasRegistrationPhoto || vehicle.hasPolicyNumber else {
            throw ServiceError.incomplete
        }

        let registrationExpiration = vehicle.registrationExpirationDate.map { dateFormatter.string(from: $0) }
        let policyExpiration = vehicle.insurancePolicyExpirationDate.map { dateFormatter.string(from: $0) }
        let registrationPhoto = vehicle.registrationPhotoData
        let insuranceCard = vehicle.insuranceCardPhotoData

        // Image decode / resize / base64 must NOT run on the main actor — that froze the app.
        let photoBase64 = await Task.detached(priority: .userInitiated) {
            Self.jpegDataForUpload(registrationPhoto)?.base64EncodedString()
        }.value
        let cardBase64 = await Task.detached(priority: .userInitiated) {
            Self.jpegDataForUpload(insuranceCard)?.base64EncodedString()
        }.value

        var body: [String: Any] = [
            "customer_email": email,
            "customer_name": customerName.trimmingCharacters(in: .whitespacesAndNewlines),
            "local_vehicle_id": vehicle.id.uuidString,
            "vehicle_display_name": vehicle.displayName,
            "license_plate": vehicle.licensePlateDisplay,
            "make": vehicle.make,
            "model": vehicle.model,
            "year": vehicle.year,
            "insurance_policy": vehicle.insurancePolicy,
            "insurance_company_name": vehicle.insuranceCompanyName,
        ]
        if let registrationExpiration {
            body["registration_expiration"] = registrationExpiration
        }
        if let policyExpiration {
            body["policy_expiration"] = policyExpiration
        }
        if let photoBase64 {
            body["registration_photo_base64"] = photoBase64
        }
        if let cardBase64 {
            body["insurance_card_photo_base64"] = cardBase64
        }

        let data = try await invokeRaw(
            name: "submit-customer-vehicle-documents",
            token: nil,
            body: body
        )
        let response = try JSONDecoder().decode(CustomerVehicleDocumentSubmitResponse.self, from: data)
        if let error = response.error, response.ok != true {
            throw ServiceError.backend(error)
        }
        return response
    }

    /// Look up admin decisions by garage vehicle ids (primary) + email (soft filter).
    func fetchStatusesByEmail(
        email: String,
        localVehicleIDs: [UUID]
    ) async throws -> [CustomerVehicleDocumentDTO] {
        try SupabaseConfig.validate()
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") || !localVehicleIDs.isEmpty else { return [] }

        let body: [String: Any] = [
            "action": "status",
            "customer_email": normalized,
            "local_vehicle_ids": localVehicleIDs.map(\.uuidString),
        ]
        let data = try await invokeRaw(
            name: "submit-customer-vehicle-documents",
            token: nil,
            body: body
        )

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.backend("Could not read document status response.")
        }
        if let error = root["error"] as? String, (root["ok"] as? Bool) != true {
            throw ServiceError.backend(error)
        }
        let rawDocs = (root["documents"] as? [[String: Any]]) ?? []
        return rawDocs.compactMap(CustomerVehicleDocumentDTO.init(json:))
    }

    private func invokeRaw(
        name: String,
        token: String?,
        body: [String: Any]
    ) async throws -> Data {
        let supabaseURL = try SupabaseConfig.url
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(name)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        try SupabaseConfig.applyClientAPIHeaders(to: &request, authorizationBearer: token)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.backend("Invalid response from document review server.")
        }

        if http.statusCode != 200 {
            if let decoded = try? JSONDecoder().decode(CustomerVehicleDocumentSubmitResponse.self, from: data),
               let message = decoded.error {
                throw ServiceError.backend(message)
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.backend("Document request failed (\(http.statusCode)). \(raw)")
        }
        return data
    }

    /// Downscale / re-encode so Edge Function JSON stays under body limits.
    /// Safe to call off the main thread.
    nonisolated private static func jpegDataForUpload(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        if let downsampled = ImageDecodeCache.decodeDownsampled(data: data, maxPixelSide: 1600),
           let jpeg = downsampled.jpegData(compressionQuality: 0.72) {
            return jpeg
        }
        return data
    }

    enum ServiceError: LocalizedError {
        case incomplete
        case needsEmailAccount
        case backend(String)

        var errorDescription: String? {
            switch self {
            case .incomplete:
                return "Registration photo or policy number is required for admin review."
            case .needsEmailAccount:
                return "Sign in with your email and password (not Guest) so admin can review your documents."
            case .backend(let message):
                return message
            }
        }
    }
}
