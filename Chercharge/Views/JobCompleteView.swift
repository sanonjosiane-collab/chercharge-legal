//
//  JobCompleteView.swift
//  Chercharge
//
//  Trip completion receipt — tip, rate, share card.
//

import SwiftUI

struct JobCompleteView: View {
    @Environment(BookingStore.self) private var store
    @Binding var path: NavigationPath
    let jobID: UUID
    var onBackHome: (() -> Void)? = nil

    @State private var tipSelection: Decimal = 0
    @State private var rating: Int = 5
    @State private var feedbackSaved = false
    @State private var feedbackError: String?

    private var job: ChargeJob? {
        if store.lastCompletedJob?.id == jobID { return store.lastCompletedJob }
        return store.pastJobs.first { $0.id == jobID }
    }

    private let tipOptions: [Decimal] = [0, 5, 10, 15]

    var body: some View {
        ZStack {
            ConciergeLuxeBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    headerBlock
                        .brandLeafFade()

                    if let job {
                        receiptCard(job)
                            .brandCardSettle(delay: 0.08)

                        if job.hasSubmittedFeedback || feedbackSaved {
                            thanksCard(job)
                                .brandCardSettle(delay: 0.12)
                        } else {
                            tipRateCard
                                .brandCardSettle(delay: 0.12)
                        }

                        shareCard(job)
                            .brandCardSettle(delay: 0.16)

                        if job.canCompareInspections {
                            compareButton(job)
                        }
                    }

                    backHomeButton
                        .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let job, job.hasSubmittedFeedback {
                feedbackSaved = true
                tipSelection = job.tipAmount ?? 0
                rating = job.driverRating ?? 5
            }
        }
        .alert("Couldn’t save feedback", isPresented: Binding(
            get: { feedbackError != nil },
            set: { if !$0 { feedbackError = nil } }
        )) {
            Button("OK", role: .cancel) { feedbackError = nil }
        } message: {
            Text(feedbackError ?? "")
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ConciergeLuxe.gold)

            Text("You're all set")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)

            Text("Your EV is back and charged.")
                .font(.system(size: 15))
                .foregroundStyle(ConciergeLuxe.muted)

            GoldBeadDivider()
        }
        .frame(maxWidth: .infinity)
    }

    private func receiptCard(_ job: ChargeJob) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RECEIPT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(ConciergeLuxe.goldDark)
                Spacer()
                Text(job.displayReceiptNumber)
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.emerald)
            }

            receiptRow("Vehicle", job.vehicle.displayName)
            receiptRow("Charge", "\(job.startingChargePercent)% → \(job.targetChargePercent)%")
            receiptRow("Valet", store.assignedDriverName)
            receiptRow("Service", job.formattedPrice)
            if let tip = job.formattedTip {
                receiptRow("Tip", tip)
            }

            Rectangle()
                .fill(ConciergeLuxe.gold.opacity(0.28))
                .frame(height: 1)

            HStack {
                Text("Total")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.emerald)
                Spacer()
                Text(job.hasSubmittedFeedback ? job.formattedTotalWithTip : job.formattedPrice)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.emerald)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ConciergeLuxe.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(ConciergeLuxe.gold.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: ConciergeLuxe.charcoal.opacity(0.06), radius: 14, y: 4)
        )
    }

    private var tipRateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rate your valet")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)

            Text(store.assignedDriverName)
                .font(.system(size: 13))
                .foregroundStyle(ConciergeLuxe.muted)

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(BrandMotion.soft) { rating = star }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 22))
                            .foregroundStyle(ConciergeLuxe.gold)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Add a tip")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)
                .padding(.top, 4)

            HStack(spacing: 8) {
                ForEach(tipOptions, id: \.self) { amount in
                    let selected = tipSelection == amount
                    Button {
                        withAnimation(BrandMotion.soft) { tipSelection = amount }
                    } label: {
                        Text(amount == 0 ? "None" : Pricing.format(amount))
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(selected ? ConciergeLuxe.card : ConciergeLuxe.emerald)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                Capsule()
                                    .fill(selected ? AnyShapeStyle(ConciergeLuxe.emeraldGradient) : AnyShapeStyle(ConciergeLuxe.ivoryDeep))
                                    .overlay(
                                        Capsule().stroke(ConciergeLuxe.gold.opacity(selected ? 0.55 : 0.28), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                do {
                    try store.submitTripFeedback(jobID: jobID, tipAmount: tipSelection, rating: rating)
                    withAnimation(BrandMotion.settle) { feedbackSaved = true }
                } catch {
                    feedbackError = error.localizedDescription
                }
            } label: {
                Text("Submit tip & rating")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
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
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ConciergeLuxe.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(ConciergeLuxe.gold.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func thanksCard(_ job: ChargeJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thank you")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)
            Text(
                job.driverRating.map { "You rated \(store.assignedDriverName) \($0) of 5." }
                    ?? "Your feedback helps keep Chercharge refined."
            )
            .font(.system(size: 13))
            .foregroundStyle(ConciergeLuxe.muted)
            if let tip = job.formattedTip {
                Text("Tip \(tip) included on this receipt.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.goldDark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ConciergeLuxe.ivoryDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ConciergeLuxe.gold.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func shareCard(_ job: ChargeJob) -> some View {
        let message = ReferralGift.tripShareMessage(job: job, driverName: store.assignedDriverName)
        return VStack(alignment: .leading, spacing: 14) {
            TripSharePreviewCard(job: job, driverName: store.assignedDriverName)

            ShareLink(item: message) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share this charge")
                }
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule()
                        .stroke(ConciergeLuxe.gold.opacity(0.45), lineWidth: 1.2)
                        .background(Capsule().fill(ConciergeLuxe.card))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func compareButton(_ job: ChargeJob) -> some View {
        Button {
            path.append(AppRoute.compareInspections(jobID: job.id))
        } label: {
            Text(
                job.inspectionComparison?.hasNewDamage == true
                    ? "Review inspection comparison"
                    : "Compare pickup & return"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ConciergeLuxe.emerald)
        }
        .buttonStyle(.plain)
    }

    private var backHomeButton: some View {
        Button {
            store.clearCompletedJob()
            if let onBackHome {
                onBackHome()
            } else {
                path = NavigationPath()
            }
        } label: {
            Text("Back to home")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.gold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(ConciergeLuxe.emeraldGradient)
                        .overlay(Capsule().stroke(ConciergeLuxe.gold.opacity(0.45), lineWidth: 1.2))
                )
        }
        .buttonStyle(.plain)
    }

    private func receiptRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(ConciergeLuxe.muted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Branded share preview — cream / emerald / gold, not generic social chrome.
struct TripSharePreviewCard: View {
    let job: ChargeJob
    let driverName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chercharge")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.emerald)
                Spacer()
                Image(systemName: "bolt.fill")
                    .foregroundStyle(ConciergeLuxe.gold)
            }
            Text("Concierge charge complete")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ConciergeLuxe.muted)
            GoldBeadDivider(width: 90)
            Text(job.vehicle.displayName)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)
            Text("\(job.startingChargePercent)% → \(job.targetChargePercent)% · \(driverName)")
                .font(.system(size: 12))
                .foregroundStyle(ConciergeLuxe.muted)
            Text(job.formattedPrice)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(ConciergeLuxe.goldDark)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ConciergeLuxe.ivory, ConciergeLuxe.ivoryDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ConciergeLuxe.gold.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack {
        JobCompleteView(path: $path, jobID: UUID())
    }
    .environment(BookingStore())
}
