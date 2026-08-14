//
//  ReferralGift.swift
//  Chercharge
//
//  Trip share copy helpers.
//

import Foundation

enum ReferralGift {
    static func tripShareMessage(job: ChargeJob, driverName: String) -> String {
        """
        Just completed a Chercharge concierge charge.
        \(job.vehicle.displayName) · \(job.startingChargePercent)% → \(job.targetChargePercent)%
        Valet \(driverName) · \(job.formattedPrice)
        Receipt \(job.displayReceiptNumber)

        Chercharge · Your EV. Our Care.
        """
    }
}
