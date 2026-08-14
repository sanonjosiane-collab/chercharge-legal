//
//  JobStatus.swift
//  Chercharge
//

import Foundation

enum JobStatus: String, CaseIterable, Codable, Hashable {
    case requested
    case driverEnRoute
    case driverArrived
    case awaitingCustomerApproval
    case pickedUp
    case charging
    case returning
    case awaitingPostTripInspection
    case awaitingReturnApproval
    case delivered

    var title: String {
        switch self {
        case .requested: return "Request received"
        case .driverEnRoute: return "Driver en route"
        case .driverArrived: return "Driver arrived"
        case .awaitingCustomerApproval: return "Inspection ready for your review"
        case .pickedUp: return "Vehicle picked up"
        case .charging: return "Charging"
        case .returning: return "Returning your car"
        case .awaitingPostTripInspection: return "Driver finishing return inspection"
        case .awaitingReturnApproval: return "Return inspection ready for your review"
        case .delivered: return "Delivered"
        }
    }

    var detail: String {
        switch self {
        case .requested: return "We're matching you with a nearby charge valet."
        case .driverEnRoute: return "Your valet is heading to the pickup spot."
        case .driverArrived: return "Your concierge is with your vehicle. You’ll be notified when the inspection is ready to review."
        case .awaitingCustomerApproval: return "Your driver’s inspection is ready. Review it within 15 seconds, then tap Approve pickup — or we’ll auto-approve."
        case .pickedUp: return "Your EV is on the way to the nearest station."
        case .charging: return "Plugged in and charging toward your target."
        case .returning: return "Fully handled — heading back to you."
        case .awaitingPostTripInspection: return "Your concierge is completing the return inspection. You’ll see it when it’s ready."
        case .awaitingReturnApproval: return "Quick-look the return photos. Approve within 15 seconds, or we’ll auto-approve."
        case .delivered: return "Your car is back. Review the return inspection anytime."
        }
    }

    var next: JobStatus? {
        switch self {
        case .requested: return .driverEnRoute
        case .driverEnRoute: return .driverArrived
        case .driverArrived: return .awaitingCustomerApproval
        case .awaitingCustomerApproval: return .pickedUp
        case .pickedUp: return .charging
        case .charging: return .returning
        case .returning: return .awaitingPostTripInspection
        case .awaitingPostTripInspection: return .awaitingReturnApproval
        case .awaitingReturnApproval: return .delivered
        case .delivered: return nil
        }
    }

    var stepIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var pausesAutoProgression: Bool {
        switch self {
        case .driverArrived, .awaitingCustomerApproval, .awaitingPostTripInspection, .awaitingReturnApproval:
            return true
        default:
            return false
        }
    }

    /// Normalize cloud status when inspection JSON is present but status lags.
    static func resolvedFromCloud(
        status: JobStatus,
        hasPreTripInspection: Bool = false,
        customerApprovedPickupAt: Date? = nil,
        hasPostTripInspection: Bool,
        customerApprovedReturnAt: Date?
    ) -> JobStatus {
        if status == .awaitingCustomerApproval {
            return .awaitingCustomerApproval
        }
        if hasPreTripInspection,
           customerApprovedPickupAt == nil,
           status == .driverArrived {
            return .awaitingCustomerApproval
        }
        if status == .awaitingReturnApproval {
            return .awaitingReturnApproval
        }
        if hasPostTripInspection,
           customerApprovedReturnAt == nil,
           status == .awaitingPostTripInspection {
            return .awaitingReturnApproval
        }
        return status
    }
}
