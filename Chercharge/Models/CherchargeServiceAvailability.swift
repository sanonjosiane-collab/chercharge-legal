//
//  CherchargeServiceAvailability.swift
//  Chercharge
//
//  Gates live EV pickup / charging / return concierge.
//  Shipping builds keep concierge available so App Store Review and customers
//  get a complete product (Book, Reservations, Live Status).
//

import Foundation

enum CherchargeServiceAvailability {
    /// Live pickup, charging coordination, return, and Live Status tracking.
    static var isLiveConciergeAvailable: Bool {
        true
    }

    static let notAvailableTitle = "Temporarily unavailable"

    static let bookMessage =
        "Booking isn’t available right now. Please try again shortly, or contact Chercharge Support."

    static let liveStatusMessage =
        "Live trip tracking appears here while your concierge charge is in progress."

    static let conciergeCardTitle = "Concierge service"
    static let conciergeCardSubtitle = "Ready when you are"
    static let conciergeCardDetail =
        "Book a charge anytime. Add your vehicle and Founding Access for the best rate."
}
