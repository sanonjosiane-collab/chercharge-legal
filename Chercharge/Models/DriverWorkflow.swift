//
//  DriverWorkflow.swift
//  Chercharge
//
//  Driver-facing step model for the in-app console (scaffolding for a
//  future separate driver app). Maps onto customer JobStatus.
//

import Foundation

enum DriverAction: String, CaseIterable, Identifiable {
    case acceptRequest
    case markEnRoute
    case markArrived
    case submitPreTripInspection
    case departForStation
    case startCharging
    case beginReturn
    case submitPostTripInspection
    case completeDelivery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .acceptRequest: return "Accept request"
        case .markEnRoute: return "En route to pickup"
        case .markArrived: return "Arrived at vehicle"
        case .submitPreTripInspection: return "Submit pre-trip inspection"
        case .departForStation: return "Depart for station"
        case .startCharging: return "Start charging"
        case .beginReturn: return "Begin return"
        case .submitPostTripInspection: return "Submit return inspection"
        case .completeDelivery: return "Mark delivered"
        }
    }

    var detail: String {
        switch self {
        case .acceptRequest: return "Claim this job and notify the customer."
        case .markEnRoute: return "Head to the pickup pin."
        case .markArrived: return "You’re with the vehicle — capture inspection next."
        case .submitPreTripInspection: return "Upload photos; customer reviews before pickup."
        case .departForStation: return "After customer approval, drive to the station."
        case .startCharging: return "Plug in and charge to target."
        case .beginReturn: return "Return the EV to the drop-off."
        case .submitPostTripInspection: return "Capture return photos for approval."
        case .completeDelivery: return "Hand off after customer return approval."
        }
    }
}

enum DriverWorkflow {
    /// Next driver action for the current customer-visible status, if any.
    static func nextAction(for status: JobStatus, hasPreTrip: Bool, hasPostTrip: Bool) -> DriverAction? {
        switch status {
        case .requested:
            return .acceptRequest
        case .driverEnRoute:
            return .markArrived
        case .driverArrived:
            return hasPreTrip ? nil : .submitPreTripInspection
        case .awaitingCustomerApproval:
            return nil // wait on customer
        case .pickedUp:
            return .startCharging
        case .charging:
            return .beginReturn
        case .returning:
            return .submitPostTripInspection
        case .awaitingPostTripInspection:
            return hasPostTrip ? nil : .submitPostTripInspection
        case .awaitingReturnApproval:
            return nil // wait on customer
        case .delivered:
            return nil
        }
    }

    static func waitingOnCustomer(for status: JobStatus) -> String? {
        switch status {
        case .awaitingCustomerApproval:
            return "Waiting for customer to approve pre-trip inspection."
        case .awaitingReturnApproval:
            return "Waiting for customer to approve return inspection."
        default:
            return nil
        }
    }
}
