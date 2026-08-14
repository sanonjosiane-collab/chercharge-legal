//
//  VehiclesView.swift
//  Chercharge
//
//  Vehicles tab — matches the luxury mock: cream parchment + botanical foil,
//  crown header, Connect Tesla row, garage cards, crest Add Vehicle CTA.
//

import SwiftUI

private enum VehiclesTabPalette {
    static let cream = Color(red: 0.980, green: 0.973, blue: 0.955)
    static let creamDeep = Color(red: 0.965, green: 0.955, blue: 0.930)
    static let card = Color(red: 0.995, green: 0.990, blue: 0.978)
    static let emerald = Color(red: 0.043, green: 0.141, blue: 0.110)
    static let emeraldMid = Color(red: 0.06, green: 0.26, blue: 0.18)
    static let emeraldDeep = Color(red: 0.03, green: 0.14, blue: 0.10)
    static let gold = Color(red: 0.77, green: 0.63, blue: 0.35)
    static let goldBright = Color(red: 0.90, green: 0.76, blue: 0.40)
    static let goldDark = Color(red: 0.68, green: 0.54, blue: 0.28)
    static let muted = Color(red: 0.44, green: 0.44, blue: 0.42)
    static let rust = Color(red: 0.62, green: 0.28, blue: 0.22)
}

struct VehiclesView: View {
    @Environment(BookingStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(TeslaAuthService.self) private var teslaAuth
    @State private var showingAddVehicle = false
    @State private var showingConnectTesla = false
    @State private var vehiclePendingEdit: Vehicle?
    @State private var vehiclePendingDelete: Vehicle?

    var body: some View {
        ZStack {
            VehiclesTabBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    connectTeslaCard

                    garageSection

                    infoRibbon

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VehiclesTabPalette.rust)
                    }

                    if let syncError = store.documentCloudSyncError {
                        Text(syncError)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VehiclesTabPalette.rust)
                    }

                    if store.canAddVehicle {
                        addVehicleCTA
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
            .refreshable {
                await store.syncVehicleDocumentsWithAdmin(
                    customerID: auth.supabaseUserID,
                    preferredEmail: auth.displayEmail
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.syncVehicleDocumentsWithAdmin(
                customerID: auth.supabaseUserID,
                preferredEmail: auth.displayEmail
            )
        }
        // While any vehicle is awaiting review, poll so Approve/Reject shows without leaving the tab.
        .task(id: store.vehicles.map(\.documentApprovalStatus)) {
            let pending = store.vehicles.contains { $0.documentApprovalStatus == .pendingReview }
            guard pending else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                let stillPending = store.vehicles.contains {
                    $0.documentApprovalStatus == .pendingReview
                }
                guard stillPending else { return }
                await store.syncVehicleDocumentsWithAdmin(
                    customerID: auth.supabaseUserID,
                    preferredEmail: auth.displayEmail
                )
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
        .sheet(isPresented: $showingConnectTesla) {
            NavigationStack {
                ConnectTeslaView()
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VehiclesTabPalette.goldBright)
                .shadow(color: VehiclesTabPalette.gold.opacity(0.35), radius: 4, y: 1)

            Text("Vehicles")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(VehiclesTabPalette.emerald)

            Text("Your garage, curated for concierge service.")
                .font(.system(size: 14, weight: .regular, design: .serif).italic())
                .foregroundStyle(VehiclesTabPalette.goldDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            VehiclesGoldOrnament()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Connect Tesla

    private var connectTeslaCard: some View {
        Group {
            if teslaAuth.isConnected {
                VehiclesStationeryCard {
                    HStack(spacing: 14) {
                        VehiclesBoltMedallion()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tesla connected")
                                .font(.system(size: 17, weight: .semibold, design: .serif))
                                .foregroundStyle(VehiclesTabPalette.emerald)
                            if let email = teslaAuth.connectedEmail {
                                Text(email)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(VehiclesTabPalette.muted)
                            }
                        }

                        Spacer(minLength: 8)

                        Button("Disconnect", role: .destructive) {
                            teslaAuth.disconnect()
                            store.removeTeslaLinkedVehicles()
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                }
            } else if teslaAuth.isConnectAvailable {
                Button {
                    showingConnectTesla = true
                } label: {
                    VehiclesStationeryCard {
                        HStack(spacing: 14) {
                            VehiclesBoltMedallion()

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Connect Tesla")
                                    .font(.system(size: 17, weight: .semibold, design: .serif))
                                    .foregroundStyle(VehiclesTabPalette.emerald)
                                Text("Import vehicles from your Tesla account")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(VehiclesTabPalette.muted)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VehiclesTabPalette.gold)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Garage

    private var garageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VehiclesTabPalette.gold)

                Text("Your garage")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(VehiclesTabPalette.goldDark)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                VehiclesTabPalette.gold.opacity(0.55),
                                VehiclesTabPalette.gold.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }

            if store.vehicles.isEmpty {
                Button {
                    showingAddVehicle = true
                } label: {
                    VehiclesStationeryCard {
                        VStack(spacing: 12) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(VehiclesTabPalette.gold)
                                .frame(width: 52, height: 52)
                                .background(
                                    Circle()
                                        .fill(VehiclesTabPalette.emeraldMid)
                                        .overlay(Circle().stroke(VehiclesTabPalette.gold.opacity(0.7), lineWidth: 1.2))
                                )

                            Text("Your garage awaits")
                                .font(.system(size: 20, weight: .semibold, design: .serif))
                                .foregroundStyle(VehiclesTabPalette.emerald)

                            Text("Register your EV for concierge pickup, or connect Tesla to sync range.")
                                .font(.system(size: 13))
                                .foregroundStyle(VehiclesTabPalette.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)

                            GoldBeadDivider(width: 100)

                            HStack(spacing: 6) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Register your vehicle")
                                    .font(.system(size: 15, weight: .semibold, design: .serif))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(VehiclesTabPalette.goldDark)
                            .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.plain)
                .brandCardSettle()
            } else {
                ForEach(store.vehicles) { vehicle in
                    vehicleCard(vehicle)
                }
            }
        }
    }

    private func vehicleCard(_ vehicle: Vehicle) -> some View {
        VehiclesStationeryCard(padding: 14) {
            VStack(spacing: 12) {
                VehicleGarage3DStage(
                    vehicle: vehicle,
                    height: 200,
                    autoSpin: true,
                    showsHint: true
                )

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vehicle.displayName)
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(VehiclesTabPalette.emerald)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)

                        Text("\(vehicle.make) \(vehicle.model) · \(vehicle.licensePlateDisplay)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(VehiclesTabPalette.muted)
                            .lineLimit(1)

                        if vehicle.smokingInVehicle {
                            Label("Smoking in vehicle", systemImage: "smoke.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(VehiclesTabPalette.gold)
                                .labelStyle(.titleAndIcon)
                        }

                        documentStatusChip(vehicle.documentApprovalStatus)

                        HStack(spacing: 14) {
                            Label("\(vehicle.estimatedRangeMiles) mi left", systemImage: "ev.charger.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    vehicle.meetsMinimumRange
                                        ? VehiclesTabPalette.emeraldMid
                                        : Color.orange
                                )

                            Label("\(vehicle.currentChargePercent)%", systemImage: "battery.100")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VehiclesTabPalette.emeraldMid)
                        }
                        .labelStyle(.titleAndIcon)

                        if let vin = vehicle.teslaVIN {
                            Text("VIN \(vin)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(VehiclesTabPalette.muted.opacity(0.85))
                        }
                    }

                    Spacer(minLength: 4)

                    VStack(spacing: 10) {
                        Button {
                            vehiclePendingEdit = vehicle
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VehiclesTabPalette.goldBright)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(VehiclesTabPalette.emeraldMid)
                                        .overlay(Circle().stroke(VehiclesTabPalette.gold.opacity(0.85), lineWidth: 1.2))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(vehicle.displayName)")

                        Button {
                            vehiclePendingDelete = vehicle
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VehiclesTabPalette.rust)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(VehiclesTabPalette.card)
                                        .overlay(Circle().stroke(VehiclesTabPalette.gold.opacity(0.55), lineWidth: 1.2))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(vehicle.displayName)")
                    }
                }

                // Card footer seal
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(VehiclesTabPalette.gold.opacity(0.35))
                        .frame(height: 0.8)
                    ZStack {
                        Circle()
                            .stroke(VehiclesTabPalette.gold.opacity(0.55), lineWidth: 1)
                            .frame(width: 22, height: 22)
                        if vehicle.isTesla || vehicle.isTeslaLinked {
                            Text("T")
                                .font(.system(size: 11, weight: .bold, design: .serif))
                                .foregroundStyle(VehiclesTabPalette.goldDark)
                        } else {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(VehiclesTabPalette.gold)
                        }
                    }
                    Rectangle()
                        .fill(VehiclesTabPalette.gold.opacity(0.35))
                        .frame(height: 0.8)
                }
                .padding(.top, 2)
            }
        }
        .contextMenu {
            Button("Edit vehicle") { vehiclePendingEdit = vehicle }
            Button("Delete vehicle", role: .destructive) { vehiclePendingDelete = vehicle }
        }
    }

    private func documentStatusChip(_ status: VehicleDocumentApprovalStatus) -> some View {
        let color: Color = {
            switch status {
            case .approved: return VehiclesTabPalette.emeraldMid
            case .pendingReview: return VehiclesTabPalette.goldDark
            case .rejected: return VehiclesTabPalette.rust
            case .incomplete: return VehiclesTabPalette.muted
            }
        }()

        return HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(status.customerLabel)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        )
    }

    // MARK: - Info ribbon

    private var infoRibbon: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(VehiclesTabPalette.emeraldMid)
                    .frame(width: 22, height: 22)
                Text("i")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Registration photo and policy number need admin approval before booking. Pickup also requires at least \(Pricing.minimumRangeMiles) miles of range.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(VehiclesTabPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(store.vehicles.count) of \(Pricing.maxSavedVehicles) vehicles saved.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VehiclesTabPalette.goldDark)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VehiclesTabPalette.card.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VehiclesTabPalette.gold.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Add Vehicle CTA

    private var addVehicleCTA: some View {
        Button {
            showingAddVehicle = true
        } label: {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                VehiclesTabPalette.emeraldMid,
                                VehiclesTabPalette.emeraldDeep,
                                VehiclesTabPalette.emeraldMid
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), .clear, Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)

                VStack(spacing: 6) {
                    Text("Add Vehicle")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(VehiclesTabPalette.goldBright)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 5) {
                        Capsule()
                            .fill(VehiclesTabPalette.gold.opacity(0.55))
                            .frame(width: 28, height: 1)
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(VehiclesTabPalette.goldBright)
                        Capsule()
                            .fill(VehiclesTabPalette.gold.opacity(0.55))
                            .frame(width: 28, height: 1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

                Circle()
                    .fill(VehiclesTabPalette.goldBright.opacity(0.95))
                    .frame(width: 5, height: 5)
                    .blur(radius: 0.4)
                    .shadow(color: VehiclesTabPalette.goldBright.opacity(0.9), radius: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 18)
                    .padding(.top, 8)
                    .allowsHitTesting(false)

                Circle()
                    .fill(VehiclesTabPalette.goldBright.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .shadow(color: VehiclesTabPalette.goldBright.opacity(0.8), radius: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 22)
                    .padding(.bottom, 10)
                    .allowsHitTesting(false)
            }
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                VehiclesTabPalette.goldBright,
                                VehiclesTabPalette.gold,
                                VehiclesTabPalette.goldBright.opacity(0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.8
                    )
            )
            .shadow(color: VehiclesTabPalette.emeraldDeep.opacity(0.35), radius: 14, y: 6)
            .shadow(color: VehiclesTabPalette.gold.opacity(0.22), radius: 10, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel("Add Vehicle")
    }
}

// MARK: - Thumbnail

private struct VehicleGarageThumbnail: View {
    let vehicle: Vehicle

    var body: some View {
        ZStack {
            if vehicle.registrationPhotoData != nil {
                CachedDataImage(data: vehicle.registrationPhotoData, maxPixelSide: 160, contentMode: .fill)
            } else if let url = compositorURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .padding(4)
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                            .tint(VehiclesTabPalette.gold)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 58, height: 58)
        .background(VehiclesTabPalette.creamDeep)
        .clipShape(Circle())
        .overlay(Circle().stroke(VehiclesTabPalette.gold.opacity(0.75), lineWidth: 1.4))
    }

    private var placeholder: some View {
        Image(systemName: vehicle.isTeslaLinked ? "bolt.car.fill" : "car.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(VehiclesTabPalette.gold)
    }

    private var compositorURL: URL? {
        guard let modelCode = vehicle.teslaModelCode else { return nil }
        let paint = vehicle.paintColor.compositorCode
        let string = "https://static-assets.tesla.com/v1/compositor/?model=\(modelCode)&view=STUD_3QTR&size=400&bkba_opt=1&options=\(paint),$W39B"
        return URL(string: string)
    }
}

// MARK: - Shared chrome

private struct VehiclesTabBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [VehiclesTabPalette.cream, VehiclesTabPalette.creamDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft parchment glow
            Ellipse()
                .fill(VehiclesTabPalette.gold.opacity(0.07))
                .frame(width: 280, height: 180)
                .blur(radius: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -20)
                .allowsHitTesting(false)

            // Same botanical leaf format as Home.
            CherchargeBotanicalBranches()
        }
    }
}

private struct VehiclesStationeryCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(VehiclesTabPalette.card))
            .overlay(shape.stroke(VehiclesTabPalette.gold.opacity(0.42), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct VehiclesBoltMedallion: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [VehiclesTabPalette.emeraldMid, VehiclesTabPalette.emeraldDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(VehiclesTabPalette.gold.opacity(0.85), lineWidth: 1.4)
            Image(systemName: "bolt.car.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VehiclesTabPalette.goldBright)
        }
        .frame(width: 48, height: 48)
        .shadow(color: VehiclesTabPalette.emeraldDeep.opacity(0.2), radius: 6, y: 2)
    }
}

private struct VehiclesGoldOrnament: View {
    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [VehiclesTabPalette.gold.opacity(0), VehiclesTabPalette.gold.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 64, height: 1)
            Image(systemName: "diamond.fill")
                .font(.system(size: 6))
                .foregroundStyle(VehiclesTabPalette.goldBright)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [VehiclesTabPalette.gold.opacity(0.8), VehiclesTabPalette.gold.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 64, height: 1)
        }
    }
}

#Preview {
    NavigationStack {
        VehiclesView()
    }
    .environment(BookingStore())
    .environment(TeslaAuthService())
}
