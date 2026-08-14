//
//  BookingsView.swift
//  Chercharge
//
//  Reservations tab — matched to the Face / mock image.
//  Do not alter ConciergeFloatingTabBar from this file.
//

import SwiftUI

struct BookingsView: View {
    @Environment(BookingStore.self) private var store
    @Environment(CustomerNotificationInbox.self) private var customerNotifications
    @Binding var path: NavigationPath
    var onOpenHomeBooking: (() -> Void)?

    @State private var showNotifications = false

    var body: some View {
        ZStack {
            ReservationsBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 2)

                    greetingBlock
                        .padding(.top, 22)

                    groupedCard {
                        reservationRow(
                            title: "Upcoming charges",
                            subtitle: "View your scheduled pickups",
                            systemImage: "calendar",
                            badge: store.upcomingJobs.isEmpty ? nil : "\(store.upcomingJobs.count)",
                            route: .upcoming,
                            showDivider: true
                        )
                        reservationRow(
                            title: "Active charge",
                            subtitle: "Track your charging in real time",
                            systemImage: "bolt.fill",
                            badge: nil,
                            route: .active,
                            showDivider: true
                        )
                        reservationRow(
                            title: "Completed charges",
                            subtitle: "See your charge history",
                            systemImage: "checkmark",
                            badge: store.pastJobs.isEmpty ? nil : "\(store.pastJobs.count)",
                            route: .completed,
                            showDivider: true
                        )
                        reservationRow(
                            title: "Cancel / Reschedule",
                            subtitle: "Manage or reschedule bookings",
                            systemImage: "arrow.triangle.2.circlepath",
                            badge: nil,
                            route: .cancelReschedule,
                            showDivider: false
                        )
                    }
                    .padding(.top, 26)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: BookingRoute.self) { route in
            switch route {
            case .upcoming:
                UpcomingChargesView(path: $path, onBookCharge: onOpenHomeBooking)
            case .active:
                ActiveChargeView(path: $path, onBookCharge: onOpenHomeBooking)
            case .completed:
                CompletedChargesView(path: $path)
            case .cancelReschedule:
                CancelRescheduleView(path: $path, onBookCharge: onOpenHomeBooking)
            }
        }
        .sheet(isPresented: $showNotifications) {
            CustomerNotificationsSheet()
        }
        .profileRouteDestinations()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            // Notification bell — admin document decisions, etc.
            Button {
                showNotifications = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: customerNotifications.hasUnread ? "bell.fill" : "bell")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ConciergeLuxe.emerald)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(ConciergeLuxe.card)
                                .overlay(Circle().stroke(ConciergeLuxe.gold.opacity(0.28), lineWidth: 1))
                                .shadow(color: ConciergeLuxe.charcoal.opacity(0.08), radius: 8, y: 3)
                        )

                    if customerNotifications.hasUnread {
                        Text("\(min(customerNotifications.unreadCount, 9))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ConciergeLuxe.emerald)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Circle().fill(ConciergeLuxe.gold))
                            .overlay(Circle().stroke(ConciergeLuxe.card, lineWidth: 1.5))
                            .offset(x: 1, y: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                customerNotifications.hasUnread
                    ? "Notifications, \(customerNotifications.unreadCount) unread"
                    : "Notifications"
            )
            .frame(width: 52, alignment: .leading)

            Spacer(minLength: 0)

            // Center brand lockup
            VStack(spacing: 5) {
                Image("CherchargeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)

                VStack(spacing: 2) {
                    Text("CHERCHARGE")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(ConciergeLuxe.emerald)
                        .tracking(2.2)
                    Text("EV CONCIERGE")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(ConciergeLuxe.emerald.opacity(0.72))
                        .tracking(2.6)
                }
            }

            Spacer(minLength: 0)

            // Balance the bell so the brand lockup stays centered
            Color.clear
                .frame(width: 52, height: 44)
        }
    }

    // MARK: - Greeting + soft hero Tesla

    private var greetingBlock: some View {
        ZStack(alignment: .leading) {
            // Soft-focus white Tesla peeking from the left (mock hero)
            if let vehicle = store.vehicles.first {
                ReservationsHeroCar(vehicle: vehicle)
                    .frame(width: 210, height: 130)
                    .offset(x: -78, y: 8)
                    .opacity(0.55)
                    .blur(radius: 0.6)
                    .allowsHitTesting(false)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.55), .white.opacity(0.15), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            (
                Text("Welcome, ")
                    .foregroundStyle(ConciergeLuxe.emerald)
                + Text(store.profileName)
                    .foregroundStyle(ConciergeLuxe.gold)
            )
            .font(.system(size: 30, weight: .bold, design: .serif))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.85)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 72)
    }

    // MARK: - Stationery cards

    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(spacing: 0) {
            content()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background(
            shape
                .fill(ConciergeLuxe.card)
                .overlay(shape.stroke(ConciergeLuxe.gold.opacity(0.28), lineWidth: 1))
                .shadow(color: ConciergeLuxe.charcoal.opacity(0.07), radius: 14, y: 5)
                .shadow(color: ConciergeLuxe.gold.opacity(0.08), radius: 10, y: 3)
        )
    }

    private func reservationRow(
        title: String,
        subtitle: String,
        systemImage: String,
        badge: String?,
        route: BookingRoute,
        showDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: route) {
                HStack(spacing: 14) {
                    ConciergeMedallion(systemImage: systemImage, size: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(ConciergeLuxe.emerald)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }

                    Spacer(minLength: 8)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ConciergeLuxe.goldDark)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(ConciergeLuxe.ivory)
                                    .overlay(Circle().stroke(ConciergeLuxe.gold, lineWidth: 1.2))
                            )
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ConciergeLuxe.gold)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDivider {
                Rectangle()
                    .fill(ConciergeLuxe.gold.opacity(0.22))
                    .frame(height: 0.5)
                    .padding(.leading, 58)
            }
        }
    }

}

// MARK: - Reservations-only background (cream + warm glow)

private struct ReservationsBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ConciergeLuxe.ivory, ConciergeLuxe.ivoryDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft warm luminous glow from top / center (mock lighting)
            RadialGradient(
                colors: [
                    Color(red: 0.95, green: 0.90, blue: 0.75).opacity(0.42),
                    Color(red: 0.95, green: 0.90, blue: 0.75).opacity(0.12),
                    .clear
                ],
                center: UnitPoint(x: 0.42, y: 0.08),
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            RadialGradient(
                colors: [
                    ConciergeLuxe.gold.opacity(0.10),
                    .clear
                ],
                center: UnitPoint(x: 0.88, y: 0.22),
                startRadius: 10,
                endRadius: 220
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Same botanical leaf format as Home.
            CherchargeBotanicalBranches()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Photoreal Tesla (greeting hero)

private struct ReservationsHeroCar: View {
    let vehicle: Vehicle

    var body: some View {
        if let url = compositorURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .empty:
                    ProgressView().tint(ConciergeLuxe.emerald)
                case .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Image(systemName: "car.side.fill")
            .font(.system(size: 40, weight: .light))
            .foregroundStyle(ConciergeLuxe.gold.opacity(0.55))
            .symbolRenderingMode(.hierarchical)
    }

    private var compositorURL: URL? {
        let modelCode = vehicle.teslaModelCode ?? inferredModelCode
        guard let modelCode else { return nil }
        let paint = vehicle.paintColor.compositorCode
        let string = "https://static-assets.tesla.com/v1/compositor/?model=\(modelCode)&view=STUD_3QTR&size=600&bkba_opt=1&options=\(paint),$W39B"
        return URL(string: string)
    }

    private var inferredModelCode: String? {
        let blob = "\(vehicle.make) \(vehicle.model) \(vehicle.name)".lowercased()
        if blob.contains("model 3") || blob.contains("model3") { return "m3" }
        if blob.contains("model y") || blob.contains("modely") { return "my" }
        if blob.contains("model s") || blob.contains("models") { return "ms" }
        if blob.contains("model x") || blob.contains("modelx") { return "mx" }
        return "m3"
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack {
        BookingsView(path: $path)
    }
    .environment(BookingStore())
    .environment(CustomerNotificationInbox())
}
