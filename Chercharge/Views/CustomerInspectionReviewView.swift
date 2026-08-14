//
//  CustomerInspectionReviewView.swift
//  Chercharge
//

import SwiftUI
import UIKit

struct CustomerInspectionReviewView: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let jobID: UUID
    let phase: InspectionPhase

    @State private var errorMessage: String?
    @State private var isApproving = false

    private var job: ChargeJob? {
        if let active = store.activeJob, active.id == jobID { return active }
        if let completed = store.lastCompletedJob, completed.id == jobID { return completed }
        return store.pastJobs.first { $0.id == jobID }
    }

    private var inspection: VehicleInspection? {
        guard let job else { return nil }
        switch phase {
        case .preTrip: return job.preTripInspection
        case .postTrip: return job.postTripInspection
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let job, let inspection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(phase.title)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Brand.ink)
                        Text("Stored with booking · \(inspection.uploadedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Pending upload")")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Brand.muted)
                    }

                    mediaBlock(title: "Exterior", rows: [
                        ("Front", inspection.frontPhotoData, inspection.storageURLs.frontPhotoURL, false),
                        ("Rear", inspection.rearPhotoData, inspection.storageURLs.rearPhotoURL, false),
                        ("Left side", inspection.leftSidePhotoData, inspection.storageURLs.leftSidePhotoURL, false),
                        ("Roof", inspection.roofPhotoData, inspection.storageURLs.roofPhotoURL, false)
                    ])

                    mediaBlock(title: "Interior & odometer", rows: [
                        ("Interior video", inspection.interiorVideoData, inspection.storageURLs.interiorVideoURL, true),
                        ("Odometer", inspection.odometerPhotoData, inspection.storageURLs.odometerPhotoURL, false)
                    ])

                    detailsCard(job: job, inspection: inspection)

                    if phase == .preTrip, job.needsCustomerApproval {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundStyle(Brand.gold)
                                Text("Auto-approves in \(job.approvalCountdownLabel)")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Brand.greenDeep)
                                    .monospacedDigit()
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Brand.card)
                            )
                        }

                        Button {
                            approve()
                        } label: {
                            if isApproving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Approve pickup")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isApproving)

                        Text("Confirm pickup within 15 seconds — or we’ll auto-approve so the driver can continue.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Brand.muted)
                    }

                    if phase == .postTrip, job.needsReturnApproval {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundStyle(Brand.gold)
                                Text("Auto-approves in \(job.approvalCountdownLabel)")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Brand.greenDeep)
                                    .monospacedDigit()
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Brand.card)
                            )
                        }

                        Button {
                            approve()
                        } label: {
                            if isApproving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Approve return")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isApproving)

                        Text("Confirm the return inspection within 15 seconds — or we’ll auto-approve.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Brand.muted)
                    }
                } else {
                    ContentUnavailableView(
                        "No inspection yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Uploaded inspection media will appear here.")
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .brandBackground()
        .navigationTitle(phase == .preTrip ? "Review inspection" : "Post-trip report")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func mediaBlock(title: String, rows: [(String, Data, String?, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Brand.ink)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.0)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Brand.muted)

                    if row.3 {
                        if let urlString = row.2, let url = URL(string: urlString),
                           !urlString.hasPrefix("local://") {
                            Label("Interior video available", systemImage: "video.fill")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Brand.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.95)))
                            Link("Open video", destination: url)
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                                .foregroundStyle(Brand.gold)
                        } else {
                            Label(
                                "Interior video on file (\(max(row.1.count / 1024, 1)) KB)",
                                systemImage: "video.fill"
                            )
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Brand.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.95)))
                        }
                    } else if let image = UIImage(data: row.1), !row.1.isEmpty {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if let urlString = row.2, let url = URL(string: urlString),
                              !urlString.hasPrefix("local://") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            case .failure:
                                Label("Photo unavailable", systemImage: "exclamationmark.triangle")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(Brand.muted)
                            default:
                                ProgressView()
                                    .tint(Brand.gold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 120)
                            }
                        }
                    } else {
                        Label("No photo yet", systemImage: "photo")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Brand.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.95)))
                    }
                }
            }
        }
    }

    private func detailsCard(job: ChargeJob, inspection: VehicleInspection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            detail("Battery percentage", "\(inspection.batteryPercent)%")
            detail("Driver name", inspection.driverName)
            detail("Date & time", inspection.capturedAt.formatted(date: .abbreviated, time: .standard))
            detail("Pickup location", job.pickup.address)
            detail("GPS", inspection.pickupCoordinateLabel)
            detail("Tire condition", inspection.tireCondition.title)
            detail("Existing damage", inspection.damageChecklist.summary)
            if let front = inspection.storageURLs.frontPhotoURL {
                detail(
                    "Storage",
                    front.hasPrefix("local://") ? "Saved on device" : "Uploaded to secure storage"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.95)))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Brand.muted)
            Text(value)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Brand.ink)
        }
    }

    private func approve() {
        isApproving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isApproving = false }
            do {
                switch phase {
                case .preTrip:
                    try await store.approvePickup(jobID: jobID)
                case .postTrip:
                    try await store.approveReturn(jobID: jobID)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        CustomerInspectionReviewView(jobID: UUID(), phase: .preTrip)
    }
    .environment(BookingStore())
}
