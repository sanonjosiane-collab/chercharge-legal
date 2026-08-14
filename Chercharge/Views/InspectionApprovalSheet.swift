//
//  InspectionApprovalSheet.swift
//  Chercharge
//
//  Home popup for quick pre-trip / post-trip inspection review (15s auto-approve).
//

import SwiftUI
import UIKit

struct InspectionApprovalSheet: View {
    @Environment(BookingStore.self) private var store
    @Binding var path: NavigationPath
    let phase: InspectionPhase
    var onDismiss: () -> Void

    @State private var isApproving = false
    @State private var errorMessage: String?

    private var job: ChargeJob? {
        store.activeJob
    }

    private var isReady: Bool {
        guard let job else { return false }
        switch phase {
        case .preTrip: return job.needsCustomerApproval && job.preTripInspection != nil
        case .postTrip: return job.needsReturnApproval && job.postTripInspection != nil
        }
    }

    private var inspection: VehicleInspection? {
        guard let job else { return nil }
        switch phase {
        case .preTrip: return job.preTripInspection
        case .postTrip: return job.postTripInspection
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let job, isReady, let inspection {
                    content(job: job, inspection: inspection)
                } else {
                    ContentUnavailableView(
                        "Inspection updated",
                        systemImage: "checkmark.seal",
                        description: Text(
                            phase == .preTrip
                                ? "Pickup approval is no longer needed."
                                : "Return approval is no longer needed."
                        )
                    )
                }
            }
            .brandBackground()
            .navigationTitle(phase == .preTrip ? "Inspection ready" : "Return inspection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDismiss() }
                        .foregroundStyle(ConciergeLuxe.emerald)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func content(job: ChargeJob, inspection: VehicleInspection) -> some View {
        let windowSeconds = Int(ChargeJob.customerApprovalWindow)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                countdownBanner(for: job)

                Text("Quick look")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.emerald)

                Text(
                    phase == .preTrip
                        ? "Review the driver photos, then approve pickup. If you do nothing, we auto-approve in \(windowSeconds) seconds."
                        : "Review the return photos, then approve. If you do nothing, we auto-approve in \(windowSeconds) seconds."
                )
                .font(.system(size: 13))
                .foregroundStyle(ConciergeLuxe.muted)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    thumb("Front", data: inspection.frontPhotoData, urlString: inspection.storageURLs.frontPhotoURL)
                    thumb("Rear", data: inspection.rearPhotoData, urlString: inspection.storageURLs.rearPhotoURL)
                    thumb("Left", data: inspection.leftSidePhotoData, urlString: inspection.storageURLs.leftSidePhotoURL)
                    thumb("Roof", data: inspection.roofPhotoData, urlString: inspection.storageURLs.roofPhotoURL)
                }

                VStack(alignment: .leading, spacing: 8) {
                    detailLine("Vehicle", job.vehicle.displayName)
                    detailLine("Driver", inspection.driverName)
                    detailLine("Battery", "\(inspection.batteryPercent)%")
                    detailLine("Damage", inspection.damageChecklist.summary)
                    detailLine("Tires", inspection.tireCondition.title)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ConciergeLuxe.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ConciergeLuxe.gold.opacity(0.25), lineWidth: 1)
                        )
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote))
                        .foregroundStyle(.red)
                }

                Button {
                    approve(jobID: job.id)
                } label: {
                    if isApproving {
                        ProgressView().tint(ConciergeLuxe.gold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    } else {
                        Text(phase == .preTrip ? "Approve pickup" : "Approve return")
                            .font(.system(.headline, design: .serif).weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isApproving)

                Button {
                    onDismiss()
                    path.append(AppRoute.reviewInspection(jobID: job.id, phase: phase))
                } label: {
                    Text("See full inspection")
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.emerald)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Text("Auto-approves when the timer reaches 0:00.")
                    .font(.system(.caption))
                    .foregroundStyle(ConciergeLuxe.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .padding(.bottom, 12)
        }
    }

    private func countdownBanner(for job: ChargeJob) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = job.approvalSecondsRemaining
            let urgent = remaining <= 30

            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(urgent ? Color(red: 0.75, green: 0.25, blue: 0.15) : ConciergeLuxe.gold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-approves in")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ConciergeLuxe.muted)
                    Text(job.approvalCountdownLabel)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(urgent ? Color(red: 0.75, green: 0.25, blue: 0.15) : ConciergeLuxe.emerald)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(urgent ? Color(red: 0.98, green: 0.93, blue: 0.90) : ConciergeLuxe.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                urgent
                                    ? Color(red: 0.75, green: 0.25, blue: 0.15).opacity(0.35)
                                    : ConciergeLuxe.gold.opacity(0.35),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    private func thumb(_ label: String, data: Data, urlString: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ConciergeLuxe.emerald.opacity(0.08))

                if let image = ImageDecodeCache.image(for: data, maxPixelSide: 400) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let urlString, let url = URL(string: urlString), !urlString.hasPrefix("local://") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(ConciergeLuxe.emerald.opacity(0.55))
                        default:
                            ProgressView()
                                .tint(ConciergeLuxe.gold)
                        }
                    }
                } else {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(ConciergeLuxe.emerald.opacity(0.55))
                }
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ConciergeLuxe.gold.opacity(0.25), lineWidth: 1)
            )

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ConciergeLuxe.gold)
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(ConciergeLuxe.muted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)
                .multilineTextAlignment(.trailing)
        }
    }

    private func approve(jobID: UUID) {
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
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Compact home banner when approval is pending and the sheet was dismissed.
struct InspectionApprovalBanner: View {
    let job: ChargeJob
    let phase: InspectionPhase
    let onReview: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Button(action: onReview) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(ConciergeLuxe.emeraldGradient)
                            .frame(width: 40, height: 40)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ConciergeLuxe.gold)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase == .preTrip ? "Inspection ready for review" : "Return inspection ready")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundStyle(ConciergeLuxe.emerald)
                        Text("Auto-approves in \(job.approvalCountdownLabel)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ConciergeLuxe.muted)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)

                    Text("Review")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(ConciergeLuxe.gold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(ConciergeLuxe.emeraldGradient)
                                .overlay(Capsule().stroke(ConciergeLuxe.gold.opacity(0.55), lineWidth: 1))
                        )
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(ConciergeLuxe.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(ConciergeLuxe.gold.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: ConciergeLuxe.charcoal.opacity(0.08), radius: 10, y: 4)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
