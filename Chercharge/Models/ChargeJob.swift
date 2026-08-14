//
//  ChargeJob.swift
//  Chercharge
//

import Foundation

struct ChargeQuote: Hashable {
    let estimatedMinutes: Int
    let price: Decimal
    let chargeDelta: Int

    var formattedPrice: String {
        Pricing.format(price)
    }
}

struct ChargeJob: Identifiable, Hashable, Codable {
    let id: UUID
    let vehicle: Vehicle
    let pickup: LocationPin
    let station: LocationPin
    /// Where the car is returned after charging. Falls back to pickup when nil (legacy jobs).
    var dropoff: LocationPin? = nil
    let targetChargePercent: Int
    let startingChargePercent: Int
    var status: JobStatus
    let estimatedPrice: Decimal
    let estimatedMinutes: Int
    let createdAt: Date
    var preTripInspection: VehicleInspection? = nil
    var postTripInspection: VehicleInspection? = nil
    var customerApprovedPickupAt: Date? = nil
    var customerApprovedReturnAt: Date? = nil
    /// When set, pickup auto-approves at this time if the customer has not acted.
    var inspectionApprovalDeadline: Date? = nil
    /// When set, return inspection auto-approves at this time if the customer has not acted.
    var returnApprovalDeadline: Date? = nil
    var issueReports: [InspectionIssueReport] = []
    /// Stripe PaymentIntent id when charged (or local mock id).
    var paymentIntentID: String? = nil
    var paymentMethodLabel: String? = nil
    var receiptNumber: String? = nil
    var completedAt: Date? = nil
    var scheduledFor: Date? = nil
    /// Optional tip after delivery (USD).
    var tipAmount: Decimal? = nil
    /// 1…5 stars for the valet; nil until submitted.
    var driverRating: Int? = nil
    var feedbackSubmittedAt: Date? = nil
    /// True when this job was inserted into Supabase `bookings` for the driver pool.
    /// Cloud jobs wait for driver status updates instead of local simulated progression.
    var isCloudDispatched: Bool = false

    /// Customer has 15 seconds to review pre-trip before pickup auto-approves.
    static let customerApprovalWindow: TimeInterval = 15
    /// Customer has 15 seconds to review post-trip before return auto-approves.
    static let returnApprovalWindow: TimeInterval = 15

    /// Shared label for UI / notifications.
    static let approvalWindowSecondsLabel = "15 seconds"

    /// Resolved return location (dropoff, or pickup when returning to the same place).
    var returnLocation: LocationPin {
        dropoff ?? pickup
    }

    var returnsToPickup: Bool {
        guard let dropoff else { return true }
        return dropoff.id == pickup.id
    }

    var isActive: Bool {
        status != .delivered
    }

    var formattedPrice: String {
        Pricing.format(estimatedPrice)
    }

    var chargeDelta: Int {
        max(0, targetChargePercent - startingChargePercent)
    }

    var needsPreTripInspection: Bool {
        status == .driverArrived && preTripInspection == nil
    }

    var needsCustomerApproval: Bool {
        status == .awaitingCustomerApproval && preTripInspection != nil && customerApprovedPickupAt == nil
    }

    var needsReturnApproval: Bool {
        status == .awaitingReturnApproval && postTripInspection != nil && customerApprovedReturnAt == nil
    }

    var needsAnyInspectionApproval: Bool {
        needsCustomerApproval || needsReturnApproval
    }

    var approvalSecondsRemaining: Int {
        if needsCustomerApproval, let deadline = inspectionApprovalDeadline {
            return max(0, Int(deadline.timeIntervalSinceNow.rounded(.down)))
        }
        if needsReturnApproval, let deadline = returnApprovalDeadline {
            return max(0, Int(deadline.timeIntervalSinceNow.rounded(.down)))
        }
        return 0
    }

    var approvalCountdownLabel: String {
        let total = approvalSecondsRemaining
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var needsPostTripInspection: Bool {
        status == .awaitingPostTripInspection && postTripInspection == nil
    }

    var canCompareInspections: Bool {
        preTripInspection != nil && postTripInspection != nil
    }

    var inspectionComparison: InspectionComparison? {
        guard let pickup = preTripInspection, let returned = postTripInspection else { return nil }
        return InspectionComparison(pickup: pickup, returnInspection: returned)
    }

    var displayReceiptNumber: String {
        receiptNumber ?? "CH-\(id.uuidString.prefix(8).uppercased())"
    }

    var hasSubmittedFeedback: Bool {
        feedbackSubmittedAt != nil
    }

    var formattedTip: String? {
        guard let tipAmount, tipAmount > 0 else { return nil }
        return Pricing.format(tipAmount)
    }

    var totalWithTip: Decimal {
        estimatedPrice + (tipAmount ?? 0)
    }

    var formattedTotalWithTip: String {
        Pricing.format(totalWithTip)
    }
}

enum Pricing {
    static let baseFee: Decimal = 18
    static let perPercentFee: Decimal = 0.45
    static let minutesPerPercent: Double = 1.2
    static let pickupBufferMinutes = 25
    /// Flat per-booking price (membership discounts apply when a paid tier is active).
    static let perBookingFee: Decimal = Decimal(string: "49.99") ?? 49.99
    /// Valet pickup requires enough range to reach a nearby station.
    static let minimumRangeMiles = 10
    /// Customers can save up to this many vehicles.
    static let maxSavedVehicles = 5

    static func quote(from current: Int, to target: Int, membership: MembershipState = .standard) -> ChargeQuote {
        let delta = max(0, target - current)
        let minutes = pickupBufferMinutes + Int((Double(delta) * minutesPerPercent).rounded())
        let discounted = max(Decimal(0), perBookingFee - membership.tier.bookingDiscount)
        return ChargeQuote(estimatedMinutes: minutes, price: discounted, chargeDelta: delta)
    }

    /// Rough local estimate when range isn't provided (manual add).
    static func estimatedMiles(fromChargePercent percent: Int) -> Int {
        max(0, Int((Double(percent) * 2.5).rounded()))
    }

    static func format(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
