//
//  InspectionNotificationService.swift
//  Chercharge
//
//  Local notifications for booking confirmation and live job progress.
//  Always show an in-app explanation before the first system permission prompt.
//

import Foundation
import UIKit
import UserNotifications

enum InspectionNotificationService {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isAuthorizedForAlerts() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// System permission prompt only — call after the in-app pre-prompt (or from Settings after explanation).
    /// On grant, also registers with APNs so Firebase can mint a valid FCM token.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        let allowed: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            allowed = true
        case .denied:
            allowed = false
        case .notDetermined:
            do {
                allowed = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                allowed = false
            }
        @unknown default:
            allowed = false
        }

        if allowed {
            await registerForRemoteNotificationsIfNeeded()
        }
        return allowed
    }

    /// Used after booking when the customer already opted into service notifications.
    @discardableResult
    static func enableForBookingFlow() async -> Bool {
        if await isAuthorizedForAlerts() {
            await registerForRemoteNotificationsIfNeeded()
            return true
        }
        return await requestAuthorization()
    }

    /// APNs registration must run on the main thread after notification permission is granted.
    static func registerForRemoteNotificationsIfNeeded() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    static func notifyBookingConfirmed(jobID: UUID, scheduledFor: Date? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "Booking confirmation"
        if let scheduledFor, scheduledFor > Date().addingTimeInterval(60 * 60) {
            content.body = "Your Chercharge pickup is scheduled. We’ll notify you as your concierge progresses."
        } else {
            content.body = "Your Chercharge concierge is preparing. Track live status in Reservations."
        }
        content.sound = .default
        content.userInfo = ["jobID": jobID.uuidString, "kind": "bookingConfirmed"]
        schedule(identifier: "booking-\(jobID.uuidString)", content: content, delay: 0.4)
    }

    static func notifyJobStatusChanged(jobID: UUID, status: JobStatus) {
        let content = UNMutableNotificationContent()
        content.title = statusNotificationTitle(for: status)
        content.body = status.detail
        content.sound = .default
        content.userInfo = [
            "jobID": jobID.uuidString,
            "kind": "jobStatus",
            "status": status.rawValue
        ]
        schedule(
            identifier: "job-\(jobID.uuidString)-\(status.rawValue)",
            content: content,
            delay: 0.35
        )
    }

    static func notifyInspectionReadyForReview(jobID: UUID, phase: InspectionPhase) {
        let content = UNMutableNotificationContent()
        switch phase {
        case .preTrip:
            content.title = "Pickup update"
            content.body = "Your pre-trip inspection is ready for review. Approve within 15 seconds, or we’ll auto-approve."
        case .postTrip:
            content.title = "Return status"
            content.body = "Quick-look your return photos. Approve within 15 seconds, or we’ll auto-approve."
        }
        content.sound = .default
        content.userInfo = [
            "jobID": jobID.uuidString,
            "kind": "inspectionReady",
            "phase": phase.rawValue
        ]
        schedule(
            identifier: "inspection-\(jobID.uuidString)-\(phase.rawValue)",
            content: content,
            delay: 0.3
        )
    }

    static func notifyCustomBanner(
        jobID: UUID,
        title: String,
        body: String,
        kind: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "jobID": jobID.uuidString,
            "kind": kind
        ]
        schedule(
            identifier: "custom-\(jobID.uuidString)-\(kind)",
            content: content,
            delay: 0.3
        )
    }

    static func notifyPickupApproved(jobID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Vehicle pickup confirmation"
        content.body = "Pickup approved. Your Chercharge concierge is taking your vehicle to charge."
        content.sound = .default
        content.userInfo = ["jobID": jobID.uuidString, "kind": "pickupApproved"]
        schedule(identifier: "pickup-approved-\(jobID.uuidString)", content: content, delay: 0.25)
    }

    static func notifyReturnApproved(jobID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Vehicle returned confirmation"
        content.body = "Return approved. Thanks for riding with Chercharge."
        content.sound = .default
        content.userInfo = ["jobID": jobID.uuidString, "kind": "returnApproved"]
        schedule(identifier: "return-approved-\(jobID.uuidString)", content: content, delay: 0.25)
    }

    /// Customer-facing notice when admin finishes vehicle document review.
    static func notifyVehicleDocumentsDecision(
        vehicleID: UUID,
        vehicleName: String,
        approved: Bool,
        reason: String? = nil
    ) {
        let content = UNMutableNotificationContent()
        if approved {
            content.title = "Documents approved"
            content.body =
                "\(vehicleName) is cleared for concierge charging. You can book a charge when ready."
        } else {
            content.title = "Documents need revision"
            if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content.body = "\(vehicleName): \(reason)"
            } else {
                content.body =
                    "\(vehicleName) documents were not approved. Update your registration photo or policy and resubmit."
            }
        }
        content.sound = .default
        content.userInfo = [
            "vehicleID": vehicleID.uuidString,
            "kind": approved ? "vehicleDocsApproved" : "vehicleDocsRejected",
        ]
        schedule(
            identifier: "vehicle-docs-\(vehicleID.uuidString)-\(approved ? "ok" : "no")",
            content: content,
            delay: 0.35
        )
    }

    // MARK: - Private

    private static func statusNotificationTitle(for status: JobStatus) -> String {
        switch status {
        case .requested: return "Booking status"
        case .driverEnRoute: return "Pickup update"
        case .driverArrived: return "Pickup update"
        case .awaitingCustomerApproval: return "Pickup update"
        case .pickedUp: return "Vehicle pickup confirmation"
        case .charging: return "Charging status"
        case .returning: return "Return status"
        case .awaitingPostTripInspection: return "Return status"
        case .awaitingReturnApproval: return "Return status"
        case .delivered: return "Vehicle returned confirmation"
        }
    }

    private static func schedule(identifier: String, content: UNMutableNotificationContent, delay: TimeInterval) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.2, delay), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
