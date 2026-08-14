//
//  PreorderState.swift
//  Chercharge
//

import Foundation

/// Customer Founding Access state — reservation fee locks a flat per-charge rate
/// (not a deposit or credit toward future bookings).
struct PreorderState: Hashable, Codable {
    var status: PreorderStatus = .none
    var paidAmount: Decimal = 0
    var promoApplied: Bool = false
    var paymentIntentID: String?
    var completedAt: Date?
    /// Legacy field from older “credit on first charge” model — unused; founding is rate-lock only.
    var accountCredit: Decimal = 0
    var creditConsumed: Bool = false
    /// Locked founding rate after a successful Founding Access reservation-fee purchase.
    var lockedTier: PreorderTier? = nil

    /// Local mock slot counter when Supabase preorder APIs are unavailable.
    var localSlotsClaimed: Int = 0

    var hasCredit: Bool {
        accountCredit > 0 && !creditConsumed
    }

    var isCompleted: Bool {
        status == .completed
    }

    var formattedCredit: String {
        Pricing.format(accountCredit)
    }

    /// Active locked per-charge price when Founding Access applies.
    var lockedChargePrice: Decimal? {
        PreOrderService.lockedChargePrice(for: self)
    }

    var activeLockedTier: PreorderTier? {
        PreOrderService.activeLockedTier(for: self)
    }
}

enum PreorderStatus: String, Codable, Hashable {
    case none
    case pending
    case completed
    case failed
}

/// Early-bird rate locked in by pre-order slot.
enum PreorderTier: String, Codable, Hashable {
    /// First 5 — $10 / charge for life, one vehicle until it leaves service.
    case lifetime
    /// Next 45 — $39.99 / charge for one year, one vehicle.
    case year

    var title: String {
        switch self {
        case .lifetime: return "Lifetime rate"
        case .year: return "Early-bird year"
        }
    }

    var price: Decimal {
        switch self {
        case .lifetime: return PreorderCampaign.lifetimePrice
        case .year: return PreorderCampaign.yearPrice
        }
    }

    var benefitSummary: String {
        switch self {
        case .lifetime:
            return "Reservation fee locks $10/charge for life on 1 car; each booking is charged $10 separately"
        case .year:
            return "Reservation fee locks $39.99/charge for 1 year on 1 car; each booking is charged $39.99 separately"
        }
    }

    var shortRateLabel: String {
        switch self {
        case .lifetime: return "$10 founding rate"
        case .year: return "$39.99 founding rate"
        }
    }
}

struct PreorderQuote: Hashable {
    let price: Decimal
    let promoApplied: Bool
    let slotsRemaining: Int
    let maxSlots: Int
    let standardPrice: Decimal
    let discount: Decimal
    let alreadyPreordered: Bool
    let existingStatus: PreorderStatus
    let accountCredit: Decimal
    let creditConsumed: Bool
    /// Server-reported tier for the caller's reservation / completed founding purchase.
    let serverTier: PreorderTier?

    /// Offer tier for checkout, or the caller's locked founding tier when already completed.
    var tier: PreorderTier? {
        if alreadyPreordered || existingStatus == .completed {
            if let serverTier { return serverTier }
            if price <= PreorderCampaign.lifetimePrice { return .lifetime }
            if price <= PreorderCampaign.yearPrice { return .year }
            return nil
        }
        if let serverTier { return serverTier }
        return PreorderCampaign.tier(slotsRemaining: slotsRemaining, promoApplied: promoApplied)
    }

    var formattedPrice: String {
        Pricing.format(price)
    }

    var formattedStandardPrice: String {
        Pricing.format(standardPrice)
    }

    var slotsLabel: String {
        if slotsRemaining <= 0 {
            return "Early-bird pricing ended"
        }
        if let tier, tier == .lifetime {
            let left = min(slotsRemaining, PreorderCampaign.lifetimeSlots)
            return "\(left) of \(PreorderCampaign.lifetimeSlots) lifetime spots left"
        }
        if let tier, tier == .year {
            let yearLeft = min(slotsRemaining, PreorderCampaign.yearSlots)
            return "\(yearLeft) of \(PreorderCampaign.yearSlots) early-bird year spots left"
        }
        return "\(slotsRemaining) of \(maxSlots) early-bird spots left"
    }
}

struct PreorderPaymentResult: Hashable {
    let paymentIntentID: String
    let amount: Decimal
    let promoApplied: Bool
    let creditGranted: Decimal
}

enum PreorderCampaign {
    static let lifetimeSlots = 5
    static let yearSlots = 45
    static let maxSlots = lifetimeSlots + yearSlots

    /// First 5 early birds — $10 / charge for life (1 car).
    static let lifetimePrice: Decimal = Decimal(string: "10.00") ?? 10
    /// Next 45 early birds — $39.99 / charge for 1 year (1 car).
    static let yearPrice: Decimal = Decimal(string: "39.99") ?? 39.99
    static let standardPrice: Decimal = Pricing.perBookingFee

    static func tier(claimedSlots: Int) -> PreorderTier? {
        if claimedSlots < lifetimeSlots { return .lifetime }
        if claimedSlots < maxSlots { return .year }
        return nil
    }

    static func tier(slotsRemaining: Int, promoApplied: Bool) -> PreorderTier? {
        guard promoApplied, slotsRemaining > 0 else { return nil }
        // remaining > 45 means lifetime tier still open (claimed < 5)
        if slotsRemaining > yearSlots { return .lifetime }
        return .year
    }

    static func price(claimedSlots: Int) -> Decimal {
        switch tier(claimedSlots: claimedSlots) {
        case .lifetime: return lifetimePrice
        case .year: return yearPrice
        case nil: return standardPrice
        }
    }

    static func discount(from price: Decimal) -> Decimal {
        max(0, standardPrice - price)
    }
}
