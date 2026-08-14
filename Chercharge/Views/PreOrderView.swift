//
//  PreOrderView.swift
//  Chercharge
//

import SwiftUI

private enum PreorderLegalLinks {
    static let cancellationRefund = CherchargeLegalLinks.cancellationRefund
    static let termsOfService = CherchargeLegalLinks.termsOfService
    static let privacyPolicy = CherchargeLegalLinks.privacyPolicy
}

struct PreOrderView: View {
    @Environment(BookingStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var purchaseSuccess = false
    @State private var acceptedTier: PreorderTier?
    @State private var paymentPassword = ""
    @State private var isLinkingSupabase = false
    @State private var showPreLaunchSheet = false
    @State private var sheetAcknowledged = false
    @State private var pendingPayTier: PreorderTier?

    private var quote: PreorderQuote? {
        store.preorderQuote
    }

    private var isGuestAccount: Bool {
        (auth.displayEmail ?? auth.localEmail)?.hasSuffix("@chercharge.local") == true
    }

    /// Signed in with email but missing Supabase JWT — password unlocks live founding PaymentIntent APIs.
    /// App Review uses known credentials and links silently (no re-entry).
    private var needsPaymentPassword: Bool {
        guard !AppleReviewDemoAccount.isSessionActive else { return false }
        return PreOrderService.isLivePreorderAvailable
            && !auth.hasSupabaseSession
            && auth.isSignedIn
            && !isGuestAccount
    }

    private var canTapPay: Bool {
        !isPurchasing
            && !store.isLoading
            && !isLinkingSupabase
            && PreOrderService.canCheckout
            && auth.isSignedIn
            && !isGuestAccount
    }

    private var canConfirmSheet: Bool {
        sheetAcknowledged
            && !isLinkingSupabase
            && (!needsPaymentPassword || paymentPassword.count >= 6)
    }

    /// Live Stripe founding purchase, or Review/DEBUG sandbox completion.
    private var hasVerifiedCompletedPreorder: Bool {
        if quote?.existingStatus == .completed { return true }
        return store.hasCompletedFoundingAccess
    }

    private var canShowPayButton: Bool {
        guard PreOrderService.canCheckout else { return false }
        guard let quote else { return false }
        guard !hasVerifiedCompletedPreorder else { return false }
        guard quote.promoApplied, quote.tier != nil else { return false }
        if quote.existingStatus == .completed { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ConciergeRoyalBanner(
                    eyebrow: "Founding Access",
                    title: "Founding Access",
                    subtitle: "Pay a reservation fee now to lock your promotional per-charge rate. That fee does not pay for a future booking—each service is charged separately at your locked rate.",
                    systemImage: "sparkles"
                )

                if !PreOrderService.canCheckout {
                    ConciergeInfoRibbon(
                        text: "Founding Access checkout isn’t available in this session. Contact Chercharge Support if you need help completing a purchase."
                    )
                } else if !auth.isSignedIn || isGuestAccount {
                    ConciergeInfoRibbon(
                        text: "Sign in with your Chercharge email account (not guest mode) to pay and lock your Founding Access rate."
                    )
                }

                if let purchaseError {
                    Text(purchaseError)
                        .font(.system(.footnote).weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let storeError = store.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(storeError)
                            .font(.system(.footnote))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry connection") {
                            store.errorMessage = nil
                            Task { await store.refreshPreorderQuote(auth: auth) }
                        }
                        .font(.system(.footnote).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.emerald)
                    }
                }

                if let quote {
                    promotionsCard(quote)

                    if hasVerifiedCompletedPreorder {
                        completedCard
                    } else {
                        pricingCard(quote)
                        if canShowPayButton, let tier = quote.tier {
                            payCTA(tier: tier)
                        }
                        detailsCard(quote)
                    }
                } else {
                    ProgressView("Loading pre-order details…")
                        .tint(ConciergeLuxe.emerald)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .brandBackground()
        .navigationTitle("Founding Access")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.applyPendingPreorderResetIfNeededPublic()
            store.clearUnverifiedLocalPreorderIfNeeded()
            await store.refreshPreorderQuote(auth: auth)
        }
        .alert("Founding Access confirmed", isPresented: $purchaseSuccess) {
            Button("Done") { dismiss() }
        } message: {
            if let acceptedTier {
                Text("Your \(Pricing.format(acceptedTier.price)) reservation fee locked in \(Pricing.format(acceptedTier.price)) per charge. You’ll pay that rate again each time you book. \(acceptedTier.benefitSummary)")
            } else if let quote {
                Text("Your reservation fee locked in \(quote.formattedPrice) per charge for one vehicle. Each future booking is charged separately at that rate.")
            }
        }
        .sheet(isPresented: $showPreLaunchSheet) {
            preLaunchAgreementSheet
        }
        .disabled(isPurchasing)
        .overlay {
            if isPurchasing {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Opening payment…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    // MARK: - Pre-launch sheet (shown on Accept & pay)

    private var preLaunchAgreementSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("FOUNDING ACCESS PURCHASE NOTICE")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    noticeParagraph("Chercharge provides EV pickup, charging, and return concierge in eligible service areas. Founding Access is a reservation fee that locks the promotional per-charge rate described in this offer for one enrolled vehicle.")

                    noticeParagraph("The fee you pay today only reserves your promotional pricing and membership. It is not a deposit or credit toward a future booking. When you later schedule a Chercharge service, you pay the locked rate again for that service.")

                    noticeParagraph("Service is fulfilled in eligible geographic areas subject to driver availability. Purchase does not guarantee a specific appointment time outside normal booking.")

                    Text("Please review the following before completing your purchase:")
                        .font(.system(.footnote).weight(.medium))
                        .foregroundStyle(ConciergeLuxe.charcoal)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink(value: ProfileRoute.foundingAgreement) {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Founding Member Terms")
                                    .font(.system(.footnote).weight(.semibold))
                                    .underline()
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(ConciergeLuxe.emerald)
                        }
                        .buttonStyle(.plain)

                        policyLink("Cancellation and Refund Policy", url: PreorderLegalLinks.cancellationRefund)
                        policyLink("Terms of Service", url: PreorderLegalLinks.termsOfService)
                        policyLink("Privacy Policy", url: PreorderLegalLinks.privacyPolicy)
                    }

                    Button {
                        sheetAcknowledged.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: sheetAcknowledged ? "checkmark.square.fill" : "square")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(
                                    sheetAcknowledged
                                        ? ConciergeLuxe.emerald
                                        : ConciergeLuxe.gold.opacity(0.7)
                                )

                            Text("I understand this payment is a reservation fee that locks my Founding Access promotional rate. It is not a deposit or credit toward a future booking—I will pay the locked rate again each time I book. I have reviewed and agree to the Founding Member Terms, Terms of Service, Privacy Policy, and applicable Cancellation and Refund Policy.")
                                .font(.system(.footnote))
                                .foregroundStyle(ConciergeLuxe.charcoal)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)

                    if needsPaymentPassword {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm your password to unlock Stripe checkout for \(auth.displayEmail ?? "your account").")
                                .font(.system(.footnote))
                                .foregroundStyle(ConciergeLuxe.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            SecureField("Account password", text: $paymentPassword)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(ConciergeLuxe.ivoryDeep.opacity(0.9))
                                )
                        }
                        .padding(.top, 4)
                    }

                    if let purchaseError {
                        Text(purchaseError)
                            .font(.system(.footnote).weight(.semibold))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await confirmSheetAndPay() }
                    } label: {
                        HStack {
                            if isLinkingSupabase {
                                ProgressView().tint(.white)
                            }
                            Text(isLinkingSupabase ? "Continuing…" : "Agree & continue to payment")
                                .font(.system(.headline).weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ConciergeLuxe.emerald)
                    .disabled(!canConfirmSheet)
                    .opacity(canConfirmSheet ? 1 : 0.55)
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .brandBackground()
            .navigationTitle("Before you pay")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProfileRoute.self) { route in
                route.destination
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPreLaunchSheet = false
                        pendingPayTier = nil
                        sheetAcknowledged = false
                        paymentPassword = ""
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func noticeParagraph(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote))
            .foregroundStyle(ConciergeLuxe.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func policyLink(_ title: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(.footnote).weight(.semibold))
                    .underline()
                Spacer(minLength: 0)
            }
            .foregroundStyle(ConciergeLuxe.emerald)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards

    private func promotionsCard(_ quote: PreorderQuote) -> some View {
        ConciergeCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("EARLY-BIRD PROMOTIONS")
                    .font(.system(.caption2).weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(ConciergeLuxe.goldDark)

                Text("Only 5 lifetime spots at $10 and 45 year spots at $39.99. Standard rate is \(Pricing.format(PreorderCampaign.standardPrice)).")
                    .font(.system(.footnote))
                    .foregroundStyle(ConciergeLuxe.muted)
                    .fixedSize(horizontal: false, vertical: true)

                promoAcceptRow(
                    seal: "01",
                    tier: .lifetime,
                    title: "First 5 customers",
                    detail: "Pay $10 now to reserve lifetime $10/charge pricing. Each later booking is another $10—this fee is not a credit.",
                    quote: quote
                )

                Rectangle()
                    .fill(ConciergeLuxe.gold.opacity(0.2))
                    .frame(height: 0.5)

                promoAcceptRow(
                    seal: "02",
                    tier: .year,
                    title: "Next 45 customers",
                    detail: "Pay $39.99 now to reserve $39.99/charge for one year. Each later booking is another $39.99—this fee is not a credit.",
                    quote: quote
                )

                if quote.slotsRemaining <= 0, !quote.alreadyPreordered {
                    Text("All early-bird spots are filled. New bookings use the standard \(Pricing.format(PreorderCampaign.standardPrice)) rate.")
                        .font(.system(.footnote).weight(.medium))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func promoAcceptRow(
        seal: String,
        tier: PreorderTier,
        title: String,
        detail: String,
        quote: PreorderQuote
    ) -> some View {
        let isThisOffer = quote.tier == tier && quote.promoApplied
        let isSoldOut: Bool = {
            switch tier {
            case .lifetime:
                return quote.tier != .lifetime && quote.slotsRemaining <= PreorderCampaign.yearSlots
            case .year:
                return quote.slotsRemaining <= 0 || (quote.tier == nil && !quote.promoApplied)
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(seal)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.goldDark)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(ConciergeLuxe.ivory)
                            .overlay(Circle().stroke(ConciergeLuxe.gold.opacity(0.45), lineWidth: 1))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.charcoal)
                    (
                        Text(Pricing.format(tier.price))
                            .foregroundStyle(ConciergeLuxe.emerald)
                        + Text(" per charge")
                            .foregroundStyle(ConciergeLuxe.muted)
                    )
                    .font(.system(.subheadline).weight(.semibold))
                    Text(detail)
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if hasVerifiedCompletedPreorder {
                EmptyView()
            } else if isThisOffer {
                Text(quote.existingStatus == .pending
                      ? "Your current offer — finish payment below"
                      : "Your current offer — pay below")
                    .font(.system(.caption).weight(.semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 40)
            } else if isSoldOut {
                Text(tier == .lifetime ? "Lifetime spots filled" : "Early-bird year spots filled")
                    .font(.system(.caption).weight(.semibold))
                    .foregroundStyle(ConciergeLuxe.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 40)
            } else if tier == .year {
                Text("Available after lifetime spots fill")
                    .font(.system(.caption).weight(.semibold))
                    .foregroundStyle(ConciergeLuxe.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 40)
            }
        }
    }

    private func payCTA(tier: PreorderTier) -> some View {
        ConciergeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(quote?.existingStatus == .pending ? "FINISH PAYMENT" : "RESERVE THIS RATE")
                    .font(.system(.caption2).weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(ConciergeLuxe.goldDark)

                Button {
                    beginAcceptAndPay(tier)
                } label: {
                    HStack {
                        Image(systemName: "creditcard.fill")
                        Text("Accept & Pay \(Pricing.format(tier.price))")
                            .font(.system(.subheadline, design: .serif).weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canTapPay)
                .opacity(canTapPay ? 1 : 0.55)

                Text(
                    PaymentService.isStripeConfigured
                        ? "You’ll confirm the reservation-fee notice, then pay securely with Stripe. This payment locks your rate—it is not applied to a future booking."
                        : "You’ll confirm the reservation-fee notice, then complete checkout. This payment locks your rate—it is not applied to a future booking."
                )
                    .font(.system(.caption).weight(.medium))
                    .foregroundStyle(ConciergeLuxe.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pricingCard(_ quote: PreorderQuote) -> some View {
        ConciergeCard {
            VStack(alignment: .leading, spacing: 12) {
                if let tier = quote.tier {
                    Text(tier == .lifetime ? "YOUR OFFER · LIFETIME" : "YOUR OFFER · EARLY-BIRD YEAR")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)
                } else if quote.promoApplied {
                    Text("EARLY BIRD")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)
                } else {
                    Text("STANDARD RATE")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.muted)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(quote.formattedPrice)
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(ConciergeLuxe.emerald)

                    Text("per charge")
                        .font(.system(.subheadline))
                        .foregroundStyle(ConciergeLuxe.muted)

                    if quote.promoApplied {
                        Text(quote.formattedStandardPrice)
                            .font(.system(.subheadline))
                            .strikethrough()
                            .foregroundStyle(ConciergeLuxe.muted)
                    }
                }

                Text(quote.slotsLabel)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(quote.slotsRemaining > 0 ? ConciergeLuxe.emerald : ConciergeLuxe.muted)

                if let tier = quote.tier {
                    Text(tier.benefitSummary)
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailsCard(_ quote: PreorderQuote) -> some View {
        ConciergeCard {
            VStack(alignment: .leading, spacing: 14) {
                detailRow("Standard charge", quote.formattedStandardPrice)
                detailRow("Your locked rate", quote.formattedPrice)
                if quote.promoApplied {
                    detailRow("You save per charge", Pricing.format(quote.discount))
                }
                if let tier = quote.tier {
                    detailRow(
                        "Coverage",
                        tier == .lifetime
                            ? "Lifetime · 1 car"
                            : "1 year · 1 car"
                    )
                } else {
                    detailRow("Coverage", "Standard · per booking")
                }
                detailRow(
                    "Payment",
                    PaymentService.isStripeConfigured
                        ? "Stripe secure checkout"
                        : (PaymentService.allowsLocalMockPayments
                            ? "On-device checkout"
                            : "Contact support to complete checkout")
                )
            }
        }
    }

    private var completedCard: some View {
        ConciergeCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Founding Access complete", systemImage: "checkmark.seal.fill")
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)

                if let tier = store.preorder.activeLockedTier {
                    Text("Your \(Pricing.format(tier.price)) reservation fee locked \(Pricing.format(tier.price)) per charge for one vehicle. Each booking is charged separately at that rate—your reservation fee is not deducted from future services.")
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your early-bird rate is locked for one vehicle. Each booking is charged separately at your locked rate—the reservation fee is not deducted from future services.")
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline))
                .foregroundStyle(ConciergeLuxe.muted)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundStyle(ConciergeLuxe.charcoal)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    private func beginAcceptAndPay(_ tier: PreorderTier) {
        purchaseError = nil
        store.errorMessage = nil

        guard PreOrderService.canCheckout else {
            purchaseError = PreOrderServiceError.notConfigured.localizedDescription
            return
        }
        guard auth.isSignedIn, !isGuestAccount else {
            purchaseError = "Sign in with your Chercharge email account (not guest mode) to pay."
            return
        }

        pendingPayTier = tier
        sheetAcknowledged = false
        paymentPassword = ""
        showPreLaunchSheet = true
    }

    private func confirmSheetAndPay() async {
        guard sheetAcknowledged, let tier = pendingPayTier else { return }

        purchaseError = nil
        isLinkingSupabase = true
        defer { isLinkingSupabase = false }

        let ready = await ensurePaymentsSessionReady()
        guard ready else { return }

        showPreLaunchSheet = false
        pendingPayTier = nil

        // Wait for the agreement sheet to fully dismiss before Stripe PaymentSheet.
        await TopViewController.waitUntilReadyForPaymentSheet()
        await runCheckout(tier: tier, agreementAccepted: true)
    }

    /// Ensures a Supabase JWT when live Founding APIs are available; App Review can fall back to Stripe-only.
    @MainActor
    private func ensurePaymentsSessionReady() async -> Bool {
        if auth.hasSupabaseSession {
            return true
        }

        if AppleReviewDemoAccount.isSessionActive {
            _ = await auth.linkSupabaseForPayments(password: AppleReviewDemoAccount.password)
            await store.refreshPreorderQuote(auth: auth)
            if auth.hasSupabaseSession { return true }
            // Review account can still open PaymentSheet via create-payment-intent.
            if PaymentService.isStripeConfigured { return true }
            purchaseError = "Secure checkout isn’t available right now. Please try again or contact Chercharge Support."
            return false
        }

        if needsPaymentPassword {
            guard paymentPassword.count >= 6 else {
                purchaseError = "Enter your account password to continue."
                return false
            }
            let ok = await auth.linkSupabaseForPayments(password: paymentPassword)
            guard ok else {
                purchaseError = auth.errorMessage
                    ?? "Could not unlock payment. Check your password and try again."
                return false
            }
            paymentPassword = ""
            await store.refreshPreorderQuote(auth: auth)
            return auth.hasSupabaseSession
        }

        return PaymentService.allowsLocalMockPayments || PaymentService.isStripeConfigured
    }

    private func runCheckout(tier: PreorderTier, agreementAccepted: Bool) async {
        let canPayLive = auth.hasSupabaseSession && PreOrderService.isLivePreorderAvailable
        let canPaySandbox = PaymentService.isStripeConfigured || PaymentService.allowsLocalMockPayments
        guard canPayLive || canPaySandbox else {
            purchaseError = auth.isSignedIn
                ? "Secure checkout couldn’t start even though you’re signed in. Sign out, sign back in, then tap Accept & Pay again."
                : "Sign in with your Chercharge email account to continue to payment."
            return
        }

        store.clearUnverifiedLocalPreorderIfNeeded()

        if store.hasCompletedFoundingAccess {
            purchaseError = "This account already completed Founding Access."
            return
        }
        if let live = store.preorderQuote, live.existingStatus == .completed {
            purchaseError = "This account already completed Founding Access."
            return
        }

        isPurchasing = true
        purchaseError = nil
        store.errorMessage = nil
        acceptedTier = tier
        defer { isPurchasing = false }

        do {
            _ = try await store.purchasePreorder(
                auth: auth,
                agreementAccepted: agreementAccepted
            )
            purchaseSuccess = true
        } catch let error as PaymentServiceError {
            if case .cancelled = error { return }
            purchaseError = error.localizedDescription
        } catch let error as PreOrderServiceError {
            if case .cancelled = error { return }
            purchaseError = error.localizedDescription
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        PreOrderView()
    }
    .environment(BookingStore())
    .environment(AuthService())
}
