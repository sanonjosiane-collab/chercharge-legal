//
//  ProfileDetailViews.swift
//  Chercharge
//

import SwiftUI

// MARK: - Personal information

struct PersonalInformationView: View {
    @Environment(BookingStore.self) private var store
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Identity",
                title: "Personal information",
                subtitle: "Your portrait and contact details for the concierge desk.",
                systemImage: "person.text.rectangle"
            )

            ConciergeCard {
                VStack(spacing: 14) {
                    ProfilePhotoAvatar(size: 108)
                    Text("Portrait")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)
                    Text("Take a photo or choose one from your library.")
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            ConciergeFieldCard(label: "Full name") {
                TextField("Full name", text: $name)
                    .textInputAutocapitalization(.words)
            }

            ConciergeFieldCard(label: "Email") {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            }

            ConciergeFieldCard(label: "Phone") {
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            ConciergePrimaryButton(title: "SAVE CHANGES") {
                store.updateProfile(name: name, email: email, phone: phone)
            }

            ConciergeInfoRibbon(text: "Updates are kept on-device and synced to the cloud when Firestore is enabled.")
        }
        .navigationTitle("Personal information")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = store.profileName
            email = store.profileEmail
            phone = store.profilePhone
        }
    }
}

// MARK: - Vehicles saved

struct VehiclesSavedView: View {
    @Environment(BookingStore.self) private var store
    @State private var showingAddVehicle = false
    @State private var vehiclePendingEdit: Vehicle?
    @State private var vehiclePendingDelete: Vehicle?

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Garage",
                title: "Vehicles saved",
                subtitle: "Up to \(Pricing.maxSavedVehicles) motorcars in your private collection.",
                systemImage: "car.fill"
            )

            if store.vehicles.isEmpty {
                ConciergeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ConciergeMedallion(systemImage: "car.fill", size: 52)
                        Text("The garage is empty")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(ConciergeLuxe.charcoal)
                        Text("Add a vehicle with make, model, year, license plate, plate state, insurance, and registration photo.")
                            .font(.system(.footnote))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(store.vehicles) { vehicle in
                        vehicleCard(vehicle)
                    }
                }
            }

            ConciergeGoldOutlineButton(
                title: store.canAddVehicle ? "Add a vehicle" : "Garage is full",
                systemImage: "plus.circle.fill"
            ) {
                showingAddVehicle = true
            }
            .disabled(!store.canAddVehicle)
            .opacity(store.canAddVehicle ? 1 : 0.45)

            ConciergeInfoRibbon(
                text: "\(store.vehicles.count) of \(Pricing.maxSavedVehicles) vehicles on file. Tap edit to update details, or delete to remove."
            )

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote))
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Vehicles saved")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddVehicle = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(ConciergeLuxe.gold)
                }
                .disabled(!store.canAddVehicle)
                .accessibilityLabel("Add vehicle")
            }
        }
        .sheet(isPresented: $showingAddVehicle) {
            NavigationStack {
                AddVehicleView()
            }
        }
        .sheet(item: $vehiclePendingEdit) { vehicle in
            NavigationStack {
                AddVehicleView(existing: vehicle)
            }
        }
        .confirmationDialog(
            "Remove this vehicle?",
            isPresented: Binding(
                get: { vehiclePendingDelete != nil },
                set: { if !$0 { vehiclePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete vehicle", role: .destructive) {
                if let vehiclePendingDelete {
                    store.removeVehicle(id: vehiclePendingDelete.id)
                }
                vehiclePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                vehiclePendingDelete = nil
            }
        } message: {
            if let vehiclePendingDelete {
                Text("\(vehiclePendingDelete.displayName) will be removed from your garage.")
            }
        }
    }

    private func vehicleCard(_ vehicle: Vehicle) -> some View {
        ConciergeCard {
            HStack(alignment: .top, spacing: 14) {
                ConciergeMedallion(systemImage: "bolt.car.fill")

                VStack(alignment: .leading, spacing: 6) {
                    Text(vehicle.isTeslaLinked ? "TESLA LINKED" : "VEHICLE")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text(vehicle.displayName)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.charcoal)

                    Text("\(vehicle.name) · \(vehicle.licensePlateDisplay)")
                        .font(.system(.subheadline))
                        .foregroundStyle(ConciergeLuxe.muted)

                    Text("\(vehicle.estimatedRangeMiles) mi left · \(vehicle.insuranceCompanyName.isEmpty ? "Insurance" : vehicle.insuranceCompanyName) \(vehicle.insurancePolicy)")
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)

                    HStack(spacing: 8) {
                        ConciergeBadge(text: "\(vehicle.currentChargePercent)%")
                        ConciergeBadge(text: vehicle.documentApprovalStatus.customerLabel)
                    }
                }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Button {
                        vehiclePendingEdit = vehicle
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ConciergeLuxe.goldDark)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(ConciergeLuxe.ivoryDeep)
                                    .overlay(Circle().stroke(ConciergeLuxe.gold.opacity(0.3), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(vehicle.displayName)")

                    Button {
                        vehiclePendingDelete = vehicle
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.75))
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(ConciergeLuxe.ivoryDeep)
                                    .overlay(Circle().stroke(Color.red.opacity(0.2), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(vehicle.displayName)")
                }
            }
        }
    }
}

// MARK: - Saved addresses

struct SavedAddressesView: View {
    @Environment(BookingStore.self) private var store
    @State private var showingAddAddress = false
    @State private var addressPendingEdit: LocationPin?
    @State private var addressPendingDelete: LocationPin?

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Estates",
                title: "Saved addresses",
                subtitle: "Private residences and clubs for valet pickup.",
                systemImage: "mappin.and.ellipse"
            )

            if store.savedAddresses.isEmpty {
                ConciergeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ConciergeMedallion(systemImage: "mappin.and.ellipse", size: 52)
                        Text("No estates on file")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(ConciergeLuxe.charcoal)
                        Text("Add a residence, office, or club — each becomes a pickup option when you book.")
                            .font(.system(.footnote))
                            .foregroundStyle(ConciergeLuxe.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(store.savedAddresses) { location in
                        addressCard(location)
                    }
                }
            }

            ConciergeGoldOutlineButton(title: "Add an address") {
                showingAddAddress = true
            }

            ConciergeInfoRibbon(text: "Tap edit to update an address, or delete to remove it.")

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote))
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Saved addresses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddAddress = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(ConciergeLuxe.gold)
                }
                .accessibilityLabel("Add address")
            }
        }
        .sheet(isPresented: $showingAddAddress) {
            NavigationStack {
                AddAddressView()
            }
        }
        .sheet(item: $addressPendingEdit) { location in
            NavigationStack {
                AddAddressView(existing: location)
            }
        }
        .confirmationDialog(
            "Remove this address?",
            isPresented: Binding(
                get: { addressPendingDelete != nil },
                set: { if !$0 { addressPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete address", role: .destructive) {
                if let addressPendingDelete {
                    store.removeAddress(id: addressPendingDelete.id)
                }
                addressPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                addressPendingDelete = nil
            }
        } message: {
            if let addressPendingDelete {
                Text("\(addressPendingDelete.name) will be removed from your saved pickup spots.")
            }
        }
    }

    private func addressCard(_ location: LocationPin) -> some View {
        ConciergeCard {
            HStack(alignment: .top, spacing: 14) {
                ConciergeMedallion(systemImage: "mappin.and.ellipse")

                VStack(alignment: .leading, spacing: 6) {
                    Text("PICKUP ESTATE")
                        .font(.system(.caption2).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.goldDark)
                        .tracking(1.2)

                    Text(location.name)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.charcoal)

                    Text(location.address)
                        .font(.system(.subheadline))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Button {
                        addressPendingEdit = location
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ConciergeLuxe.goldDark)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(ConciergeLuxe.ivoryDeep)
                                    .overlay(Circle().stroke(ConciergeLuxe.gold.opacity(0.3), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(location.name)")

                    Button {
                        addressPendingDelete = location
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.75))
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(ConciergeLuxe.ivoryDeep)
                                    .overlay(Circle().stroke(Color.red.opacity(0.2), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(location.name)")
                }
            }
        }
    }
}

// MARK: - Payment methods

struct PaymentMethodsView: View {
    @Environment(BookingStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var showingAdd = false
    @State private var brand: PaymentBrand = .visa
    @State private var last4 = ""
    @State private var expiryMonth = "12"
    @State private var expiryYear = "28"
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var canSaveWithStripe: Bool {
        PaymentService.isStripeConfigured && auth.supabaseAccessToken != nil
    }

    private var visibleMethods: [SavedPaymentMethod] {
        if PaymentService.allowsLocalMockPayments {
            return store.paymentMethods
        }
        return store.paymentMethods.filter { !$0.isLocalMock }
    }

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Treasury",
                title: "Payment methods",
                subtitle: paymentBannerSubtitle,
                systemImage: "creditcard.fill"
            )

            if visibleMethods.isEmpty {
                ConciergeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ConciergeMedallion(systemImage: "creditcard.fill", size: 52)
                        Text(emptyTitle)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(ConciergeLuxe.charcoal)
                        Text(paymentEmptyCopy)
                            .font(.system(.footnote))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(visibleMethods) { method in
                        paymentCard(method)
                    }
                }
            }

            if canSaveWithStripe {
                ConciergeGoldOutlineButton(
                    title: isBusy ? "Saving…" : "Save card",
                    systemImage: "plus.circle.fill"
                ) {
                    Task { await saveStripeCard() }
                }
                .disabled(isBusy)

                ConciergeInfoRibbon(
                    text: "Cards are saved securely with Stripe. You won’t be charged until you book or purchase."
                )
            } else if PaymentService.isStripeConfigured {
                ConciergeInfoRibbon(
                    text: "Sign in with your Chercharge email account to save a card for faster checkout."
                )
            } else if PaymentService.allowsLocalMockPayments {
                ConciergeGoldOutlineButton(
                    title: "Add payment method",
                    systemImage: "plus.circle.fill"
                ) {
                    showingAdd = true
                }

                ConciergeInfoRibbon(
                    text: "Save a card for local checkout rehearsal. Connect Stripe for live saved cards."
                )
            } else {
                ConciergeInfoRibbon(
                    text: "Pay securely at checkout when available. Contact Chercharge Support if you need help."
                )
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(.footnote).weight(.medium))
                    .foregroundStyle(ConciergeLuxe.emerald)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote).weight(.medium))
                    .foregroundStyle(Color.red.opacity(0.85))
            }
        }
        .navigationTitle("Payment methods")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStripeCardsIfNeeded()
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                Form {
                    Picker("Brand", selection: $brand) {
                        ForEach(PaymentBrand.allCases.filter { $0 != .other }) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    if brand != .applePay {
                        TextField("Last 4 digits", text: $last4)
                            .keyboardType(.numberPad)
                        TextField("Exp month (MM)", text: $expiryMonth)
                            .keyboardType(.numberPad)
                        TextField("Exp year (YY)", text: $expiryYear)
                            .keyboardType(.numberPad)
                    }
                }
                .navigationTitle("Add card")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let method = SavedPaymentMethod(
                                id: UUID(),
                                brand: brand,
                                last4: brand == .applePay ? "" : String(last4.suffix(4)),
                                expiryMonth: Int(expiryMonth),
                                expiryYear: 2000 + (Int(expiryYear) ?? 28),
                                isDefault: store.paymentMethods.isEmpty,
                                stripePaymentMethodID: "pm_local_\(UUID().uuidString.prefix(8))",
                                createdAt: Date()
                            )
                            store.addPaymentMethod(method)
                            showingAdd = false
                        }
                        .disabled(brand != .applePay && last4.count < 4)
                    }
                }
            }
        }
    }

    private var emptyTitle: String {
        if canSaveWithStripe { return "No cards on file" }
        if PaymentService.allowsLocalMockPayments { return "No cards on file" }
        return "Pay at checkout"
    }

    private var paymentBannerSubtitle: String {
        if canSaveWithStripe {
            return "Save a card securely with Stripe for quicker booking checkout."
        }
        if PaymentService.allowsLocalMockPayments {
            return PaymentService.isStripeConfigured
                ? "Stripe handles live cards. Local cards remain for offline rehearsal."
                : "Local cards for rehearsal. Connect Stripe when you are ready for live charges."
        }
        return PaymentService.isStripeConfigured
            ? "Sign in to save a card, or enter payment details securely when you check out."
            : "Payments are processed securely through Stripe when live checkout is available."
    }

    private var paymentEmptyCopy: String {
        if canSaveWithStripe {
            return "Tap Save card to securely add a Visa, Mastercard, or Amex. You won’t be charged now."
        }
        if PaymentService.allowsLocalMockPayments {
            return "Add a payment method for checkout, or pay with Stripe when you book."
        }
        return PaymentService.isStripeConfigured
            ? "Sign in with email to save a card here, or pay with Stripe when you place a request."
            : "Saved cards are not required here. Use Stripe checkout when you book."
    }

    private func paymentCard(_ method: SavedPaymentMethod) -> some View {
        ConciergeCard(selected: method.isDefault) {
            HStack(spacing: 14) {
                ConciergeMedallion(
                    systemImage: method.brand.systemImage,
                    selected: method.isDefault
                )

                Button {
                    store.setDefaultPaymentMethod(id: method.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(method.brand.title)
                            .font(.system(.body, design: .serif).weight(.semibold))
                            .foregroundStyle(method.isDefault ? ConciergeLuxe.card : ConciergeLuxe.charcoal)
                        Text(method.detailLabel)
                            .font(.system(.footnote))
                            .foregroundStyle(method.isDefault ? ConciergeLuxe.card.opacity(0.8) : ConciergeLuxe.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if method.isDefault {
                    ConciergeBadge(text: "Default")
                }

                Button {
                    Task { await removeMethod(method) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(method.isDefault ? ConciergeLuxe.goldSoft : ConciergeLuxe.muted)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
    }

    @MainActor
    private func refreshStripeCardsIfNeeded() async {
        guard canSaveWithStripe,
              let token = auth.supabaseAccessToken else { return }
        do {
            let remote = try await PaymentService.listSavedPaymentMethods(accessToken: token)
            store.replaceStripePaymentMethods(with: remote)
        } catch {
            // Keep local cache if refresh fails (offline / deploy lag).
        }
    }

    @MainActor
    private func saveStripeCard() async {
        guard let token = auth.supabaseAccessToken else {
            errorMessage = "Sign in with your Chercharge email account to save a card."
            return
        }
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }

        do {
            let remote = try await PaymentService.saveCard(accessToken: token)
            store.replaceStripePaymentMethods(with: remote)
            statusMessage = "Card saved securely."
        } catch let error as PaymentServiceError {
            if case .cancelled = error { return }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func removeMethod(_ method: SavedPaymentMethod) async {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }

        if !method.isLocalMock,
           let stripeID = method.stripePaymentMethodID,
           let token = auth.supabaseAccessToken,
           PaymentService.isStripeConfigured {
            do {
                try await PaymentService.detachPaymentMethod(id: stripeID, accessToken: token)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        store.removePaymentMethod(id: method.id)
        statusMessage = "Card removed."
    }
}

// MARK: - Membership

struct MembershipView: View {
    @Environment(BookingStore.self) private var store

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Concierge tariff",
                title: "Membership",
                subtitle: "Founding Access is a reservation fee that locks your promotional per-charge rate. It is not applied to future bookings—you pay the locked rate again each time you book.",
                systemImage: "rosette"
            )

            if !store.preorder.isCompleted {
                NavigationLink(value: ProfileRoute.preOrder) {
                    ConciergeCard {
                        HStack(spacing: 12) {
                            ConciergeMedallion(systemImage: "sparkles", size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Founding Access")
                                    .font(.system(.body, design: .serif).weight(.semibold))
                                    .foregroundStyle(ConciergeLuxe.charcoal)
                                if let quote = store.preorderQuote, quote.promoApplied {
                                    Text("\(quote.formattedPrice) · \(quote.slotsLabel)")
                                        .font(.system(.footnote))
                                        .foregroundStyle(ConciergeLuxe.emerald)
                                } else if let quote = store.preorderQuote {
                                    Text("\(quote.formattedPrice) · early-bird spots filled")
                                        .font(.system(.footnote))
                                        .foregroundStyle(ConciergeLuxe.muted)
                                } else {
                                    Text("Lock in $10 / charge (first 5) or $39.99 / charge (next 45)")
                                        .font(.system(.footnote))
                                        .foregroundStyle(ConciergeLuxe.muted)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(ConciergeLuxe.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if let tier = store.preorder.activeLockedTier {
                ConciergeInfoRibbon(
                    text: "Founding Access locked · \(Pricing.format(tier.price)) per charge on every booking. Your reservation fee does not count toward service."
                )
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PAY PER CHARGE")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text(
                        Pricing.format(
                            store.preorder.lockedChargePrice ?? Pricing.perBookingFee
                        )
                    )
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(ConciergeLuxe.emerald)

                    Text(
                        store.preorder.activeLockedTier != nil
                            ? "your locked founding rate · charged on every booking"
                            : "per charge · no subscription required"
                    )
                        .font(.system(.subheadline))
                        .foregroundStyle(ConciergeLuxe.muted)

                    ConciergeGoldFlourish()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    Text("Every booking is a single flat fee at your locked rate (or the standard rate without Founding Access). The Founding Access reservation fee only locks pricing—it is never deducted from a booking.")
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                }
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ConciergeMedallion(systemImage: "bell.badge.fill", size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Membership updates")
                                .font(.system(.body, design: .serif).weight(.semibold))
                                .foregroundStyle(ConciergeLuxe.charcoal)
                            Text("Get notified if Chercharge Plus or Elite Concierge opens.")
                                .font(.system(.footnote))
                                .foregroundStyle(ConciergeLuxe.muted)
                        }
                    }

                    Toggle("Notify me about membership plans", isOn: Binding(
                        get: { store.membership.notifyWhenPlusLaunches },
                        set: { store.setNotifyWhenPlusLaunches($0) }
                    ))
                    .tint(ConciergeLuxe.emerald)
                    .font(.system(.subheadline, design: .serif))
                }
            }

            ConciergeInfoRibbon(text: "White-glove charging at a flat rate. No subscription required.")
        }
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.membership.tier != .standard {
                store.setMembershipTier(.standard)
            }
        }
    }
}

// MARK: - Support

struct SupportView: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var showingCompose = false
    @State private var subject = "General question"
    @State private var bodyText = ""
    @State private var sentMessage: String?

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Concierge desk",
                title: "Support",
                subtitle: "Email Chercharge for account, booking, billing, and privacy help.",
                systemImage: "questionmark.circle.fill"
            )

            if let sentMessage {
                ConciergeCard(selected: true) {
                    Text(sentMessage)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(ConciergeLuxe.card)
                }
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CONTACT")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    labeled("Email", CherchargeLegalLinks.supportEmail)
                    labeled("Hours", "We reply as soon as reasonably possible")

                    Button {
                        openURL(CherchargeLegalLinks.supportMailURL)
                    } label: {
                        Text("Email \(CherchargeLegalLinks.supportEmail)")
                            .font(.system(.subheadline).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ConciergeLuxe.emerald)
                }
            }

            VStack(spacing: 12) {
                Button {
                    openURL(CherchargeLegalLinks.support)
                } label: {
                    ConciergeNavRow(
                        title: "Help center",
                        systemImage: "book.fill",
                        subtitle: "Guides & support topics"
                    )
                }
                .buttonStyle(.plain)

                supportButton(
                    "Email support",
                    "Message the desk",
                    "bubble.left.and.bubble.right.fill",
                    "Chat with support"
                )
                supportButton(
                    "Report an issue",
                    "Flag a concern",
                    "exclamationmark.bubble.fill",
                    "Report an issue"
                )
            }

            if !store.supportTickets.isEmpty {
                ConciergeGoldFlourish()
                    .frame(maxWidth: .infinity)

                Text("YOUR TICKETS")
                    .font(.system(.caption2).weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(ConciergeLuxe.goldDark)

                VStack(spacing: 12) {
                    ForEach(store.supportTickets) { ticket in
                        ConciergeCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(ticket.subject)
                                        .font(.system(.body, design: .serif).weight(.semibold))
                                        .foregroundStyle(ConciergeLuxe.charcoal)
                                    Spacer()
                                    ConciergeBadge(text: ticket.status)
                                }
                                Text(ticket.body)
                                    .font(.system(.footnote))
                                    .foregroundStyle(ConciergeLuxe.muted)
                                    .lineLimit(2)
                                Text(ticket.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(.caption2))
                                    .foregroundStyle(ConciergeLuxe.muted)
                            }
                        }
                    }
                }
            }

            ConciergeInfoRibbon(
                text: "Email \(CherchargeLegalLinks.supportEmail) for support. In-app tickets are also saved on your profile for follow-up."
            )
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCompose) {
            NavigationStack {
                Form {
                    TextField("Subject", text: $subject)
                    TextField("How can we help?", text: $bodyText, axis: .vertical)
                        .lineLimit(4...8)
                }
                .navigationTitle("New request")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCompose = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.submitSupportTicket(subject: subject, body: trimmed)
                            var components = URLComponents()
                            components.scheme = "mailto"
                            components.path = CherchargeLegalLinks.supportEmail
                            components.queryItems = [
                                URLQueryItem(name: "subject", value: "Chercharge: \(subject)"),
                                URLQueryItem(name: "body", value: trimmed),
                            ]
                            if let mail = components.url {
                                openURL(mail)
                            }
                            sentMessage =
                                "Request saved. Opening email to \(CherchargeLegalLinks.supportEmail)."
                            showingCompose = false
                        }
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func supportButton(_ title: String, _ subtitle: String, _ icon: String, _ composeSubject: String) -> some View {
        Button {
            subject = composeSubject
            bodyText = ""
            showingCompose = true
        } label: {
            ConciergeNavRow(title: title, systemImage: icon, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(.caption2).weight(.semibold))
                .foregroundStyle(ConciergeLuxe.muted)
                .tracking(0.8)
            Text(value)
                .font(.system(.body, design: .serif))
                .foregroundStyle(ConciergeLuxe.charcoal)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(BookingStore.self) private var store
    @Environment(AuthService.self) private var auth

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Preferences",
                title: "Settings",
                subtitle: "Notifications, account status, and quiet housekeeping.",
                systemImage: "gearshape.fill"
            )

            ConciergeCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("SERVICE NOTIFICATIONS")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text("Booking, pickup, charging, return, and important account updates. Optional — Chercharge still works if these are off.")
                        .font(.system(.caption))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    toggleRow("Service notifications", binding(\.pushNotificationsEnabled))
                    toggleRow("Inspection alerts", binding(\.inspectionAlertsEnabled))
                }
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("MARKETING (OPTIONAL)")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text("Offers & product updates are never required for booking or concierge service.")
                        .font(.system(.caption))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    toggleRow("Offers & updates", binding(\.marketingEnabled))
                }
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("PREFERENCES")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    toggleRow("Location access", binding(\.locationAccessEnabled))
                }
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ACCOUNT")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    metaRow("Signed in as", auth.displayEmail ?? store.profileEmail)
                    metaRow("Auth", auth.authBackendLabel)
                    metaRow("Cloud sync", store.cloudSyncLabel)
                    metaRow(
                        "Payments",
                        PaymentService.isStripeConfigured
                            ? "Stripe PaymentSheet"
                            : (PaymentService.allowsLocalMockPayments ? "On-device checkout" : "Contact support")
                    )

                    if let syncError = store.cloudSyncError {
                        Text(syncError)
                            .font(.system(.footnote))
                            .foregroundStyle(.orange)
                    }
                }
            }

            NavigationLink(value: ProfileRoute.legalPrivacy) {
                ConciergeNavRow(
                    title: "Legal & Privacy",
                    systemImage: "building.columns.fill",
                    subtitle: "Policies & agreements"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: ProfileRoute.privacyAccount) {
                ConciergeNavRow(
                    title: "Privacy & Account",
                    systemImage: "hand.raised.fill",
                    subtitle: "Delete account & privacy controls"
                )
            }
            .buttonStyle(.plain)

            ConciergeCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("APP")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    metaRow(
                        "Version",
                        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    )
                    metaRow("Vehicles saved", "\(store.vehicles.count)")
                    metaRow("Past bookings", "\(store.pastJobs.count)")
                }
            }

            Button {
                Task { await auth.signOut() }
            } label: {
                Text("Sign out")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)
                            .fill(ConciergeLuxe.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)
                                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            ConciergeInfoRibbon(text: "Chercharge keeps your suite composed — change preferences anytime.")
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .tint(ConciergeLuxe.emerald)
            .font(.system(.body, design: .serif))
            .foregroundStyle(ConciergeLuxe.charcoal)
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.subheadline))
                .foregroundStyle(ConciergeLuxe.muted)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundStyle(ConciergeLuxe.charcoal)
                .multilineTextAlignment(.trailing)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                var next = store.settings
                next[keyPath: keyPath] = newValue
                store.updateSettings(next)
            }
        )
    }
}

#Preview("Personal information") {
    NavigationStack {
        PersonalInformationView()
    }
    .environment(BookingStore())
}
