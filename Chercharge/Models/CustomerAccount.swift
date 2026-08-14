//
//  CustomerAccount.swift
//  Chercharge
//

import Foundation

// MARK: - Saved payment method

enum PaymentBrand: String, Codable, CaseIterable, Identifiable, Hashable {
    case visa
    case mastercard
    case amex
    case applePay
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "Amex"
        case .applePay: return "Apple Pay"
        case .other: return "Card"
        }
    }

    var systemImage: String {
        switch self {
        case .applePay: return "apple.logo"
        default: return "creditcard.fill"
        }
    }

    static func fromStripeBrand(_ brand: String) -> PaymentBrand {
        switch brand.lowercased() {
        case "visa": return .visa
        case "mastercard": return .mastercard
        case "amex", "american express": return .amex
        default: return .other
        }
    }
}

struct SavedPaymentMethod: Identifiable, Hashable, Codable {
    let id: UUID
    var brand: PaymentBrand
    /// Last 4 digits (empty for Apple Pay).
    var last4: String
    var expiryMonth: Int?
    var expiryYear: Int?
    var isDefault: Bool
    /// Stripe PaymentMethod id when linked (`pm_…`), or local mock id.
    var stripePaymentMethodID: String?
    var createdAt: Date

    /// True for DEBUG rehearsal cards (`pm_local_…`), not Stripe-linked methods.
    var isLocalMock: Bool {
        guard let stripePaymentMethodID else { return true }
        return stripePaymentMethodID.hasPrefix("pm_local")
    }

    var detailLabel: String {
        switch brand {
        case .applePay:
            return "iPhone · Apple Pay"
        default:
            let exp: String
            if let month = expiryMonth, let year = expiryYear {
                exp = String(format: "%02d/%02d", month, year % 100)
            } else {
                exp = "—"
            }
            return "•••• \(last4) · Exp \(exp)"
        }
    }
}

// MARK: - Membership

enum MembershipTier: String, Codable, CaseIterable, Identifiable, Hashable {
    case standard
    case plus
    case elite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .plus: return "Chercharge Plus"
        case .elite: return "Elite Concierge"
        }
    }

    var monthlyPrice: Decimal {
        switch self {
        case .standard: return 0
        case .plus: return Decimal(string: "29.99") ?? 29.99
        case .elite: return Decimal(string: "79.99") ?? 79.99
        }
    }

    var bookingDiscount: Decimal {
        switch self {
        case .standard: return 0
        case .plus: return Decimal(string: "5.00") ?? 5
        case .elite: return Decimal(string: "15.00") ?? 15
        }
    }

    var perks: [String] {
        switch self {
        case .standard:
            return ["Pay per booking", "Standard valet matching", "Inspection history"]
        case .plus:
            return ["$5 off every booking", "Faster valet matching", "Priority support"]
        case .elite:
            return ["$15 off every booking", "Dedicated elite concierge", "Same-day priority", "Complimentary inspection reports"]
        }
    }
}

struct MembershipState: Hashable, Codable {
    var tier: MembershipTier
    var renewsAt: Date?
    var notifyWhenPlusLaunches: Bool
    var stripeSubscriptionID: String?

    static let standard = MembershipState(
        tier: .standard,
        renewsAt: nil,
        notifyWhenPlusLaunches: false,
        stripeSubscriptionID: nil
    )
}

// MARK: - App settings

struct AppSettings: Hashable, Codable {
    var pushNotificationsEnabled: Bool
    var locationAccessEnabled: Bool
    var marketingEnabled: Bool
    var inspectionAlertsEnabled: Bool
    /// When true, Chercharge requires Face ID (or device biometrics) to open the app and for sensitive account actions.
    var faceIDEnabled: Bool

    static let `default` = AppSettings(
        pushNotificationsEnabled: false,
        locationAccessEnabled: true,
        marketingEnabled: false,
        inspectionAlertsEnabled: true,
        faceIDEnabled: false
    )

    enum CodingKeys: String, CodingKey {
        case pushNotificationsEnabled
        case locationAccessEnabled
        case marketingEnabled
        case inspectionAlertsEnabled
        case faceIDEnabled
    }

    init(
        pushNotificationsEnabled: Bool,
        locationAccessEnabled: Bool,
        marketingEnabled: Bool,
        inspectionAlertsEnabled: Bool,
        faceIDEnabled: Bool
    ) {
        self.pushNotificationsEnabled = pushNotificationsEnabled
        self.locationAccessEnabled = locationAccessEnabled
        self.marketingEnabled = marketingEnabled
        self.inspectionAlertsEnabled = inspectionAlertsEnabled
        self.faceIDEnabled = faceIDEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pushNotificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .pushNotificationsEnabled) ?? false
        locationAccessEnabled = try c.decodeIfPresent(Bool.self, forKey: .locationAccessEnabled) ?? true
        marketingEnabled = try c.decodeIfPresent(Bool.self, forKey: .marketingEnabled) ?? false
        inspectionAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .inspectionAlertsEnabled) ?? true
        faceIDEnabled = try c.decodeIfPresent(Bool.self, forKey: .faceIDEnabled) ?? false
    }
}

// MARK: - Support ticket

struct SupportTicket: Identifiable, Hashable, Codable {
    let id: UUID
    var subject: String
    var body: String
    var createdAt: Date
    var status: String
}
