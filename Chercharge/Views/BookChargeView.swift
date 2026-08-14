//
//  BookChargeView.swift
//  Chercharge
//

import SwiftUI

struct BookChargeView: View {
    @Environment(BookingStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Binding var path: NavigationPath
    /// Leaves Book a Charge and opens Profile (wired from ContentView).
    var onOpenProfile: (() -> Void)? = nil

    @State private var step: BookChargeStep = .schedule
    @State private var selectedVehicleID: UUID?
    @State private var selectedPickupID: UUID?
    @State private var selectedDropoffID: UUID?
    @State private var targetPercent: Double = 80
    @State private var rangeConfirmed = false
    @State private var scheduledAt = Date().addingTimeInterval(60 * 60)
    @State private var selectedPaymentID: UUID?
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showAddAddress = false
    @State private var showAddVehicle = false

    private var selectedVehicle: Vehicle? {
        store.vehicles.first { $0.id == selectedVehicleID }
    }

    private var selectedPickup: LocationPin? {
        store.pickupLocations.first { $0.id == selectedPickupID }
    }

    private var selectedDropoff: LocationPin? {
        store.pickupLocations.first { $0.id == selectedDropoffID }
    }

    private var quote: ChargeQuote? {
        guard let vehicle = selectedVehicle else { return nil }
        return store.quote(for: vehicle, targetChargePercent: Int(targetPercent))
    }

    private var pricingBreakdown: (
        amountDue: Decimal,
        savings: Decimal,
        foundingTier: PreorderTier?
    )? {
        guard let vehicle = selectedVehicle else { return nil }
        let breakdown = store.quoteDueToday(for: vehicle, targetChargePercent: Int(targetPercent))
        return (breakdown.amountDue, breakdown.creditApplied, breakdown.foundingTier)
    }

    private var earliestSchedule: Date {
        Self.nextHalfHour(after: Date().addingTimeInterval(30 * 60))
    }

    private var scheduleDay: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: scheduledAt) },
            set: { newDay in
                let time = Calendar.current.dateComponents([.hour, .minute], from: scheduledAt)
                var parts = Calendar.current.dateComponents([.year, .month, .day], from: newDay)
                parts.hour = time.hour
                parts.minute = time.minute
                if let combined = Calendar.current.date(from: parts) {
                    scheduledAt = Self.snapToHalfHour(combined)
                    if scheduledAt < earliestSchedule {
                        scheduledAt = earliestSchedule
                    }
                }
            }
        )
    }

    private var timeSlotsForSelectedDay: [Date] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: scheduledAt)
        var slots: [Date] = []
        // 7:00 AM – 10:00 PM in 30-minute steps
        for minuteOfDay in stride(from: 7 * 60, through: 22 * 60, by: 30) {
            guard let slot = cal.date(byAdding: .minute, value: minuteOfDay, to: dayStart) else { continue }
            if slot >= earliestSchedule {
                slots.append(slot)
            }
        }
        return slots
    }

    /// Next 12 bookable calendar days for the horizontal date scroller.
    private var scheduleDays: [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: earliestSchedule)
        return (0..<12).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var selectedTimeSlot: Binding<Date> {
        Binding(
            get: {
                timeSlotsForSelectedDay.first {
                    Calendar.current.isDate($0, equalTo: scheduledAt, toGranularity: .minute)
                } ?? timeSlotsForSelectedDay.first ?? scheduledAt
            },
            set: { scheduledAt = $0 }
        )
    }

    private var canContinue: Bool {
        switch step {
        case .schedule:
            return scheduledAt >= earliestSchedule
        case .vehicle:
            guard let selectedVehicle else { return false }
            return store.canBook(selectedVehicle) && rangeConfirmed
        case .pickup:
            return selectedPickup != nil
        case .dropoff:
            return selectedDropoff != nil
        case .payment:
            if (pricingBreakdown?.amountDue ?? quote?.price ?? 1) == 0 { return true }
            if PaymentService.isStripeConfigured { return true }
            guard PaymentService.allowsLocalMockPayments else { return false }
            return selectedPaymentID != nil
        case .review:
            guard let selectedVehicle else { return false }
            let amountDue = pricingBreakdown?.amountDue ?? quote?.price ?? 0
            let paymentOK = amountDue == 0
                || PaymentService.isStripeConfigured
                || (PaymentService.allowsLocalMockPayments && selectedPaymentID != nil)
            return store.canBook(selectedVehicle)
                && rangeConfirmed
                && scheduledAt >= earliestSchedule
                && selectedPickup != nil
                && selectedDropoff != nil
                && paymentOK
                && !isSubmitting
        }
    }

    private var selectedPaymentMethod: SavedPaymentMethod? {
        guard PaymentService.allowsLocalMockPayments else { return nil }
        return store.paymentMethods.first { $0.id == selectedPaymentID }
    }

    private var paymentStepSubtitle: String {
        if PaymentService.isStripeConfigured {
            return "You’ll enter card details securely with Stripe when you place the request."
        }
        if PaymentService.allowsLocalMockPayments {
            return store.membership.tier == .standard
                ? "Today’s price is \(Pricing.format(Pricing.perBookingFee)) per booking."
                : "\(store.membership.tier.title) saves \(Pricing.format(store.membership.tier.bookingDiscount)) on this booking."
        }
        return "Secure Stripe checkout is required for paid bookings."
    }

    var body: some View {
        ZStack {
            BookChargeBackground()
            BookChargeAmbientSparkles()

            VStack(spacing: 0) {
                BookChargeHeader(
                    onBack: { goBack() },
                    onOpenProfile: onOpenProfile
                )

                BookChargeProgress(
                    step: step.rawValue,
                    total: BookChargeStep.allCases.count,
                    label: step.title
                )
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, (step == .vehicle || step == .schedule) ? 12 : 22)

                if step == .vehicle || step == .schedule {
                    Group {
                        if step == .vehicle {
                            vehicleStep
                        } else {
                            scheduleStep
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        stepContent
                            .padding(.horizontal, 24)
                            .padding(.bottom, 28)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: step)
                    }
                }

                BookChargeBottomBar {
                    HStack(spacing: 12) {
                        if step != .schedule {
                            BookChargeSecondaryButton(title: "Back") {
                                goBack()
                            }
                            .frame(maxWidth: 120)
                        }

                        BookChargeContinueButton(
                            title: step == .review ? "PLACE REQUEST" : "CONTINUE",
                            isEnabled: canContinue,
                            isLoading: isSubmitting,
                            showsCrown: step == .review
                        ) {
                            if step == .review {
                                Task { await placeRequest() }
                            } else if canContinue, let next = step.next {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    step = next
                                }
                            }
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if selectedPickupID == nil {
                selectedPickupID = store.pickupLocations.first?.id
            }
            if selectedDropoffID == nil {
                selectedDropoffID = selectedPickupID ?? store.pickupLocations.first?.id
            }
            if selectedVehicleID == nil {
                selectedVehicleID = store.vehicles.first(where: { store.canBook($0) })?.id
            }
            targetPercent = 80
            scheduledAt = earliestSchedule
            if selectedPaymentID == nil {
                selectedPaymentID = store.defaultPaymentMethod?.id
            }
        }
        .onChange(of: scheduleDay.wrappedValue) { _, _ in
            if !timeSlotsForSelectedDay.contains(where: {
                Calendar.current.isDate($0, equalTo: scheduledAt, toGranularity: .minute)
            }), let first = timeSlotsForSelectedDay.first {
                scheduledAt = first
            }
        }
        .sheet(isPresented: $showAddAddress) {
            NavigationStack {
                AddAddressView()
            }
        }
        .sheet(isPresented: $showAddVehicle) {
            NavigationStack {
                AddVehicleView()
            }
        }
        .onChange(of: store.savedAddresses.count) { oldCount, newCount in
            if newCount > oldCount, let newest = store.savedAddresses.last {
                selectedPickupID = newest.id
                selectedDropoffID = newest.id
            } else if selectedPickupID == nil {
                selectedPickupID = store.pickupLocations.first?.id
            }
            if selectedDropoffID == nil {
                selectedDropoffID = selectedPickupID ?? store.pickupLocations.first?.id
            }
        }
        .onChange(of: store.vehicles.count) { oldCount, newCount in
            if newCount > oldCount,
               let newest = store.vehicles.last,
               store.canBook(newest) {
                selectedVehicleID = newest.id
            } else if selectedVehicleID == nil {
                selectedVehicleID = store.vehicles.first(where: { store.canBook($0) })?.id
            }
        }
    }

    private func goBack() {
        if let previous = step.previous {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                step = previous
            }
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .schedule, .vehicle:
            EmptyView()
        case .pickup:
            pickupStep
        case .dropoff:
            dropoffStep
        case .payment:
            paymentStep
        case .review:
            reviewStep
        }
    }

    // MARK: - Steps

    private var scheduleStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                BookChargeTitle(
                    leading: "When should we",
                    accent: "arrive?",
                    subtitle: "Choose a pickup date and arrival time."
                )

                // MARK: Date cards
                VStack(alignment: .leading, spacing: 10) {
                    Text("CHOOSE A PICKUP DATE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BookChargePalette.gold)
                        .tracking(1.4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(scheduleDays, id: \.self) { day in
                                let selected = Calendar.current.isDate(day, inSameDayAs: scheduledAt)
                                Button {
                                    scheduleDay.wrappedValue = day
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(selected ? .white.opacity(0.9) : BookChargePalette.gold)
                                        Text(day.formatted(.dateTime.day()))
                                            .font(.system(size: 22, weight: .bold, design: .serif))
                                            .foregroundStyle(selected ? BookChargePalette.goldSoft : BookChargePalette.emerald)
                                        Text(day.formatted(.dateTime.month(.abbreviated)).uppercased())
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(selected ? .white.opacity(0.9) : BookChargePalette.gold)
                                    }
                                    .frame(width: 64, height: 78)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(selected ? BookChargePalette.emerald : BookChargePalette.card)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(
                                                selected
                                                    ? BookChargePalette.gold.opacity(0.55)
                                                    : BookChargePalette.gold.opacity(0.35),
                                                lineWidth: selected ? 1.5 : 1
                                            )
                                    )
                                    .shadow(
                                        color: selected
                                            ? BookChargePalette.gold.opacity(0.35)
                                            : BookChargePalette.ink.opacity(0.04),
                                        radius: selected ? 10 : 4,
                                        y: selected ? 3 : 2
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                }

                // MARK: Availability ribbon
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.56, blue: 0.34))
                        .frame(width: 7, height: 7)
                    Text("Pickup availability")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BookChargePalette.emerald)

                    Text("|")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(BookChargePalette.muted.opacity(0.5))

                    Text("Concierge availability confirmed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BookChargePalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)

                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(BookChargePalette.card.opacity(0.9))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(BookChargePalette.gold.opacity(0.35), lineWidth: 1)
                        )
                )

                // MARK: Time grid
                VStack(alignment: .leading, spacing: 10) {
                    Text("SELECT ARRIVAL TIME  ·  30 MIN INTERVALS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BookChargePalette.gold)
                        .tracking(1.1)

                    if timeSlotsForSelectedDay.isEmpty {
                        Text("No more slots today. Pick another date.")
                            .font(.system(.footnote))
                            .foregroundStyle(BookChargePalette.muted)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(BookChargePalette.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                                    )
                            )
                    } else {
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Array(timeSlotsForSelectedDay.prefix(9)), id: \.self) { slot in
                                let selected = Calendar.current.isDate(
                                    slot,
                                    equalTo: selectedTimeSlot.wrappedValue,
                                    toGranularity: .minute
                                )
                                Button {
                                    selectedTimeSlot.wrappedValue = slot
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Text(slot.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 14, weight: .semibold, design: .serif))
                                            .foregroundStyle(selected ? BookChargePalette.gold : BookChargePalette.emerald)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(selected ? BookChargePalette.emerald : BookChargePalette.card)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(
                                                        selected
                                                            ? BookChargePalette.gold.opacity(0.55)
                                                            : BookChargePalette.gold.opacity(0.32),
                                                        lineWidth: selected ? 1.5 : 1
                                                    )
                                            )
                                            .shadow(
                                                color: selected
                                                    ? BookChargePalette.gold.opacity(0.28)
                                                    : .clear,
                                                radius: 8,
                                                y: 2
                                            )

                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(BookChargePalette.gold)
                                                .offset(x: 4, y: -4)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // MARK: Summary
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)

                    Text("Pickup")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(BookChargePalette.emerald)

                    Text("|")
                        .foregroundStyle(BookChargePalette.muted.opacity(0.45))

                    Text(scheduledAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BookChargePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(BookChargePalette.card)
                                .overlay(Circle().stroke(BookChargePalette.gold.opacity(0.4), lineWidth: 1))
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BookChargePalette.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(BookChargePalette.gold.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .padding(.bottom, 8)
        }
    }

    private var vehicleStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                BookChargeTitle(
                    leading: "Which EV are we",
                    accent: "charging?",
                    subtitle: "Pick your car and confirm range for pickup."
                )

                if store.vehicles.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Add a vehicle in your garage to continue.")
                            .font(.system(.subheadline))
                            .foregroundStyle(BookChargePalette.muted)

                        Button {
                            showAddVehicle = true
                        } label: {
                            Text("Add Vehicle")
                                .font(.system(.subheadline, design: .serif).weight(.semibold))
                                .foregroundStyle(BookChargePalette.gold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(BookChargePalette.emeraldGradient)
                                        .overlay(Capsule().stroke(BookChargePalette.gold.opacity(0.45), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(BookChargePalette.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                            )
                    )
                } else {
                    BookChargeVehicleCarousel(
                        vehicles: store.vehicles,
                        selectedID: $selectedVehicleID,
                        canBook: { store.canBook($0) }
                    )
                    .onChange(of: selectedVehicleID) { _, newID in
                        guard let vehicle = store.vehicles.first(where: { $0.id == newID }) else { return }
                        if !store.canBook(vehicle) || !vehicle.meetsMinimumRange {
                            rangeConfirmed = false
                        }
                    }

                    if let vehicle = selectedVehicle,
                       let reason = store.bookingBlockReason(for: vehicle) {
                        Text(reason)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                vehicle.isDocumentsApprovedForBooking
                                    ? Color.orange.opacity(0.95)
                                    : BookChargePalette.gold
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let vehicle = selectedVehicle {
                        BookChargeSmokingNotice(smokingInVehicle: vehicle.smokingInVehicle)
                    }

                    // Pickup range confirmation — toggle
                    RangeConfirmToggle(
                        isOn: $rangeConfirmed,
                        isEnabled: selectedVehicle?.meetsMinimumRange == true
                            && selectedVehicle?.isDocumentsApprovedForBooking == true
                    )
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var pickupStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            BookChargeTitle(
                leading: "Where should we",
                accent: "grab",
                trailing: "your car?",
                subtitle: "Choose a saved pickup spot."
            )

            ForEach(Array(store.pickupLocations.enumerated()), id: \.element.id) { index, location in
                BookChargePickupCard(
                    location: location,
                    systemImage: pickupIcon(location.name),
                    isSelected: selectedPickupID == location.id,
                    isDefault: location.isDefault || index == 0
                ) {
                    selectedPickupID = location.id
                    // Default return to the same spot when pickup changes and return wasn't customized.
                    if selectedDropoffID == nil || selectedDropoffID == selectedPickupID {
                        selectedDropoffID = location.id
                    }
                }
            }

            // Add New Location
            Button {
                showAddAddress = true
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .stroke(BookChargePalette.gold.opacity(0.45), lineWidth: 1.2)
                        .frame(width: 18, height: 18)

                    ZStack {
                        Circle()
                            .fill(BookChargePalette.emerald.opacity(0.12))
                            .overlay(Circle().stroke(BookChargePalette.gold.opacity(0.35), lineWidth: 1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BookChargePalette.emerald)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add New Location")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(BookChargePalette.emerald)
                        Text("Enter a new address")
                            .font(.system(size: 12))
                            .foregroundStyle(BookChargePalette.muted)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BookChargePalette.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Concierge info box
            ZStack(alignment: .bottomTrailing) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(BookChargePalette.gold)
                        .frame(width: 36, height: 36)

                    (
                        Text("Our concierge will arrive at the selected location at your scheduled time. ")
                            .foregroundStyle(BookChargePalette.emerald)
                        + Text("We'll handle the rest.")
                            .italic()
                            .foregroundStyle(BookChargePalette.gold)
                    )
                    .font(.system(size: 13, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.97, green: 0.95, blue: 0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                    )
            )
        }
    }

    private var dropoffStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            BookChargeTitle(
                leading: "Where should we",
                accent: "return",
                trailing: "your car?",
                subtitle: "Choose where we drop off your EV after charging."
            )

            if let pickup = selectedPickup {
                Button {
                    selectedDropoffID = pickup.id
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(BookChargePalette.emeraldGradient)
                                .frame(width: 40, height: 40)
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(BookChargePalette.gold)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Same as pickup")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundStyle(BookChargePalette.emerald)
                            Text("\(pickup.name) — \(pickup.address)")
                                .font(.system(size: 12))
                                .foregroundStyle(BookChargePalette.muted)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        if selectedDropoffID == pickup.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(BookChargePalette.gold)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                selectedDropoffID == pickup.id
                                    ? BookChargePalette.emerald.opacity(0.08)
                                    : BookChargePalette.card
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        selectedDropoffID == pickup.id
                                            ? BookChargePalette.gold.opacity(0.55)
                                            : BookChargePalette.gold.opacity(0.28),
                                        lineWidth: selectedDropoffID == pickup.id ? 1.5 : 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Text("OR CHOOSE ANOTHER ADDRESS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BookChargePalette.gold)
                .tracking(1.4)
                .padding(.top, 4)

            ForEach(Array(store.pickupLocations.enumerated()), id: \.element.id) { index, location in
                BookChargePickupCard(
                    location: location,
                    systemImage: pickupIcon(location.name),
                    isSelected: selectedDropoffID == location.id,
                    isDefault: false
                ) {
                    selectedDropoffID = location.id
                }
            }

            ZStack(alignment: .bottomTrailing) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(BookChargePalette.gold)
                        .frame(width: 36, height: 36)

                    (
                        Text("After charging, our concierge returns your car to this address. ")
                            .foregroundStyle(BookChargePalette.emerald)
                        + Text("Same-day white-glove delivery.")
                            .italic()
                            .foregroundStyle(BookChargePalette.gold)
                    )
                    .font(.system(size: 13, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.97, green: 0.95, blue: 0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                    )
            )
        }
    }

    private var paymentStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            BookChargeTitle(
                leading: "How will you",
                accent: "pay?",
                subtitle: paymentStepSubtitle
            )
            .padding(.bottom, 4)

            if PaymentService.isStripeConfigured {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stripe PaymentSheet", systemImage: "lock.shield.fill")
                        .font(.system(.body).weight(.semibold))
                        .foregroundStyle(BookChargePalette.emerald)
                    Text("You’ll enter card or Apple Pay details securely with Stripe when you place the request.")
                        .font(.system(.footnote))
                        .foregroundStyle(BookChargePalette.muted)
                    #if DEBUG
                    Text("DEBUG: test cards are only for sandbox keys. Production uses live Stripe checkout.")
                        .font(.system(.caption2))
                        .foregroundStyle(BookChargePalette.muted)
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .bookChargeCard()
            } else if PaymentService.allowsLocalMockPayments {
                if store.paymentMethods.isEmpty {
                    Text("Add a payment method in Profile → Payment methods first.")
                        .font(.system(.footnote))
                        .foregroundStyle(.orange)
                }

                ForEach(store.paymentMethods) { method in
                    BookChargeSelectionCard(
                        systemImage: method.brand.systemImage,
                        title: method.brand.title,
                        subtitleLines: [method.detailLabel],
                        isSelected: selectedPaymentID == method.id
                    ) {
                        selectedPaymentID = method.id
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Payments unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.body).weight(.semibold))
                        .foregroundStyle(BookChargePalette.emerald)
                    Text("Live Stripe checkout is not configured in this build. Please try again later or contact Chercharge Support.")
                        .font(.system(.footnote))
                        .foregroundStyle(BookChargePalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .bookChargeCard()
            }

            HStack {
                Text("Due today")
                    .font(.system(.body))
                    .foregroundStyle(BookChargePalette.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let pricingBreakdown, let tier = pricingBreakdown.foundingTier {
                        Text(Pricing.format(pricingBreakdown.amountDue))
                            .font(.system(.title3, design: .serif).weight(.bold))
                            .foregroundStyle(BookChargePalette.emerald)
                        Text("\(tier.shortRateLabel) · you save \(Pricing.format(pricingBreakdown.savings))")
                            .font(.system(.caption2))
                            .foregroundStyle(BookChargePalette.muted)
                    } else {
                        Text(quote?.formattedPrice ?? Pricing.format(Pricing.perBookingFee))
                            .font(.system(.title3, design: .serif).weight(.bold))
                            .foregroundStyle(BookChargePalette.emerald)
                    }
                }
            }
            .bookChargeCard()
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            BookChargeTitle(
                leading: "Review &",
                accent: "book",
                subtitle: "Confirm the details, then place your request."
            )

            if let vehicle = selectedVehicle, let pickup = selectedPickup {
                VStack(spacing: 0) {
                    BookChargeReviewRow(
                        systemImage: "calendar",
                        label: "Schedule",
                        value: reviewScheduleValue
                    ) { step = .schedule }

                    reviewDivider

                    BookChargeReviewRow(
                        systemImage: "car.fill",
                        label: "Vehicle",
                        value: vehicle.displayName
                    ) { step = .vehicle }

                    reviewDivider

                    BookChargeReviewRow(
                        systemImage: "smoke.fill",
                        label: "Smoking / vaping",
                        value: vehicle.smokingInVehicle ? "Yes — inside vehicle" : "No"
                    ) { step = .vehicle }

                    reviewDivider

                    BookChargeReviewRow(
                        systemImage: "rectangle.on.rectangle",
                        label: "Plate",
                        value: vehicle.licensePlateDisplay
                    ) { step = .vehicle }

                    reviewDivider

                    BookChargeReviewRow(
                        systemImage: "gauge.with.dots.needle.33percent",
                        label: "Range",
                        value: "\(vehicle.estimatedRangeMiles) miles left"
                    ) { step = .vehicle }

                    reviewDivider

                    BookChargeReviewRow(
                        systemImage: "mappin.and.ellipse",
                        label: "Pickup",
                        value: "\(pickup.name) — \(pickup.address)"
                    ) { step = .pickup }

                    reviewDivider

                    BookChargeReviewRow(
                        systemImage: "ev.charger.fill",
                        label: "Station",
                        value: store.station.name
                    ) { step = .pickup }

                    reviewDivider

                    BookChargeReviewRow(
                        systemImage: "bolt.fill",
                        label: "Charge",
                        value: "\(vehicle.currentChargePercent)% → \(Int(targetPercent))%"
                    ) { step = .vehicle }

                    reviewDivider

                    BookChargeReviewRow(
                        systemImage: "checkmark.shield.fill",
                        label: "Range Confirmed",
                        value: rangeConfirmed ? "Yes" : "No"
                    ) { step = .vehicle }

                    reviewDivider

                    if PaymentService.isStripeConfigured {
                        BookChargeReviewRow(
                            systemImage: "creditcard.fill",
                            label: "Payment",
                            value: "Stripe · card at confirm"
                        ) { step = .payment }
                    } else if let selectedPaymentMethod {
                        BookChargeReviewRow(
                            systemImage: "creditcard.fill",
                            label: "Payment",
                            value: "\(selectedPaymentMethod.brand.title) \(selectedPaymentMethod.detailLabel)"
                        ) { step = .payment }
                    }

                    if store.membership.tier != .standard || pricingBreakdown?.foundingTier != nil {
                        reviewDivider
                        if store.membership.tier != .standard {
                            BookChargeReviewRow(
                                systemImage: "rosette",
                                label: "Membership",
                                value: "\(store.membership.tier.title) (−\(Pricing.format(store.membership.tier.bookingDiscount)))",
                                showEdit: false
                            )
                        }
                        if let pricingBreakdown, let tier = pricingBreakdown.foundingTier {
                            if store.membership.tier != .standard { reviewDivider }
                            BookChargeReviewRow(
                                systemImage: "sparkles",
                                label: tier == .lifetime ? "Founding lifetime" : "Founding year",
                                value: "\(Pricing.format(pricingBreakdown.amountDue)) / charge",
                                showEdit: false
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(BookChargePalette.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                        )
                        .shadow(color: BookChargePalette.ink.opacity(0.06), radius: 12, y: 4)
                        .shadow(color: BookChargePalette.gold.opacity(0.10), radius: 10, y: 3)
                )

                BookChargeSecureBanner()
            }

            if let submitError {
                Text(submitError)
                    .font(.system(.footnote))
                    .foregroundStyle(.red)
            }
        }
    }

    private var reviewScheduleValue: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: scheduledAt)
    }

    private var reviewDivider: some View {
        Rectangle()
            .fill(BookChargePalette.muted.opacity(0.12))
            .frame(height: 1)
    }

    // MARK: - Helpers

    private func placeRequest() async {
        guard let vehicle = selectedVehicle,
              let pickup = selectedPickup,
              let dropoff = selectedDropoff else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        do {
            let job = try await store.createJob(
                vehicle: vehicle,
                pickup: pickup,
                dropoff: dropoff,
                targetChargePercent: Int(targetPercent),
                paymentMethod: selectedPaymentMethod,
                scheduledFor: scheduledAt,
                customerEmail: auth.displayEmail ?? store.profileEmail,
                customerName: auth.displayName ?? store.profileName
            )
            path = NavigationPath()
            path.append(AppRoute.tracking(jobID: job.id))
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func pickupIcon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("home") || n.contains("mom") || n.contains("house") { return "house.fill" }
        if n.contains("office") || n.contains("work") { return "briefcase.fill" }
        if n.contains("mission") { return "building.2.fill" }
        return "mappin.and.ellipse"
    }

    private static func snapToHalfHour(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = comps.minute ?? 0
        let snapped = minute < 30 ? 0 : 30
        var next = DateComponents()
        next.year = comps.year
        next.month = comps.month
        next.day = comps.day
        next.hour = comps.hour
        next.minute = snapped
        return cal.date(from: next) ?? date
    }

    private static func nextHalfHour(after date: Date) -> Date {
        let snapped = snapToHalfHour(date)
        if snapped >= date { return snapped }
        return Calendar.current.date(byAdding: .minute, value: 30, to: snapped) ?? date
    }
}

// MARK: - Step 2 range toggle

private struct BookChargeSmokingNotice: View {
    let smokingInVehicle: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        smokingInVehicle
                            ? BookChargePalette.gold.opacity(0.22)
                            : BookChargePalette.emerald.opacity(0.12)
                    )
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(BookChargePalette.gold.opacity(0.4), lineWidth: 1.2)
                    .frame(width: 44, height: 44)
                Image(systemName: smokingInVehicle ? "smoke.fill" : "smoke")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        smokingInVehicle ? BookChargePalette.gold : BookChargePalette.emerald
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Smoking in vehicle")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(BookChargePalette.emerald)
                Text(
                    smokingInVehicle
                        ? "Yes — drivers will see a smoke marker on this request."
                        : "No smoke or vape inside. You can change this in Vehicles."
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BookChargePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BookChargePalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

private struct RangeConfirmToggle: View {
    @Binding var isOn: Bool
    var isEnabled: Bool

    @State private var flash = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BookChargePalette.emeraldGradient)
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(BookChargePalette.gold.opacity(0.45), lineWidth: 1.2)
                        .frame(width: 44, height: 44)
                    Image(systemName: "ev.charger.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                }

                Text("At least \(Pricing.minimumRangeMiles) miles of range")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(BookChargePalette.emerald)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(BookChargePalette.emerald)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BookChargePalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isOn
                                ? BookChargePalette.gold.opacity(0.55)
                                : BookChargePalette.gold.opacity(flash ? 0.85 : 0.28),
                            lineWidth: isOn ? 1.5 : (flash ? 2 : 1)
                        )
                )
                .shadow(
                    color: isOn
                        ? BookChargePalette.gold.opacity(0.16)
                        : BookChargePalette.gold.opacity(flash ? 0.35 : 0.06),
                    radius: isOn ? 10 : (flash ? 14 : 4),
                    y: 3
                )
        )
        .opacity(isEnabled ? 1 : 0.55)
        .disabled(!isEnabled)
        .onAppear { startFlashIfNeeded() }
        .onChange(of: isEnabled) { _, _ in startFlashIfNeeded() }
        .onChange(of: isOn) { _, on in
            if on { flash = false }
            startFlashIfNeeded()
        }
    }

    private func startFlashIfNeeded() {
        guard isEnabled, !isOn else {
            flash = false
            return
        }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            flash = true
        }
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack {
        BookChargeView(path: $path)
    }
    .environment(BookingStore())
    .environment(AuthService())
}
