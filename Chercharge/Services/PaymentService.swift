//
//  PaymentService.swift
//  Chercharge
//
//  Stripe PaymentSheet when a LIVE publishable key (pk_live_…) + Supabase are configured.
//  PaymentIntents are always created by the backend; the app only receives clientSecret.
//  Never put sk_… keys in the iOS app.
//

import Foundation
import StripePaymentSheet
import UIKit

struct PaymentChargeResult: Hashable {
    let paymentIntentID: String
    let amount: Decimal
    let methodLabel: String
    let receiptNumber: String
}

enum PaymentServiceError: LocalizedError {
    case noPaymentMethod
    case declined(String)
    case notConfigured
    case cancelled
    case backend(String)
    case presentationFailed
    case invalidClientKey

    var errorDescription: String? {
        switch self {
        case .noPaymentMethod:
            return "Add a payment method before booking."
        case .declined(let reason):
            return reason
        case .notConfigured:
            return "Secure checkout isn’t available right now. Please try again later or contact Chercharge Support."
        case .cancelled:
            return "Payment was cancelled."
        case .backend(let message):
            return message
        case .presentationFailed:
            return "Unable to present the payment sheet."
        case .invalidClientKey:
            return "Secure checkout isn’t configured correctly for this build. Please contact Chercharge Support."
        }
    }
}

enum PaymentService {
    /// Apple Pay Merchant ID registered in Apple Developer + Stripe.
    static let applePayMerchantID = "merchant.Chercharge.Chercharge"
    static let applePayMerchantCountryCode = "US"

    /// Shared PaymentSheet configuration (Apple Pay + Chercharge branding).
    static func makePaymentSheetConfiguration() -> PaymentSheet.Configuration {
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "Chercharge"
        configuration.allowsDelayedPaymentMethods = false
        configuration.applePay = .init(
            merchantId: applePayMerchantID,
            merchantCountryCode: applePayMerchantCountryCode
        )
        return configuration
    }

    /// True when a publishable key (live or test) and Supabase (for create-payment-intent) are real.
    static var isStripeConfigured: Bool {
        guard let key = rawPublishableKey,
              isValidPublishableKey(key) else { return false }
        return SupabaseConfig.isConfigured
    }

    /// Local mock payment UI and `chargeLocally` are DEBUG-only.
    /// When Stripe (live or test) is configured, PaymentSheet is preferred over mocks.
    static var allowsLocalMockPayments: Bool {
        #if DEBUG
        // Never mock-charge the App Review account — reviewers must see PaymentSheet.
        if AppleReviewDemoAccount.isSessionActive { return false }
        // Prefer real Stripe PaymentSheet when a publishable key is present.
        if isStripeConfigured { return false }
        return true
        #else
        return false
        #endif
    }

    static var publishableKey: String? {
        guard isStripeConfigured else { return nil }
        return rawPublishableKey
    }

    /// True when the configured publishable key is test mode (`pk_test_…`).
    static var isTestMode: Bool {
        (rawPublishableKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("pk_test_")
    }

    private static var rawPublishableKey: String? {
        SecretsReader.string(for: "STRIPE_PUBLISHABLE_KEY")
    }

    /// Client may hold `pk_live_…` or `pk_test_…`. Rejects secret keys and placeholders.
    static func isValidPublishableKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("YOUR_STRIPE"),
              !trimmed.hasPrefix("sk_") else { return false }
        return trimmed.hasPrefix("pk_live_") || trimmed.hasPrefix("pk_test_")
    }

    /// Legacy alias — same rules as `isValidPublishableKey`.
    static func isValidLivePublishableKey(_ key: String) -> Bool {
        isValidPublishableKey(key)
    }

    /// Charges the quoted net amount (already membership-discounted).
    /// Stripe path: backend PaymentIntent → PaymentSheet → real `pi_…`.
    /// Mock path (DEBUG only): requires a saved local payment method.
    @MainActor
    static func charge(
        amount: Decimal,
        method: SavedPaymentMethod? = nil,
        flow: String = "book_a_charge"
    ) async throws -> PaymentChargeResult {
        let net = max(0, amount) as Decimal

        if let raw = rawPublishableKey, raw.hasPrefix("sk_") {
            throw PaymentServiceError.invalidClientKey
        }

        // Always prefer live Stripe PaymentSheet when configured (including App Review).
        if isStripeConfigured {
            return try await chargeWithStripe(amount: net, flow: flow)
        }

        guard allowsLocalMockPayments else {
            throw PaymentServiceError.notConfigured
        }

        guard let method else {
            throw PaymentServiceError.noPaymentMethod
        }
        return try await chargeLocally(amount: net, method: method)
    }

    // MARK: - Stripe

    @MainActor
    private static func chargeWithStripe(amount: Decimal, flow: String) async throws -> PaymentChargeResult {
        guard let publishableKey else {
            throw PaymentServiceError.notConfigured
        }

        let amountCents = cents(from: amount)
        let intent = try await createPaymentIntent(amountCents: amountCents, flow: flow)

        STPAPIClient.shared.publishableKey = publishableKey

        let configuration = makePaymentSheetConfiguration()

        let sheet = PaymentSheet(
            paymentIntentClientSecret: intent.clientSecret,
            configuration: configuration
        )

        // Founding Access dismisses a SwiftUI sheet first — wait so PaymentSheet can present.
        await TopViewController.waitUntilReadyForPaymentSheet()

        guard let presenter = TopViewController.find() else {
            throw PaymentServiceError.presentationFailed
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
            return PaymentChargeResult(
                paymentIntentID: intent.paymentIntentId,
                amount: amount,
                methodLabel: "Apple Pay / Card · Stripe",
                receiptNumber: makeReceiptNumber()
            )
        case .canceled:
            throw PaymentServiceError.cancelled
        case .failed(let error):
            throw PaymentServiceError.declined(error.localizedDescription)
        @unknown default:
            throw PaymentServiceError.declined("Payment failed.")
        }
    }

    private static func createPaymentIntent(amountCents: Int, flow: String) async throws -> PaymentIntentResponse {
        let supabaseURL = try SupabaseConfig.url
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("create-payment-intent")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try SupabaseConfig.applyClientAPIHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "amount_cents": amountCents,
            "currency": "usd",
            "metadata": ["app": "chercharge", "flow": flow],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PaymentServiceError.backend("Invalid response from payment server.")
        }

        let decoded = try JSONDecoder().decode(PaymentIntentAPIResponse.self, from: data)
        guard http.statusCode == 200,
              let clientSecret = decoded.clientSecret,
              let paymentIntentId = decoded.paymentIntentId else {
            throw PaymentServiceError.backend(
                decoded.error ?? "Could not create payment (\(http.statusCode))."
            )
        }

        // Never treat a secret key as a client secret.
        guard clientSecret.hasPrefix("pi_"),
              clientSecret.contains("_secret_") else {
            throw PaymentServiceError.backend("Payment server returned an invalid client secret.")
        }

        return PaymentIntentResponse(
            clientSecret: clientSecret,
            paymentIntentId: paymentIntentId
        )
    }

    // MARK: - Save card (SetupIntent)

    /// Presents Stripe PaymentSheet to save a card (no charge), then returns the updated wallet.
    @MainActor
    static func saveCard(accessToken: String) async throws -> [SavedPaymentMethod] {
        guard isStripeConfigured, let publishableKey else {
            throw PaymentServiceError.notConfigured
        }

        let setup = try await createSetupIntent(accessToken: accessToken)
        guard setup.clientSecret.hasPrefix("seti_"),
              setup.clientSecret.contains("_secret_") else {
            throw PaymentServiceError.backend("Payment server returned an invalid setup secret.")
        }

        STPAPIClient.shared.publishableKey = publishableKey

        let configuration = makePaymentSheetConfiguration()
        let sheet = PaymentSheet(
            setupIntentClientSecret: setup.clientSecret,
            configuration: configuration
        )

        await TopViewController.waitUntilReadyForPaymentSheet()

        guard let presenter = TopViewController.find() else {
            throw PaymentServiceError.presentationFailed
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
            return try await listSavedPaymentMethods(accessToken: accessToken)
        case .canceled:
            throw PaymentServiceError.cancelled
        case .failed(let error):
            throw PaymentServiceError.declined(error.localizedDescription)
        @unknown default:
            throw PaymentServiceError.declined("Could not save that card.")
        }
    }

    static func listSavedPaymentMethods(accessToken: String) async throws -> [SavedPaymentMethod] {
        let response: ListPaymentMethodsAPIResponse = try await invokeAuthenticated(
            name: "list-payment-methods",
            accessToken: accessToken
        )
        if let error = response.error {
            throw PaymentServiceError.backend(error)
        }
        return (response.paymentMethods ?? []).compactMap { remote in
            guard let id = remote.id, id.hasPrefix("pm_"),
                  let last4 = remote.last4, !last4.isEmpty else { return nil }
            return SavedPaymentMethod(
                id: UUID(),
                brand: PaymentBrand.fromStripeBrand(remote.brand ?? "card"),
                last4: last4,
                expiryMonth: remote.expMonth,
                expiryYear: remote.expYear,
                isDefault: false,
                stripePaymentMethodID: id,
                createdAt: Date()
            )
        }
    }

    static func detachPaymentMethod(id: String, accessToken: String) async throws {
        guard id.hasPrefix("pm_") else {
            throw PaymentServiceError.backend("Invalid payment method.")
        }
        let response: DetachPaymentMethodAPIResponse = try await invokeAuthenticated(
            name: "detach-payment-method",
            accessToken: accessToken,
            body: ["payment_method_id": id]
        )
        if let error = response.error {
            throw PaymentServiceError.backend(error)
        }
        guard response.ok == true else {
            throw PaymentServiceError.backend("Could not remove that card.")
        }
    }

    private static func createSetupIntent(accessToken: String) async throws -> SetupIntentResponse {
        let response: SetupIntentAPIResponse = try await invokeAuthenticated(
            name: "create-setup-intent",
            accessToken: accessToken
        )
        guard let clientSecret = response.clientSecret,
              let setupIntentId = response.setupIntentId else {
            throw PaymentServiceError.backend(
                response.error ?? "Could not start card setup."
            )
        }
        return SetupIntentResponse(
            clientSecret: clientSecret,
            setupIntentId: setupIntentId,
            customerId: response.customerId
        )
    }

    private static func invokeAuthenticated<T: Decodable>(
        name: String,
        accessToken: String,
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
        try SupabaseConfig.applyClientAPIHeaders(to: &request, authorizationBearer: accessToken)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PaymentServiceError.backend("Invalid response from payment server.")
        }
        if http.statusCode >= 400 {
            if let envelope = try? JSONDecoder().decode(PaymentAPIErrorEnvelope.self, from: data),
               let message = envelope.error, !message.isEmpty {
                throw PaymentServiceError.backend(message)
            }
            throw PaymentServiceError.backend("Payment request failed (\(http.statusCode)).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PaymentServiceError.backend("Could not read payment server response.")
        }
    }

    // MARK: - Local mock

    private static func chargeLocally(
        amount: Decimal,
        method: SavedPaymentMethod
    ) async throws -> PaymentChargeResult {
        try await Task.sleep(for: .milliseconds(700))

        if method.brand != .applePay, method.last4 == "0000" {
            throw PaymentServiceError.declined("Card was declined. Try another payment method.")
        }

        let intentID =
            "pi_local_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"

        return PaymentChargeResult(
            paymentIntentID: intentID,
            amount: amount,
            methodLabel: "\(method.brand.title) \(method.detailLabel)",
            receiptNumber: makeReceiptNumber()
        )
    }

    // MARK: - Helpers

    private static func cents(from amount: Decimal) -> Int {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return NSDecimalNumber(decimal: rounded * 100).intValue
    }

    private static func makeReceiptNumber() -> String {
        "CH-\(Calendar.current.component(.year, from: Date()))-\(Int.random(in: 100000...999999))"
    }
}

// MARK: - API models

private struct PaymentIntentResponse {
    let clientSecret: String
    let paymentIntentId: String
}

private struct PaymentIntentAPIResponse: Decodable {
    let clientSecret: String?
    let paymentIntentId: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case clientSecret
        case paymentIntentId
        case error
    }
}

private struct SetupIntentResponse {
    let clientSecret: String
    let setupIntentId: String
    let customerId: String?
}

private struct SetupIntentAPIResponse: Decodable {
    let clientSecret: String?
    let setupIntentId: String?
    let customerId: String?
    let error: String?
}

private struct ListPaymentMethodsAPIResponse: Decodable {
    let paymentMethods: [RemoteSavedPaymentMethod]?
    let error: String?
}

private struct RemoteSavedPaymentMethod: Decodable {
    let id: String?
    let brand: String?
    let last4: String?
    let expMonth: Int?
    let expYear: Int?
}

private struct DetachPaymentMethodAPIResponse: Decodable {
    let ok: Bool?
    let error: String?
}

private struct PaymentAPIErrorEnvelope: Decodable {
    let error: String?
}

/// Finds the top-most view controller for presenting PaymentSheet.
enum TopViewController {
    @MainActor
    static func find() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return topMost(from: window?.rootViewController)
    }

    /// Waits for any SwiftUI/UIKit sheet to finish dismissing so Stripe PaymentSheet can present.
    @MainActor
    static func waitUntilReadyForPaymentSheet(timeoutSeconds: Double = 2.5) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            guard let presenter = find() else {
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            if presenter.presentedViewController == nil {
                // One extra beat for SwiftUI sheet teardown / hosting controller churn.
                try? await Task.sleep(nanoseconds: 200_000_000)
                if find()?.presentedViewController == nil { return }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    private static func topMost(from root: UIViewController?) -> UIViewController? {
        guard let root else { return nil }
        if let presented = root.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = root as? UINavigationController {
            return topMost(from: nav.visibleViewController ?? nav)
        }
        if let tab = root as? UITabBarController {
            return topMost(from: tab.selectedViewController ?? tab)
        }
        return root
    }
}

/// Lightweight Secrets.plist reader for optional third-party keys.
enum SecretsReader {
    static func string(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let value = dict[key] as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
