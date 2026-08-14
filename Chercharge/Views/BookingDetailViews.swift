//
//  BookingDetailViews.swift
//  Chercharge
//

import MapKit
import SwiftUI

// MARK: - Shared row

private struct BookingSummaryRow: View {
    let job: ChargeJob
    var emphasize: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: emphasize ? "bolt.car.fill" : "checkmark.circle.fill")
                .foregroundStyle(emphasize ? Brand.green : Brand.muted)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.vehicle.displayName)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Brand.ink)
                Text("\(job.startingChargePercent)% → \(job.targetChargePercent)% · \(job.pickup.name)")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Brand.muted)
                Text(job.status.title)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(Brand.greenDeep)
            }

            Spacer(minLength: 8)

            Text(job.formattedPrice)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Brand.greenDeep)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Upcoming

struct UpcomingChargesView: View {
    @Environment(BookingStore.self) private var store
    @Binding var path: NavigationPath
    var onBookCharge: (() -> Void)? = nil

    var body: some View {
        List {
            if store.upcomingJobs.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No upcoming charges",
                        systemImage: "calendar",
                        description: Text("Scheduled pickups will show up here.")
                    )
                    .listRowBackground(Color.clear)
                }
                if let onBookCharge, CherchargeServiceAvailability.isLiveConciergeAvailable {
                    Section {
                        Button("Book a Charge") {
                            onBookCharge()
                        }
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Brand.greenDeep)
                    }
                }
            } else {
                Section {
                    ForEach(store.upcomingJobs) { job in
                        VStack(alignment: .leading, spacing: 10) {
                            BookingSummaryRow(job: job)

                            HStack {
                                if CherchargeServiceAvailability.isLiveConciergeAvailable {
                                    Button("Start now") {
                                        store.startUpcomingNow(id: job.id)
                                        path.append(AppRoute.tracking(jobID: job.id))
                                    }
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Brand.greenDeep)
                                    .disabled(store.activeJob != nil)
                                } else {
                                    Text(CherchargeServiceAvailability.notAvailableTitle)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Brand.muted)
                                }

                                Spacer()

                                Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Brand.muted)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let id = store.upcomingJobs[index].id
                            store.cancelUpcomingJob(id: id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .brandBackground()
        .navigationTitle("Upcoming charges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.upcomingJobs.isEmpty || store.activeJob != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        store.clearOpenBookings()
                    }
                    .foregroundStyle(Brand.greenDeep)
                }
            }
        }
    }
}

// MARK: - Active

struct ActiveChargeView: View {
    @Environment(BookingStore.self) private var store
    @Binding var path: NavigationPath
    var onBookCharge: (() -> Void)? = nil

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var body: some View {
        ZStack {
            LiveStatusBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Active charge")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(ConciergeLuxe.emerald)
                        .padding(.top, 8)

                    if !CherchargeServiceAvailability.isLiveConciergeAvailable {
                        ConciergeCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(CherchargeServiceAvailability.notAvailableTitle)
                                    .font(.system(.title3, design: .serif).weight(.semibold))
                                    .foregroundStyle(ConciergeLuxe.emerald)
                                Text(CherchargeServiceAvailability.liveStatusMessage)
                                    .font(.system(.footnote))
                                    .foregroundStyle(ConciergeLuxe.muted)
                            }
                        }
                    } else if let active = store.activeJob {
                        Button {
                            path.append(AppRoute.tracking(jobID: active.id))
                        } label: {
                            ConciergeCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(active.vehicle.displayName)
                                        .font(.system(.title3, design: .serif).weight(.semibold))
                                        .foregroundStyle(ConciergeLuxe.emerald)
                                    Text(active.status.title)
                                        .font(.system(.subheadline).weight(.semibold))
                                        .foregroundStyle(ConciergeLuxe.goldDark)
                                    Text("Open live status")
                                        .font(.system(.footnote).weight(.semibold))
                                        .foregroundStyle(ConciergeLuxe.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .brandCardSettle()

                        Button {
                            store.clearOpenBookings()
                        } label: {
                            Text("Cancel trip & clear bookings")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.75, green: 0.25, blue: 0.15))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        idleLiveMap
                            .brandLeafFade()

                        ConciergeCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No live trip yet")
                                    .font(.system(size: 20, weight: .semibold, design: .serif))
                                    .foregroundStyle(ConciergeLuxe.emerald)
                                Text("When a concierge charge is underway, your route, valet, and inspections appear here.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(ConciergeLuxe.muted)
                                GoldBeadDivider(width: 100)
                                if let onBookCharge {
                                    Button(action: onBookCharge) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "bolt.fill")
                                            Text("Book a Charge")
                                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                        }
                                        .foregroundStyle(ConciergeLuxe.gold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            Capsule()
                                                .fill(ConciergeLuxe.emeraldGradient)
                                                .overlay(Capsule().stroke(ConciergeLuxe.gold.opacity(0.45), lineWidth: 1))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .brandCardSettle(delay: 0.1)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var idleLiveMap: some View {
        Map(position: $cameraPosition) {
            if let station = store.chargingStations.first {
                Annotation("Station", coordinate: station.coordinate) {
                    Image(systemName: "ev.charger.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ConciergeLuxe.gold)
                        .padding(8)
                        .background(Circle().fill(ConciergeLuxe.emerald))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ConciergeLuxe.gold.opacity(0.28), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Text("LIVE MAP")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(ConciergeLuxe.gold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(ConciergeLuxe.emerald.opacity(0.92)))
                .padding(12)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Completed

struct CompletedChargesView: View {
    @Environment(BookingStore.self) private var store
    @Binding var path: NavigationPath

    var body: some View {
        List {
            if store.pastJobs.isEmpty {
                ContentUnavailableView(
                    "No completed charges",
                    systemImage: "checkmark.circle",
                    description: Text("Finished trips will appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.pastJobs) { job in
                        VStack(alignment: .leading, spacing: 10) {
                            BookingSummaryRow(job: job)

                            if job.canCompareInspections {
                                Button {
                                    path.append(AppRoute.compareInspections(jobID: job.id))
                                } label: {
                                    Label(
                                        job.inspectionComparison?.hasNewDamage == true
                                            ? "Compare inspections · new damage"
                                            : "Compare pickup & return",
                                        systemImage: "rectangle.split.2x1"
                                    )
                                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                                    .foregroundStyle(
                                        job.inspectionComparison?.hasNewDamage == true
                                            ? Color(red: 0.55, green: 0.22, blue: 0.08)
                                            : Brand.greenDeep
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .brandBackground()
        .navigationTitle("Completed charges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Receipts

struct ReceiptsView: View {
    @Environment(BookingStore.self) private var store

    var body: some View {
        List {
            if store.pastJobs.isEmpty {
                ContentUnavailableView(
                    "No receipts yet",
                    systemImage: "doc.text",
                    description: Text("Receipts are created when a charge is completed.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.pastJobs) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(job.displayReceiptNumber)
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Brand.muted)
                                Spacer()
                                Text((job.completedAt ?? job.createdAt).formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Brand.muted)
                            }

                            Text(job.vehicle.displayName)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(Brand.ink)

                            labeled("Charge", "\(job.startingChargePercent)% → \(job.targetChargePercent)%")
                            labeled("Pickup", job.pickup.address)
                            labeled("Station", job.station.name)
                            if let payment = job.paymentMethodLabel {
                                labeled("Payment", payment)
                            }
                            if let intent = job.paymentIntentID {
                                labeled("Payment ID", intent)
                            }
                            labeled("Total", job.formattedPrice)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text(
                        PaymentService.isStripeConfigured
                            ? "Receipts include Stripe PaymentIntent IDs from PaymentSheet."
                            : (PaymentService.allowsLocalMockPayments
                                ? "Receipts are stored on-device with local payment references."
                                : "Receipts are stored with your booking once Stripe checkout completes.")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .brandBackground()
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Brand.muted)
            Spacer()
            Text(value)
                .foregroundStyle(Brand.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(.footnote, design: .rounded))
    }
}

// MARK: - Cancel / Reschedule

struct CancelRescheduleView: View {
    @Environment(BookingStore.self) private var store
    @Binding var path: NavigationPath
    var onBookCharge: (() -> Void)? = nil
    @State private var message: String?

    var body: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Brand.greenDeep)
                }
            }

            if let active = store.activeJob {
                Section("Active charge") {
                    BookingSummaryRow(job: active, emphasize: true)

                    Button("Cancel active charge", role: .destructive) {
                        store.cancelActiveJob()
                        message = "Active charge canceled."
                    }
                }
            }

            Section("Upcoming charges") {
                if store.upcomingJobs.isEmpty {
                    Text("Nothing scheduled to change.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Brand.muted)
                } else {
                    ForEach(store.upcomingJobs) { job in
                        VStack(alignment: .leading, spacing: 10) {
                            BookingSummaryRow(job: job)

                            HStack(spacing: 16) {
                                Button("Cancel", role: .destructive) {
                                    store.cancelUpcomingJob(id: job.id)
                                    message = "Upcoming charge canceled."
                                }
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            }
                        }
                    }
                }
            }

            if store.activeJob == nil && store.upcomingJobs.isEmpty {
                Section {
                    ContentUnavailableView(
                        CherchargeServiceAvailability.isLiveConciergeAvailable
                            ? "Nothing to manage"
                            : CherchargeServiceAvailability.notAvailableTitle,
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text(
                            CherchargeServiceAvailability.isLiveConciergeAvailable
                                ? "Book or schedule a charge to cancel or reschedule."
                                : CherchargeServiceAvailability.bookMessage
                        )
                    )
                    .listRowBackground(Color.clear)
                }
                if let onBookCharge, CherchargeServiceAvailability.isLiveConciergeAvailable {
                    Section {
                        Button("Book a Charge") {
                            onBookCharge()
                        }
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Brand.greenDeep)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .brandBackground()
        .navigationTitle("Cancel / Reschedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Upcoming") {
    @Previewable @State var path = NavigationPath()
    NavigationStack {
        UpcomingChargesView(path: $path)
    }
    .environment(BookingStore())
}
