//
//  TrackingView.swift
//  Chercharge
//
//  Live status — matched to the Face / mock image.
//

import MapKit
import SwiftUI

struct TrackingView: View {
    @Environment(BookingStore.self) private var store
    @Binding var path: NavigationPath
    let jobID: UUID
    var onBackHome: (() -> Void)? = nil
    var onOpenProfile: (() -> Void)? = nil

    @State private var cameraPosition: MapCameraPosition = .automatic

    private let emerald = ConciergeLuxe.emerald
    private let emeraldDeep = ConciergeLuxe.emeraldDeep
    private let gold = ConciergeLuxe.gold
    private let muted = ConciergeLuxe.muted
    private let card = ConciergeLuxe.card
    private let ivory = ConciergeLuxe.ivory

    private var job: ChargeJob? {
        if let active = store.activeJob, active.id == jobID {
            return active
        }
        if let completed = store.lastCompletedJob, completed.id == jobID {
            return completed
        }
        return nil
    }

    var body: some View {
        ZStack {
            LiveStatusBackground()

            Group {
                if let job {
                    content(for: job)
                } else {
                    ContentUnavailableView(
                        "Job not found",
                        systemImage: "bolt.slash",
                        description: Text("This charge request is no longer available.")
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onChange(of: store.lastCompletedJob?.id) { _, newID in
            guard let newID, newID == jobID else { return }
            path = NavigationPath()
            path.append(AppRoute.complete(jobID: newID))
        }
    }

    private func content(for job: ChargeJob) -> some View {
        VStack(spacing: 0) {
            liveHeader

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock

                    mapCard(for: job)

                    timelineCard(for: job)

                    secondaryInspectionLinks(for: job)

                    tripDetailsCard(for: job)

                    insuredBanner
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            fitCamera(to: job)
        }
        .onChange(of: job.status) { _, _ in
            fitCamera(to: job)
        }
    }

    // MARK: - Header

    private var liveHeader: some View {
        ZStack {
            HStack {
                Button {
                    if let onBackHome {
                        onBackHome()
                    } else {
                        path = NavigationPath()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Home")
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                    }
                    .foregroundStyle(emerald)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(card)
                            .overlay(Capsule().stroke(gold.opacity(0.45), lineWidth: 1))
                            .shadow(color: ConciergeLuxe.charcoal.opacity(0.06), radius: 6, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Home")

                Spacer(minLength: 0)

                Button {
                    onOpenProfile?()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [emerald, emeraldDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Circle()
                            .stroke(gold.opacity(0.7), lineWidth: 1.5)
                        if let uiImage = ImageDecodeCache.image(for: store.profilePhotoData, maxPixelSide: 96) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(gold)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .shadow(color: gold.opacity(0.2), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(onOpenProfile == nil)
                .accessibilityLabel("Open Profile")
            }

            VStack(spacing: 3) {
                Image("CherchargeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("CHERCHARGE")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(emerald)
                    .tracking(1.6)
                Text("EV CONCIERGE")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(gold)
                    .tracking(2.0)
            }
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live status")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(emerald)

            Text("Real-time updates on your charge")
                .font(.system(size: 14))
                .foregroundStyle(emerald.opacity(0.75))

            // Gold bead divider
            HStack(spacing: 8) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [gold.opacity(0), gold.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                Circle()
                    .fill(gold)
                    .frame(width: 6, height: 6)
                    .shadow(color: gold.opacity(0.45), radius: 3)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [gold.opacity(0.7), gold.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Map

    private func mapCard(for job: ChargeJob) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return Map(position: $cameraPosition) {
            MapPolyline(coordinates: [job.pickup.coordinate, job.station.coordinate])
                .stroke(emerald, lineWidth: 5)

            Annotation("", coordinate: job.pickup.coordinate, anchor: .bottom) {
                mapCallout(
                    icon: "car.fill",
                    iconGold: false,
                    eyebrow: "PICKUP",
                    title: job.pickup.address,
                    statusPill: nil
                )
            }

            Annotation("", coordinate: job.station.coordinate, anchor: .bottom) {
                mapCallout(
                    icon: "bolt.fill",
                    iconGold: true,
                    eyebrow: "STATION",
                    title: job.station.name.replacingOccurrences(of: "—", with: " ").replacingOccurrences(of: "  ", with: " "),
                    statusPill: shortStatusPill(for: job.status)
                )
            }

            Annotation("", coordinate: carCoordinate(for: job)) {
                ZStack {
                    Circle()
                        .fill(card)
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    Circle()
                        .stroke(emerald, lineWidth: 2)
                        .frame(width: 34, height: 34)
                    Image(systemName: "car.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(emerald)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .frame(height: 260)
        .clipShape(shape)
        .overlay(shape.stroke(gold.opacity(0.28), lineWidth: 1))
        .shadow(color: ConciergeLuxe.charcoal.opacity(0.08), radius: 12, y: 4)
        .disabled(true)
    }

    private func mapCallout(
        icon: String,
        iconGold: Bool,
        eyebrow: String,
        title: String,
        statusPill: String?
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(emerald)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconGold ? gold : .white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(gold)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(emerald)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let statusPill {
                    Text(statusPill)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(emerald)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.82, green: 0.92, blue: 0.86))
                        )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 168, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(card.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(gold.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        )
    }

    private func shortStatusPill(for status: JobStatus) -> String {
        switch status {
        case .requested: return "Requested"
        case .driverEnRoute, .driverArrived, .awaitingCustomerApproval: return "En route"
        case .pickedUp: return "In transit"
        case .charging: return "Charging"
        case .returning: return "Returning"
        case .awaitingPostTripInspection: return "Inspecting"
        case .awaitingReturnApproval: return "Review return"
        case .delivered: return "Delivered"
        }
    }

    // MARK: - Timeline

    private func timelineCard(for job: ChargeJob) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(JobStatus.allCases, id: \.self) { status in
                timelineRow(status: status, job: job)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            shape
                .fill(card)
                .overlay(shape.stroke(gold.opacity(0.22), lineWidth: 1))
                .shadow(color: ConciergeLuxe.charcoal.opacity(0.07), radius: 14, y: 5)
                .shadow(color: gold.opacity(0.06), radius: 8, y: 2)
        )
    }

    private func timelineRow(status: JobStatus, job: ChargeJob) -> some View {
        let reached = status.stepIndex <= job.status.stepIndex
        let current = status == job.status
        let completed = reached && !current
        let isLast = status == .delivered

        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                timelineDot(completed: completed, current: current, pending: !reached)
                if !isLast {
                    Rectangle()
                        .fill(status.stepIndex < job.status.stepIndex ? emerald : Color.gray.opacity(0.22))
                        .frame(width: 2)
                        .frame(minHeight: current && job.needsAnyInspectionApproval ? 52 : 28)
                }
            }
            .frame(width: 22)

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(status.title)
                            .font(.system(size: 14, weight: current ? .semibold : .regular, design: .serif))
                            .foregroundStyle(reached ? emerald : muted.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)

                        if completed, let time = timeLabel(for: status, job: job) {
                            Text(time)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(emerald.opacity(0.7))
                        }
                    }

                    if current {
                        Text(activeDetail(for: job))
                            .font(.system(size: 12))
                            .foregroundStyle(emerald.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 4)

                if current && job.needsAnyInspectionApproval {
                    VStack(alignment: .trailing, spacing: 6) {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(job.approvalCountdownLabel)
                                .font(.system(size: 12, weight: .bold, design: .serif))
                                .foregroundStyle(gold)
                                .monospacedDigit()
                        }

                        Button {
                            let phase: InspectionPhase = job.needsReturnApproval ? .postTrip : .preTrip
                            path.append(AppRoute.reviewInspection(jobID: job.id, phase: phase))
                        } label: {
                            Text("Review")
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .foregroundStyle(gold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [emerald, emeraldDeep],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(Capsule().stroke(gold.opacity(0.65), lineWidth: 1))
                                )
                                .shadow(color: emerald.opacity(0.3), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 10)
        }
    }

    private func timelineDot(completed: Bool, current: Bool, pending: Bool) -> some View {
        ZStack {
            if current {
                Circle()
                    .fill(emerald.opacity(0.18))
                    .frame(width: 22, height: 22)
            }

            if completed {
                Circle()
                    .fill(emerald)
                    .frame(width: 16, height: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            } else if current {
                Circle()
                    .stroke(emerald, lineWidth: 2)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(emerald)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .stroke(Color.gray.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: 22, height: 22)
        .opacity(pending && !current ? 0.85 : 1)
    }

    private func activeDetail(for job: ChargeJob) -> String {
        if job.needsCustomerApproval {
            return "Quick look on Home, or Review here. Auto-approves in \(job.approvalCountdownLabel)."
        }
        if job.needsReturnApproval {
            return "Return photos ready. Auto-approves in \(job.approvalCountdownLabel)."
        }
        return job.status.detail
    }

    private func timeLabel(for status: JobStatus, job: ChargeJob) -> String? {
        let minutes = status.stepIndex * 4
        let date = job.createdAt.addingTimeInterval(Double(minutes) * 60)
        return date.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func secondaryInspectionLinks(for job: ChargeJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if job.preTripInspection != nil, !job.needsCustomerApproval {
                Button {
                    path.append(AppRoute.reviewInspection(jobID: job.id, phase: .preTrip))
                } label: {
                    Label("View pre-trip inspection", systemImage: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(emerald)
                }
            }

            if job.postTripInspection != nil {
                Button {
                    path.append(AppRoute.reviewInspection(jobID: job.id, phase: .postTrip))
                } label: {
                    Label("View return inspection", systemImage: "checkmark.seal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(emerald)
                }
            }

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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        job.inspectionComparison?.hasNewDamage == true
                            ? Color(red: 0.55, green: 0.22, blue: 0.08)
                            : emerald
                    )
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Trip details

    private func tripDetailsCard(for job: ChargeJob) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let plate = job.vehicle.licensePlateDisplay

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Trip details")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(emerald)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [gold.opacity(0), gold.opacity(0.65)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(gold)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [gold.opacity(0.65), gold.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }

            tripRow(icon: "car.fill", label: "Vehicle", value: "\(job.vehicle.displayName) · \(plate)")
            if job.vehicle.smokingInVehicle {
                tripRow(icon: "smoke.fill", label: "Smoking", value: "Yes — inside vehicle")
            }

            HStack(alignment: .center, spacing: 12) {
                tripIcon("person.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(gold)
                        .tracking(0.6)
                    HStack(spacing: 8) {
                        Text(store.assignedDriverName)
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(emerald)
                        if let phoneURL = URL(string: "tel:+18005550199") {
                            Link(destination: phoneURL) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(gold)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            tripRow(icon: "bolt.fill", label: "Charge", value: "\(job.startingChargePercent)% → \(job.targetChargePercent)%")
            tripRow(icon: "mappin.and.ellipse", label: "Pickup", value: job.pickup.address)
            tripRow(icon: "ev.charger.fill", label: "Station", value: job.station.name)
            tripRow(icon: "clock.fill", label: "Estimate", value: "\(job.formattedPrice) · ~\(job.estimatedMinutes) min")
        }
        .padding(18)
        .background(
            shape
                .fill(card)
                .overlay(shape.stroke(gold.opacity(0.22), lineWidth: 1))
                .shadow(color: ConciergeLuxe.charcoal.opacity(0.07), radius: 14, y: 5)
                .shadow(color: gold.opacity(0.06), radius: 8, y: 2)
        )
    }

    private func tripRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            tripIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(gold)
                    .tracking(0.6)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(emerald)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func tripIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(gold)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(ivory)
                    .overlay(Circle().stroke(gold.opacity(0.35), lineWidth: 1))
            )
    }

    // MARK: - Insured footer

    private var insuredBanner: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return ZStack(alignment: .trailing) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(emerald)
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(gold)
                }

                Text("Your vehicle is fully insured while in our care. Sit back and relax — we've got you.")
                    .font(.system(size: 13))
                    .foregroundStyle(emerald)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .background(
            shape
                .fill(Color(red: 0.94, green: 0.96, blue: 0.93).opacity(0.95))
                .overlay(shape.stroke(gold.opacity(0.22), lineWidth: 1))
        )
    }

    // MARK: - Map helpers

    private func carCoordinate(for job: ChargeJob) -> CLLocationCoordinate2D {
        let pickup = job.pickup.coordinate
        let station = job.station.coordinate
        switch job.status {
        case .requested:
            return interpolate(from: pickup, to: station, t: 0.06)
        case .driverEnRoute, .driverArrived, .awaitingCustomerApproval:
            return interpolate(from: pickup, to: station, t: 0.14)
        case .pickedUp:
            return interpolate(from: pickup, to: station, t: 0.55)
        case .charging:
            return station
        case .returning:
            return interpolate(from: station, to: pickup, t: 0.4)
        case .awaitingPostTripInspection, .awaitingReturnApproval, .delivered:
            return pickup
        }
    }

    private func interpolate(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * t,
            longitude: from.longitude + (to.longitude - from.longitude) * t
        )
    }

    private func fitCamera(to job: ChargeJob) {
        let coords = [job.pickup.coordinate, job.station.coordinate, carCoordinate(for: job)]
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.9, 0.04),
            longitudeDelta: max((maxLon - minLon) * 1.9, 0.04)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Cream showroom background

struct LiveStatusBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ConciergeLuxe.ivory, ConciergeLuxe.ivoryDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft warm glow near the top
            RadialGradient(
                colors: [
                    Color(red: 0.95, green: 0.90, blue: 0.76).opacity(0.35),
                    .clear
                ],
                center: UnitPoint(x: 0.45, y: 0.06),
                startRadius: 20,
                endRadius: 340
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack {
        TrackingView(path: $path, jobID: UUID())
    }
    .environment(BookingStore())
}
