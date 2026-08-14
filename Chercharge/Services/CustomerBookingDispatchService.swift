//
//  CustomerBookingDispatchService.swift
//  Chercharge
//
//  Sends PLACE REQUEST bookings to the driver open-jobs pool via Edge Function
//  (works with Firebase / local auth — no Supabase JWT required).
//

import Foundation

struct CustomerBookingDispatchResponse: Decodable {
    let ok: Bool?
    let message: String?
    let error: String?
    let booking: DispatchedBooking?

    struct DispatchedBooking: Decodable {
        let id: UUID
        let status: String?
        let customerId: UUID?
        let vehicleId: UUID?

        enum CodingKeys: String, CodingKey {
            case id
            case status
            case customerId = "customer_id"
            case vehicleId = "vehicle_id"
        }
    }
}

struct CustomerBookingStatusDTO: Decodable, Hashable {
    let id: UUID
    let status: String
    let driverId: UUID?
    let customerName: String?
    let vehicleName: String?
    let preTripInspection: CloudInspectionPayload?
    let postTripInspection: CloudInspectionPayload?
    let customerApprovedPickupAt: Date?
    let customerApprovedReturnAt: Date?
    /// Server-stored 15s auto-approve deadline (source of truth).
    let customerApprovalDeadline: Date?
    /// Server-stored 15s return auto-approve deadline (source of truth).
    let returnApprovalDeadline: Date?
    let pickupApprovalMethod: String?
    let returnApprovalMethod: String?
    /// Filled by `fetchStatus` from the envelope `pending_push` field (not a booking column).
    var pendingPush: PendingPushDTO? = nil
    /// Normalized inbox rows from the status poll (`notifications`).
    var notifications: [BookingNotificationDTO] = []
    /// True when an unread `inspection_ready` notification exists for this booking.
    var inspectionReady: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case driverId = "driver_id"
        case customerName = "customer_name"
        case vehicleName = "vehicle_name"
        case preTripInspection = "pre_trip_inspection"
        case postTripInspection = "post_trip_inspection"
        case customerApprovedPickupAt = "customer_approved_pickup_at"
        case customerApprovedReturnAt = "customer_approved_return_at"
        case customerApprovalDeadline = "customer_approval_deadline"
        case returnApprovalDeadline = "return_approval_deadline"
        case pickupApprovalMethod = "pickup_approval_method"
        case returnApprovalMethod = "return_approval_method"
    }

    var jobStatus: JobStatus? {
        guard let raw = JobStatus(rawValue: status) else { return nil }
        // Cloud often stores return-ready as awaitingPostTripInspection once photos exist.
        return JobStatus.resolvedFromCloud(
            status: raw,
            hasPreTripInspection: preTripInspection != nil,
            customerApprovedPickupAt: customerApprovedPickupAt,
            hasPostTripInspection: postTripInspection != nil,
            customerApprovedReturnAt: customerApprovedReturnAt
        )
    }

    /// Unread inspection-ready notification for this booking (server inbox).
    var unreadInspectionNotification: BookingNotificationDTO? {
        notifications.first {
            $0.type == "inspection_ready"
                && $0.bookingId == id
                && $0.readAt == nil
        }
    }
}

struct PendingPushDTO: Decodable, Hashable {
    let id: UUID?
    let event: String?
    let title: String?
    let body: String?

    var inspectionPhase: InspectionPhase? {
        switch event {
        case "inspection_ready_preTrip": return .preTrip
        case "inspection_ready_postTrip": return .postTrip
        default: return nil
        }
    }

    var jobStatusHint: JobStatus? {
        switch event {
        case "driver_arrived": return .driverArrived
        case "driver_en_route": return .driverEnRoute
        default: return nil
        }
    }
}

/// Normalized customer notification from `push_events` (status / notifications poll).
struct BookingNotificationDTO: Decodable, Hashable {
    let id: UUID?
    let type: String?
    let event: String?
    let bookingId: UUID?
    let title: String?
    let body: String?
    let phase: InspectionPhase?
    let readAt: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, type, event, title, body, phase
        case bookingId = "booking_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    var isUnreadInspectionReady: Bool {
        type == "inspection_ready" && readAt == nil
    }
}

@MainActor
final class CustomerBookingDispatchService {
    static let shared = CustomerBookingDispatchService()

    var isAvailable: Bool {
        SupabaseConfig.isConfigured
    }

    func createBooking(
        customerEmail: String,
        customerName: String,
        vehicle: Vehicle,
        pickup: LocationPin,
        station: LocationPin,
        targetChargePercent: Int,
        estimatedPrice: Decimal,
        estimatedMinutes: Int,
        paymentIntentID: String?
    ) async throws -> CustomerBookingDispatchResponse.DispatchedBooking {
        try SupabaseConfig.validate()

        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), !email.hasSuffix("@chercharge.local") else {
            throw ServiceError.needsEmailAccount
        }

        var body: [String: Any] = [
            "customer_email": email,
            "customer_name": customerName.trimmingCharacters(in: .whitespacesAndNewlines),
            "local_vehicle_id": vehicle.id.uuidString,
            "vehicle_name": vehicle.displayName,
            "vehicle_make": vehicle.make,
            "vehicle_model": vehicle.model,
            "vehicle_year": vehicle.year,
            "vehicle_plate": vehicle.licensePlateDisplay,
            "smoking_in_vehicle": vehicle.smokingInVehicle,
            "current_charge_percent": vehicle.currentChargePercent,
            "target_charge_percent": targetChargePercent,
            "pickup_name": pickup.name,
            "pickup_address": pickup.address,
            "pickup_lat": pickup.latitude,
            "pickup_lng": pickup.longitude,
            "station_name": station.name,
            "station_address": station.address,
            "station_lat": station.latitude,
            "station_lng": station.longitude,
            "estimated_price": NSDecimalNumber(decimal: estimatedPrice).doubleValue,
            "estimated_minutes": estimatedMinutes,
        ]
        if let paymentIntentID, !paymentIntentID.isEmpty {
            body["payment_intent_id"] = paymentIntentID
        }

        let response: CustomerBookingDispatchResponse = try await invoke(
            body: body
        )

        if let error = response.error, response.ok != true {
            throw ServiceError.backend(error)
        }
        guard let booking = response.booking else {
            throw ServiceError.backend(response.error ?? "Driver dispatch returned no booking.")
        }
        return booking
    }

    func fetchStatus(
        customerEmail: String,
        bookingID: UUID
    ) async throws -> CustomerBookingStatusDTO? {
        try SupabaseConfig.validate()
        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { return nil }

        struct Envelope: Decodable {
            let ok: Bool?
            let error: String?
            let booking: CustomerBookingStatusDTO?
            let pendingPush: PendingPushDTO?
            let notifications: [BookingNotificationDTO]?
            let inspectionReady: Bool?

            enum CodingKeys: String, CodingKey {
                case ok, error, booking
                case pendingPush = "pending_push"
                case notifications
                case inspectionReady = "inspection_ready"
            }
        }

        let envelope: Envelope = try await invoke(
            body: [
                "action": "status",
                "customer_email": email,
                "booking_id": bookingID.uuidString,
            ]
        )
        if let error = envelope.error, envelope.ok != true {
            throw ServiceError.backend(error)
        }
        guard var booking = envelope.booking else { return nil }
        booking.pendingPush = envelope.pendingPush
        booking.notifications = envelope.notifications ?? []
        booking.inspectionReady = envelope.inspectionReady
            ?? (booking.unreadInspectionNotification != nil)
        return booking
    }

    /// Poll customer notifications (optionally filtered to one booking).
    func fetchNotifications(
        customerEmail: String,
        bookingID: UUID? = nil
    ) async throws -> (notifications: [BookingNotificationDTO], inspectionReady: Bool) {
        try SupabaseConfig.validate()
        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { return ([], false) }

        struct Envelope: Decodable {
            let ok: Bool?
            let error: String?
            let notifications: [BookingNotificationDTO]?
            let inspectionReady: Bool?

            enum CodingKeys: String, CodingKey {
                case ok, error, notifications
                case inspectionReady = "inspection_ready"
            }
        }

        var body: [String: Any] = [
            "action": "notifications",
            "customer_email": email,
        ]
        if let bookingID {
            body["booking_id"] = bookingID.uuidString
        }

        let envelope: Envelope = try await invoke(body: body)
        if let error = envelope.error, envelope.ok != true {
            throw ServiceError.backend(error)
        }
        let list = envelope.notifications ?? []
        let ready = envelope.inspectionReady
            ?? list.contains { $0.isUnreadInspectionReady && (bookingID == nil || $0.bookingId == bookingID) }
        return (list, ready)
    }

    func approvePickup(customerEmail: String, bookingID: UUID) async throws {
        try await postApproval(
            action: "approve_pickup",
            customerEmail: customerEmail,
            bookingID: bookingID
        )
    }

    func approveReturn(customerEmail: String, bookingID: UUID) async throws {
        try await postApproval(
            action: "approve_return",
            customerEmail: customerEmail,
            bookingID: bookingID
        )
    }

    /// Server-side 15s auto-approve (works even if this device never opened the sheet).
    @discardableResult
    func autoApproveDue(bookingID: UUID) async -> Bool {
        guard SupabaseConfig.isConfigured else { return false }
        struct Envelope: Decodable {
            let ok: Bool?
            let approved: Bool?
            let error: String?
        }
        do {
            let envelope: Envelope = try await invoke(
                body: [
                    "action": "auto_approve_due",
                    "booking_id": bookingID.uuidString,
                ]
            )
            return envelope.approved == true
        } catch {
            #if DEBUG
            print("auto_approve_due failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Marks a push_events row delivered after the customer app schedules a local banner.
    func acknowledgePendingPush(
        customerEmail: String,
        bookingID: UUID,
        pushEventID: UUID
    ) async {
        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), SupabaseConfig.isConfigured else { return }
        struct Envelope: Decodable {
            let ok: Bool?
            let error: String?
        }
        do {
            let _: Envelope = try await invoke(
                body: [
                    "action": "acknowledge_push",
                    "customer_email": email,
                    "booking_id": bookingID.uuidString,
                    "push_event_id": pushEventID.uuidString,
                ]
            )
        } catch {
            #if DEBUG
            print("acknowledge_push failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func postApproval(
        action: String,
        customerEmail: String,
        bookingID: UUID
    ) async throws {
        try SupabaseConfig.validate()
        let email = customerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else {
            throw ServiceError.needsEmailAccount
        }

        struct Envelope: Decodable {
            let ok: Bool?
            let error: String?
        }

        let envelope: Envelope = try await invoke(
            body: [
                "action": action,
                "customer_email": email,
                "booking_id": bookingID.uuidString,
            ]
        )
        if let error = envelope.error, envelope.ok != true {
            throw ServiceError.backend(error)
        }
    }

    private func invoke<T: Decodable>(body: [String: Any]) async throws -> T {
        let supabaseURL = try SupabaseConfig.url
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("create-customer-booking")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        try SupabaseConfig.applyClientAPIHeaders(to: &request, authorizationBearer: nil)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.backend("Invalid response from booking dispatch server.")
        }

        if let decoded = try? decoder.decode(CustomerBookingDispatchResponse.self, from: data),
           let message = decoded.error,
           http.statusCode != 200 {
            throw ServiceError.backend(message)
        }

        guard http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.backend("Booking dispatch failed (\(http.statusCode)). \(raw)")
        }

        return try decoder.decode(T.self, from: data)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let raw = try container.decode(String.self)
            if let date = Self.parseFlexibleDate(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date: \(raw)"
            )
        }
        return decoder
    }

    /// Accepts Postgres / driver timestamps with or without a timezone suffix.
    private static func parseFlexibleDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    enum ServiceError: LocalizedError {
        case needsEmailAccount
        case backend(String)

        var errorDescription: String? {
            switch self {
            case .needsEmailAccount:
                return "Sign in with your email and password (not Guest) so we can send your request to a driver."
            case .backend(let message):
                return message
            }
        }
    }
}
