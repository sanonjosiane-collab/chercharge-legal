//
//  PreOrderService.swift
//  Chercharge
//
//  Pay-now pre-order before launch. Requires Supabase Auth + Stripe PaymentSheet.
//  Quote can still preview locally when signed out; purchase never grants Founding
//  Access without a verified Stripe PaymentIntent.
//

import Foundation
import StripePaymentSheet
import Supabase
import UIKit

enum PreOrderServiceError: LocalizedError {
    case notConfigured
    case requiresSupabaseAuth
    case alreadyPreordered
    case cancelled
    case declined(String)
    case backend(String)
    case presentationFailed
    case slotsFilled
    case unverifiedPayment

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Founding Access checkout isn’t available right now. Please try again later or contact Chercharge Support."
        case .requiresSupabaseAuth:
            return "You’re signed in, but payment still needs a quick account unlock. Enter your password on the next step, or sign out and sign back in."
        case .alreadyPreordered:
            return "You already completed your pre-order."
        case .cancelled:
            return "Pre-order was cancelled."
        case .declined(let reason):
            return reason
        case .backend(let message):
            return message
        case .presentationFailed:
            return "Unable to present the payment sheet."
        case .slotsFilled:
            return "Early-bird spots are full. Pre-order is still available at the regular price."
        case .unverifiedPayment:
            return "Founding Access was not granted because payment could not be verified."
        }
    }
}

enum PreOrderService {
    private static let campaignID = "early_bird_50"
    /// Keep in sync with create-preorder-payment CURRENT_TERMS_VERSION.
    static let foundingTermsVersion = "founding-access-v1"
    private static let client = SupabaseClientProvider.shared

    static var isLivePreorderAvailable: Bool {
        PaymentService.isStripeConfigured && SupabaseConfig.isConfigured
    }

    /// Live Stripe founding checkout, or Review/DEBUG sandbox checkout.
    static var canCheckout: Bool {
        isLivePreorderAvailable || PaymentService.allowsLocalMockPayments
    }

    // MARK: - Quote

    @MainActor
    static func fetchQuote(
        auth: AuthService,
        localState: PreorderState
    ) async throws -> PreorderQuote {
        if canUseLiveAPI(auth: auth) {
            return try await fetchLiveQuote(auth: auth)
        }
        return localQuote(state: localState)
    }

    // MARK: - Checkout

    @MainActor
    static func purchase(
        auth: AuthService,
        localState: PreorderState,
        agreementAccepted: Bool,
        agreementAcceptedAt: Date = Date()
    ) async throws -> (result: PreorderPaymentResult, updatedState: PreorderState) {
        guard agreementAccepted else {
            throw PreOrderServiceError.backend(
                "You must accept the Founding Access agreement before paying."
            )
        }

        // Founding Access is never granted by local mock checkout — Stripe PaymentSheet only.
        guard isLivePreorderAvailable else {
            throw PreOrderServiceError.notConfigured
        }
        guard PaymentService.publishableKey != nil else {
            throw PreOrderServiceError.notConfigured
        }
        guard canUseLiveAPI(auth: auth) else {
            throw PreOrderServiceError.requiresSupabaseAuth
        }

        let quote = try await fetchLiveQuote(auth: auth)

        if quote.existingStatus == .completed {
            throw PreOrderServiceError.alreadyPreordered
        }
        // Ignore unverified local "completed" leftovers (e.g. pi_local_…).
        if localState.isCompleted,
           BookingStore.isVerifiedStripePaymentIntentID(localState.paymentIntentID) {
            throw PreOrderServiceError.alreadyPreordered
        }
        // pending reservations are resumable via create-preorder-payment.

        let result = try await purchaseLive(
            auth: auth,
            quote: quote,
            agreementAcceptedAt: agreementAcceptedAt
        )
        guard BookingStore.isVerifiedStripePaymentIntentID(result.paymentIntentID) else {
            throw PreOrderServiceError.unverifiedPayment
        }

        var updated = localState
        updated.status = .completed
        updated.paidAmount = result.amount
        updated.promoApplied = result.promoApplied
        updated.paymentIntentID = result.paymentIntentID
        updated.completedAt = Date()
        updated.accountCredit = 0
        updated.creditConsumed = true
        updated.lockedTier = quote.tier ?? Self.inferredLockedTier(paidAmount: result.amount)
        updated.localSlotsClaimed = 0
        return (result, updated)
    }

    // MARK: - Live (Supabase + Stripe)

    private static func canUseLiveAPI(auth: AuthService) -> Bool {
        auth.session != nil
    }

    @MainActor
    private static func fetchLiveQuote(auth: AuthService) async throws -> PreorderQuote {
        guard let token = auth.supabaseAccessToken else {
            throw PreOrderServiceError.requiresSupabaseAuth
        }

        let response: PreorderStatusResponse = try await invoke(
            name: "get-preorder-status",
            token: token
        )

        return PreorderQuote(
            price: centsToDecimal(response.priceCents),
            promoApplied: response.promoApplied,
            slotsRemaining: response.slotsRemaining,
            maxSlots: response.maxSlots,
            standardPrice: centsToDecimal(response.standardPriceCents),
            discount: centsToDecimal(response.discountCents),
            alreadyPreordered: response.alreadyPreordered,
            existingStatus: mapStatus(response.existingStatus),
            accountCredit: centsToDecimal(response.accountCreditCents),
            creditConsumed: response.preorderCreditConsumed,
            serverTier: mapTier(response.tier)
        )
    }

    @MainActor
    private static func purchaseLive(
        auth: AuthService,
        quote: PreorderQuote,
        agreementAcceptedAt: Date
    ) async throws -> PreorderPaymentResult {
        guard let token = auth.supabaseAccessToken,
              let publishableKey = PaymentService.publishableKey else {
            throw PreOrderServiceError.requiresSupabaseAuth
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let created: CreatePreorderResponse = try await invoke(
            name: "create-preorder-payment",
            token: token,
            body: [
                "agreement_accepted": true,
                "terms_version": foundingTermsVersion,
                "agreement_accepted_at": formatter.string(from: agreementAcceptedAt),
            ]
        )

        guard BookingStore.isVerifiedStripePaymentIntentID(created.paymentIntentId),
              created.clientSecret.hasPrefix("pi_"),
              created.clientSecret.contains("_secret_") else {
            throw PreOrderServiceError.backend(
                "Payment could not be verified. Please try again or contact Chercharge Support."
            )
        }

        STPAPIClient.shared.publishableKey = publishableKey

        let configuration = PaymentService.makePaymentSheetConfiguration()

        let sheet = PaymentSheet(
            paymentIntentClientSecret: created.clientSecret,
            configuration: configuration
        )

        // Avoid presenting over a dismissing SwiftUI agreement sheet.
        await TopViewController.waitUntilReadyForPaymentSheet()

        guard let presenter = TopViewController.find() else {
            throw PreOrderServiceError.presentationFailed
        }

        let result: PaymentSheetResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                sheet.present(from: presenter) { result in
                    continuation.resume(returning: result)
                }
            }
        }

        switch result {
        case .completed:
            let confirmed: ConfirmPreorderResponse = try await invoke(
                name: "confirm-preorder",
                token: token,
                body: ["payment_intent_id": created.paymentIntentId]
            )

            return PreorderPaymentResult(
                paymentIntentID: created.paymentIntentId,
                amount: centsToDecimal(created.priceCents),
                promoApplied: created.promoApplied,
                creditGranted: centsToDecimal(confirmed.creditCents)
            )
        case .canceled:
            throw PreOrderServiceError.cancelled
        case .failed(let error):
            throw PreOrderServiceError.declined(error.localizedDescription)
        @unknown default:
            throw PreOrderServiceError.declined("Payment failed.")
        }
    }

    // MARK: - Local quote preview (no purchase)

    /// Exposed for offline fallback when the live quote request fails.
    static func localPreviewQuote(state: PreorderState) -> PreorderQuote {
        localQuote(state: state)
    }

    private static func localQuote(state: PreorderState) -> PreorderQuote {
        let claimed = state.localSlotsClaimed
        let slotsRemaining = max(0, PreorderCampaign.maxSlots - claimed)
        let tier = PreorderCampaign.tier(claimedSlots: claimed)
        let promoAvailable = tier != nil && state.status != .completed
        let price = promoAvailable
            ? PreorderCampaign.price(claimedSlots: claimed)
            : PreorderCampaign.standardPrice

        return PreorderQuote(
            price: price,
            promoApplied: promoAvailable,
            slotsRemaining: slotsRemaining,
            maxSlots: PreorderCampaign.maxSlots,
            standardPrice: PreorderCampaign.standardPrice,
            discount: PreorderCampaign.discount(from: price),
            alreadyPreordered: state.status == .completed,
            existingStatus: state.status,
            accountCredit: state.accountCredit,
            creditConsumed: state.creditConsumed,
            serverTier: state.lockedTier ?? (state.isCompleted ? inferredLockedTier(paidAmount: state.paidAmount) : tier)
        )
    }

    // MARK: - Founding rate helpers

    /// Locked flat per-charge price for completed Founding Access (not a one-time credit).
    static func lockedChargePrice(for state: PreorderState) -> Decimal? {
        activeLockedTier(for: state)?.price
    }

    static func activeLockedTier(for state: PreorderState) -> PreorderTier? {
        guard state.isCompleted else { return nil }
        let paid = state.paidAmount > 0 ? state.paidAmount : state.accountCredit
        let tier = state.lockedTier ?? inferredLockedTier(paidAmount: paid)
        guard let tier else { return nil }

        if tier == .year, let completedAt = state.completedAt {
            if let expiry = Calendar.current.date(byAdding: .year, value: 1, to: completedAt),
               Date() >= expiry {
                return nil
            }
        }
        return tier
    }

    static func inferredLockedTier(paidAmount: Decimal) -> PreorderTier? {
        guard paidAmount > 0 else { return nil }
        if paidAmount <= PreorderCampaign.lifetimePrice { return .lifetime }
        if paidAmount <= PreorderCampaign.yearPrice { return .year }
        return nil
    }

    /// Amount charged for a booking — founding flat rate when locked, else standard quote.
    static func amountDue(for quotePrice: Decimal, state: PreorderState) -> Decimal {
        if let locked = lockedChargePrice(for: state) {
            return locked
        }
        return max(0, quotePrice)
    }

    /// Display-only savings vs the standard quote when a founding rate is active.
    static func foundingSavings(for quotePrice: Decimal, state: PreorderState) -> Decimal {
        guard let locked = lockedChargePrice(for: state) else { return 0 }
        return max(0, quotePrice - locked)
    }

    /// Legacy one-time credit path — unused for founding rates.
    static func creditToApply(for quotePrice: Decimal, state: PreorderState) -> Decimal {
        // Founding Access is a locked rate, not a credit subtraction.
        if lockedChargePrice(for: state) != nil { return 0 }
        guard state.hasCredit else { return 0 }
        return min(state.accountCredit, quotePrice)
    }

    // MARK: - Networking

    private static func invoke<T: Decodable>(
        name: String,
        token: String,
        body: [String: Any] = [:]
    ) async throws -> T {
        let supabaseURL = try SupabaseConfig.url
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(name)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try SupabaseConfig.applyClientAPIHeaders(to: &request, authorizationBearer: token)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PreOrderServiceError.backend("Invalid response from preorder server.")
        }

        if let decoded = try? JSONDecoder().decode(PreorderErrorResponse.self, from: data),
           let message = decoded.error,
           http.statusCode != 200 {
            throw PreOrderServiceError.backend(message)
        }

        guard http.statusCode == 200 else {
            throw PreOrderServiceError.backend("Preorder request failed (\(http.statusCode)).")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func centsToDecimal(_ cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    private static func mapStatus(_ raw: String?) -> PreorderStatus {
        switch raw {
        case "pending": return .pending
        case "completed": return .completed
        case "failed": return .failed
        case "cancelled": return .failed
        default: return .none
        }
    }

    private static func mapTier(_ raw: String?) -> PreorderTier? {
        switch raw {
        case "lifetime": return .lifetime
        case "year": return .year
        default: return nil
        }
    }
}

// MARK: - API models

private struct PreorderStatusResponse: Decodable {
    let priceCents: Int
    let promoApplied: Bool
    let slotsRemaining: Int
    let maxSlots: Int
    let standardPriceCents: Int
    let discountCents: Int
    let alreadyPreordered: Bool
    let existingStatus: String?
    let accountCreditCents: Int
    let preorderCreditConsumed: Bool
    let tier: String?
}

private struct CreatePreorderResponse: Decodable {
    let clientSecret: String
    let paymentIntentId: String
    let priceCents: Int
    let promoApplied: Bool
}

private struct ConfirmPreorderResponse: Decodable {
    let creditCents: Int
}

private struct PreorderErrorResponse: Decodable {
    let error: String?
}
