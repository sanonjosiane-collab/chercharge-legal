//
//  HomeView.swift
//  Chercharge
//
//  Home matches the Face luxury mock: botanical accent, greeting,
//  vehicle showcase, concierge card, Apple Maps, then Book a Charge.
//  Floating tab bar stays in ContentView (unchanged).
//

import MapKit
import SwiftUI

/// Shared home layout tokens — keep ContentView margins in sync when needed.
enum HomeLayout {
    static let horizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let cardShadow = Color.black.opacity(0.07)
}

/// Chercharge emblem — homescreen only (replaces crown SF Symbols here).
private struct HomeEmblem: View {
    var size: CGFloat = 28

    var body: some View {
        Image("CherchargeLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Chercharge")
    }
}

struct HomeView: View {
    @Environment(BookingStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(CustomerNotificationInbox.self) private var customerNotifications
    @Environment(UserLocationService.self) private var userLocation
    @Binding var path: NavigationPath
    /// Switches to the Vehicles tab (wired from ContentView).
    var onOpenVehicles: (() -> Void)? = nil

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: SampleMapData.homeMapCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.048, longitudeDelta: 0.048)
        )
    )
    @State private var didCenterOnUserLocation = false
    @State private var showInspectionApproval = false
    @State private var didAutoPresentInspectionApproval = false
    @State private var inspectionApprovalPhase: InspectionPhase = .preTrip
    @State private var showNotifications = false
    @State private var showAddVehicle = false

    private let cardFill = Color.white.opacity(0.96)
    private let emerald = Color(red: 0.05, green: 0.28, blue: 0.17)
    private let greetingGreen = Color(red: 0.05, green: 0.30, blue: 0.18)
    private let statusGreen = Color(red: 0.18, green: 0.55, blue: 0.34)
    private let softMuted = Color(red: 0.52, green: 0.54, blue: 0.50)

    private var firstName: String {
        let trimmed = store.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "there" }
        return trimmed.components(separatedBy: .whitespaces).first ?? trimmed
    }

    private var needsInspectionApproval: Bool {
        store.activeJob?.needsAnyInspectionApproval == true
    }

    private var pendingInspectionPhase: InspectionPhase? {
        guard let job = store.activeJob else { return nil }
        if job.needsCustomerApproval { return .preTrip }
        if job.needsReturnApproval { return .postTrip }
        return nil
    }

    /// Flashy Home CTA until early-bird spots (5 + 45) are gone or the user already pre-ordered.
    private var shouldShowHomePreorderCTA: Bool {
        if store.hasCompletedFoundingAccess {
            return false
        }
        if let quote = store.preorderQuote {
            if quote.existingStatus == .completed { return false }
            return quote.slotsRemaining > 0 && quote.promoApplied
        }
        return true
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Brand.ivory
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 0.988, green: 0.980, blue: 0.965),
                    Color(red: 0.975, green: 0.965, blue: 0.945)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            CherchargeBotanicalBranches()
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 18)

                    greeting
                        .padding(.bottom, 14)

                    if shouldShowHomePreorderCTA {
                        PreOrderFlashButton(
                            slotsRemaining: store.preorderQuote?.slotsRemaining ?? PreorderCampaign.maxSlots,
                            currentTier: store.preorderQuote?.tier
                        ) {
                            path.append(AppRoute.preOrder)
                        }
                        .padding(.bottom, HomeLayout.sectionSpacing)
                    }

                    if needsInspectionApproval, let job = store.activeJob, let phase = pendingInspectionPhase, !showInspectionApproval {
                        InspectionApprovalBanner(job: job, phase: phase) {
                            inspectionApprovalPhase = phase
                            showInspectionApproval = true
                        }
                        .padding(.bottom, HomeLayout.sectionSpacing)
                    }

                    Group {
                        if let vehicle = store.primaryVehicle {
                            vehicleShowcase(vehicle)
                        } else {
                            emptyVehicleCard
                        }
                    }
                    .padding(.bottom, HomeLayout.sectionSpacing)

                    conciergeCard
                        .padding(.bottom, HomeLayout.sectionSpacing)

                    mapSection
                        .padding(.bottom, HomeLayout.sectionSpacing)

                    BookChargeButton {
                        path.append(AppRoute.book)
                    }
                    .disabled(store.activeJob != nil || store.isLoading)
                    .opacity(store.activeJob == nil ? 1 : 0.45)
                }
                .padding(.horizontal, HomeLayout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.refreshPreorderQuote(auth: auth)
        }
        .sheet(isPresented: $showInspectionApproval) {
            InspectionApprovalSheet(path: $path, phase: inspectionApprovalPhase) {
                showInspectionApproval = false
            }
        }
        .profileRouteDestinations()
        .sheet(isPresented: $showNotifications) {
            CustomerNotificationsSheet()
        }
        .sheet(isPresented: $showAddVehicle) {
            NavigationStack {
                AddVehicleView()
            }
        }
        .onAppear {
            presentInspectionApprovalIfNeeded(force: false)
        }
        .onChange(of: store.activeJob?.status) { _, _ in
            presentInspectionApprovalIfNeeded(force: true)
        }
        .onChange(of: store.activeJob?.needsAnyInspectionApproval) { _, needsApproval in
            if needsApproval != true {
                showInspectionApproval = false
                didAutoPresentInspectionApproval = false
            } else {
                presentInspectionApprovalIfNeeded(force: true)
            }
        }
    }

    private func presentInspectionApprovalIfNeeded(force: Bool) {
        guard let phase = pendingInspectionPhase else {
            showInspectionApproval = false
            return
        }
        inspectionApprovalPhase = phase
        if force || !didAutoPresentInspectionApproval {
            showInspectionApproval = true
            didAutoPresentInspectionApproval = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                HomeEmblem(size: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("CHERCHARGE")
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(greetingGreen)
                        .tracking(1.4)
                    Text("EV CONCIERGE")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(greetingGreen.opacity(0.7))
                        .tracking(1.8)
                }
            }

            Spacer(minLength: 0)

            ZStack(alignment: .topTrailing) {
                Button {
                    showNotifications = true
                } label: {
                    Image(systemName: customerNotifications.hasUnread ? "bell.fill" : "bell")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(greetingGreen)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    customerNotifications.hasUnread
                        ? "Notifications, \(customerNotifications.unreadCount) unread"
                        : "Notifications"
                )

                if customerNotifications.hasUnread {
                    Text("\(min(customerNotifications.unreadCount, 9))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(greetingGreen)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Circle().fill(Brand.gold))
                        .offset(x: 2, y: 0)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Self.greetingPrefix()),")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(greetingGreen)

            Text(firstName)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(Brand.gold)

            Text("Your EV Concierge is ready.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(softMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Vehicle showcase

    private func vehicleShowcase(_ vehicle: Vehicle) -> some View {
        ZStack(alignment: .topTrailing) {
            HomeEmblem(size: 78)
                .opacity(0.08)
                .padding(.trailing, 4)
                .padding(.top, 2)
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vehicle.homeCardTitle)
                            .font(.system(size: 17, weight: .bold, design: .serif))
                            .foregroundStyle(greetingGreen)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(vehicle.homeTrimLabel)
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundStyle(Brand.gold)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "battery.100.bolt")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(statusGreen)
                        Text("\(vehicle.currentChargePercent)%")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(greetingGreen)
                    }

                    Text("\(vehicle.estimatedRangeMiles) Miles Available")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(softMuted)

                    VStack(alignment: .leading, spacing: 5) {
                        Label {
                            Text(vehicle.currentChargePercent >= 80 ? "Fully Charged" : "Charging Ready")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(softMuted)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(statusGreen)
                        }

                        HStack(spacing: 5) {
                            HomeEmblem(size: 12)
                            Text(vehicle.meetsMinimumRange ? "Ready for Pickup" : "Low Range")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(softMuted)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VehicleGarage3DStage(
                    vehicle: vehicle,
                    height: 132,
                    autoSpin: true,
                    showsHint: false
                )
                .frame(width: 168, height: 132)
            }
            .padding(HomeLayout.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HomeLayout.cardRadius, style: .continuous)
                .fill(cardFill)
                .shadow(color: HomeLayout.cardShadow, radius: 14, y: 5)
        )
    }

    private var emptyVehicleCard: some View {
        Button {
            if let onOpenVehicles {
                onOpenVehicles()
            } else {
                showAddVehicle = true
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Register your vehicle")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(greetingGreen)
                    Text("Save a car to see charge and range — then book concierge pickup.")
                        .font(.system(size: 13))
                        .foregroundStyle(softMuted)
                    GoldBeadDivider(width: 88)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(emerald.opacity(0.7))
            }
            .padding(HomeLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HomeLayout.cardRadius, style: .continuous)
                    .fill(cardFill)
                    .shadow(color: HomeLayout.cardShadow, radius: 14, y: 5)
            )
        }
        .buttonStyle(.plain)
        .brandCardSettle()
    }

    // MARK: - Concierge

    private var conciergeCard: some View {
        Group {
            if !CherchargeServiceAvailability.isLiveConciergeAvailable {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(emerald.opacity(0.12))
                            .overlay(Circle().stroke(Brand.gold.opacity(0.55), lineWidth: 1.5))
                            .frame(width: 56, height: 56)
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(emerald)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(CherchargeServiceAvailability.conciergeCardTitle.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Brand.gold)

                        Text(CherchargeServiceAvailability.notAvailableTitle)
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(greetingGreen)

                        Text(CherchargeServiceAvailability.conciergeCardSubtitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.gold.opacity(0.9))

                        Text(CherchargeServiceAvailability.conciergeCardDetail)
                            .font(.system(size: 12))
                            .foregroundStyle(softMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(HomeLayout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: HomeLayout.cardRadius, style: .continuous)
                        .fill(cardFill)
                        .shadow(color: HomeLayout.cardShadow, radius: 12, y: 4)
                )
            } else if let driver = store.nextAvailableDriver {
                Button {
                    if let job = store.activeJob {
                        path.append(AppRoute.tracking(jobID: job.id))
                    } else {
                        path.append(AppRoute.book)
                    }
                } label: {
                    HStack(spacing: 14) {
                        ZStack(alignment: .bottomTrailing) {
                            Text(driver.initials)
                                .font(.system(size: 20, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(emerald)
                                        .overlay(Circle().stroke(Brand.gold.opacity(0.65), lineWidth: 1.5))
                                )

                            HomeEmblem(size: 18)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 20, height: 20)
                                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                )
                                .offset(x: 2, y: 2)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your Concierge")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Brand.gold)

                            Text(driver.firstName)
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .foregroundStyle(greetingGreen)

                            Text(driver.tier)
                                .font(.system(size: 12))
                                .foregroundStyle(softMuted)

                            HStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { index in
                                    Image(systemName: index < Int(driver.rating.rounded()) ? "star.fill" : "star")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Brand.gold)
                                }
                                Text(String(format: "%.2f", driver.rating))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(greetingGreen)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(statusGreen)
                                Text("\(driver.etaMinutes) min away")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(statusGreen)
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(emerald.opacity(0.7))
                    }
                    .padding(HomeLayout.cardPadding)
                    .background(
                        RoundedRectangle(cornerRadius: HomeLayout.cardRadius, style: .continuous)
                            .fill(cardFill)
                            .shadow(color: HomeLayout.cardShadow, radius: 12, y: 4)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Text("Searching for your concierge…")
                    .font(.system(size: 14))
                    .foregroundStyle(softMuted)
                    .padding(HomeLayout.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: HomeLayout.cardRadius, style: .continuous)
                            .fill(cardFill)
                            .shadow(color: HomeLayout.cardShadow, radius: 12, y: 4)
                    )
            }
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            if CherchargeServiceAvailability.isLiveConciergeAvailable {
                ForEach(store.chargingStations) { station in
                    Annotation(station.name, coordinate: station.coordinate) {
                        mapPin(systemImage: "bolt.car.fill", tint: Brand.green)
                    }
                }
                ForEach(store.nearbyDrivers) { driver in
                    Annotation(driver.label, coordinate: driver.coordinate) {
                        mapPin(
                            systemImage: "car.fill",
                            tint: driver.status == .available
                                ? Color(red: 0.12, green: 0.35, blue: 0.55)
                                : Color(red: 0.55, green: 0.40, blue: 0.12)
                        )
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 176)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: HomeLayout.cardRadius, style: .continuous))
        .shadow(color: HomeLayout.cardShadow, radius: 12, y: 4)
        .allowsHitTesting(false)
        .onAppear {
            userLocation.refresh(preferenceEnabled: store.settings.locationAccessEnabled)
            centerMapOnBestAvailableLocation(force: false)
        }
        .onChange(of: userLocation.coordinate?.latitude) { _, _ in
            // Center once when GPS arrives — continuous Map camera animation freezes Home.
            centerMapOnBestAvailableLocation(force: false)
        }
        .onChange(of: store.settings.locationAccessEnabled) { _, enabled in
            didCenterOnUserLocation = false
            userLocation.refresh(preferenceEnabled: enabled)
            centerMapOnBestAvailableLocation(force: true)
        }
    }

    /// Prefers live GPS; falls back to a saved address; only then uses the SF sample center.
    private func centerMapOnBestAvailableLocation(force: Bool) {
        if let coordinate = userLocation.coordinate {
            guard force || !didCenterOnUserLocation else { return }
            didCenterOnUserLocation = true
            updateCamera(to: coordinate, animated: true)
            return
        }

        guard force || !didCenterOnUserLocation else { return }

        if let saved = store.savedAddresses.first {
            didCenterOnUserLocation = true
            updateCamera(
                to: CLLocationCoordinate2D(latitude: saved.latitude, longitude: saved.longitude),
                animated: false
            )
            return
        }

        // Keep SF sample only until GPS / a saved address is available.
        updateCamera(to: SampleMapData.homeMapCenter, animated: false)
    }

    private func updateCamera(to coordinate: CLLocationCoordinate2D, animated: Bool) {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.048, longitudeDelta: 0.048)
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.55)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }

    private func mapPin(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(tint))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    private static func greetingPrefix(now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<21: return "Good Evening"
        default: return "Good Night"
        }
    }
}

// MARK: - Vehicle trim helper

private extension Vehicle {
    var homeTrimLabel: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           trimmed.lowercased() != model.lowercased(),
           trimmed.lowercased() != homeCardTitle.lowercased() {
            return trimmed
        }
        if model.lowercased().contains("performance") { return "Performance" }
        return "Performance"
    }
}

// MARK: - Photoreal car (360° turntable — car only)

private struct HomeCarPhoto: View {
    let vehicle: Vehicle

    /// Studio views sequenced as a turntable orbit (front 3/4 → side → rear → mirrored).
    private let orbit: [(view: String, flip: Bool)] = [
        ("STUD_3QTR", false),
        ("STUD_SIDE", false),
        ("STUD_REAR", false),
        ("STUD_SIDE", true),
        ("STUD_3QTR", true)
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2.6)) { context in
            let frameIndex = Int(context.date.timeIntervalSinceReferenceDate / 2.6) % orbit.count
            let frame = orbit[frameIndex]

            // One frame at a time — loading five 1400px compositor images froze Home.
            turntableFrame(frame)
                .id("\(frame.view)-\(frame.flip)")
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.85), value: frameIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func turntableFrame(_ frame: (view: String, flip: Bool)) -> some View {
        if let url = compositorURL(view: frame.view) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(x: frame.flip ? -1 : 1, y: 1)
                case .empty:
                    ProgressView().tint(Brand.greenDeep)
                case .failure:
                    fallbackSymbol
                @unknown default:
                    fallbackSymbol
                }
            }
        } else {
            fallbackSymbol
        }
    }

    private var fallbackSymbol: some View {
        Image(systemName: "car.side.fill")
            .font(.system(size: 42, weight: .light))
            .foregroundStyle(Brand.greenDeep.opacity(0.45))
            .symbolRenderingMode(.hierarchical)
    }

    private func compositorURL(view: String) -> URL? {
        let modelCode = vehicle.teslaModelCode ?? inferredModelCode
        guard let modelCode else { return nil }
        let paint = vehicle.paintColor.compositorCode
        let string = "https://static-assets.tesla.com/v1/compositor/?model=\(modelCode)&view=\(view)&size=600&bkba_opt=1&options=\(paint),$W39B"
        return URL(string: string)
    }

    private var inferredModelCode: String? {
        let blob = "\(vehicle.make) \(vehicle.model) \(vehicle.name)".lowercased()
        if blob.contains("model 3") || blob.contains("model3") || blob.hasSuffix(" 3") { return "m3" }
        if blob.contains("model y") || blob.contains("modely") { return "my" }
        if blob.contains("model s") || blob.contains("models") { return "ms" }
        if blob.contains("model x") || blob.contains("modelx") { return "mx" }
        return nil
    }
}

// MARK: - Flashy Home pre-order CTA

private struct PreOrderFlashButton: View {
    let slotsRemaining: Int
    let currentTier: PreorderTier?
    let action: () -> Void

    @State private var shimmer = false
    @State private var pulse = false
    @State private var sparkle = false

    private let emerald = Color(red: 0.05, green: 0.28, blue: 0.17)
    private let emeraldDeep = Color(red: 0.03, green: 0.18, blue: 0.12)
    private let brightGold = Color(red: 0.95, green: 0.80, blue: 0.36)
    private let champagne = Color(red: 0.90, green: 0.74, blue: 0.42)

    private var headline: String {
        switch currentTier {
        case .lifetime: return "Reserve $10 / charge for life"
        case .year: return "Reserve $39.99 / charge for a year"
        case nil: return "Founding Access rates"
        }
    }

    private var spotsLine: String {
        if let currentTier, currentTier == .lifetime {
            let left = min(slotsRemaining, PreorderCampaign.lifetimeSlots)
            return "\(left) of \(PreorderCampaign.lifetimeSlots) lifetime spots left"
        }
        if let currentTier, currentTier == .year {
            let left = min(slotsRemaining, PreorderCampaign.yearSlots)
            return "\(left) of \(PreorderCampaign.yearSlots) year spots left"
        }
        return "\(slotsRemaining) early-bird spots left · then $49.99"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [emerald, emeraldDeep, emerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [brightGold.opacity(0.28), .clear],
                            center: .topTrailing,
                            startRadius: 4,
                            endRadius: 140
                        )
                    )
                    .allowsHitTesting(false)

                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            .clear,
                            brightGold.opacity(0.0),
                            brightGold.opacity(0.55),
                            .white.opacity(0.35),
                            brightGold.opacity(0.0),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.45)
                    .offset(x: shimmer ? proxy.size.width : -proxy.size.width * 0.45)
                    .blendMode(.plusLighter)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(brightGold.opacity(0.22))
                            .frame(width: 46, height: 46)
                            .scaleEffect(pulse ? 1.08 : 1.0)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(brightGold)
                            .rotationEffect(.degrees(sparkle ? -8 : 8))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PRE-ORDER NOW")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2.0)
                            .foregroundStyle(brightGold)

                        Text(headline)
                            .font(.system(size: 17, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(spotsLine)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(brightGold)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 88)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [brightGold, champagne, brightGold.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.8
                    )
            )
            .shadow(color: emeraldDeep.opacity(0.4), radius: 16, y: 8)
            .shadow(color: brightGold.opacity(pulse ? 0.45 : 0.2), radius: pulse ? 16 : 8, y: 4)
            .scaleEffect(pulse ? 1.015 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Founding Access early-bird charging rate")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                sparkle = true
            }
            startShimmer()
        }
    }

    private func startShimmer() {
        shimmer = false
        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
            shimmer = true
        }
    }
}

// MARK: - Book a Charge

struct BookChargeButton: View {
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var breathe = false
    @State private var glowAngle: Double = 0

    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
    /// Homescreen CTA — lighter emerald wash.
    private let fill = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.48, blue: 0.34),
            Color(red: 0.10, green: 0.38, blue: 0.26)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Brighter gold for CTA label and accents.
    private let brightGold = Color(red: 0.93, green: 0.78, blue: 0.38)

    var body: some View {
        Button(action: action) {
            ZStack {
                    Text("BOOK A CHARGE")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .tracking(2.0)
                    .foregroundStyle(brightGold)
                    .frame(maxWidth: .infinity)

                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.14))
                            .overlay(
                                Circle()
                                    .stroke(brightGold.opacity(0.7), lineWidth: 1.2)
                            )
                            .frame(width: 40, height: 40)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(brightGold)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(brightGold)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(shape.fill(fill))
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [
                            brightGold.opacity(0.55),
                            brightGold.opacity(0.22),
                            brightGold.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
            )
            .overlay {
                shape
                    .stroke(
                        AngularGradient(
                            colors: [
                                .clear,
                                brightGold.opacity(0.12),
                                brightGold.opacity(0.95),
                                brightGold.opacity(0.28),
                                .clear,
                                .clear
                            ],
                            center: .center,
                            angle: .degrees(glowAngle)
                        ),
                        lineWidth: 2.2
                    )
            }
            .shadow(color: Color(red: 0.10, green: 0.38, blue: 0.26).opacity(0.22), radius: 12, y: 6)
            .shadow(
                color: brightGold.opacity(breathe ? 0.34 : 0.14),
                radius: breathe ? 14 : 7,
                y: breathe ? 5 : 3
            )
            .scaleEffect(breathe ? 1.012 : 1.0)
        }
        .buttonStyle(.plain)
        .onAppear { startMotionIfNeeded() }
        .onChange(of: isEnabled) { _, enabled in
            if enabled {
                startMotionIfNeeded()
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    breathe = false
                }
            }
        }
    }

    private func startMotionIfNeeded() {
        guard isEnabled else { return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            breathe = true
        }
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
            glowAngle = 360
        }
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        HomeView(path: $path)
    }
    .environment(BookingStore())
    .environment(CustomerNotificationInbox())
    .environment(AuthService())
    .environment(UserLocationService())
}
