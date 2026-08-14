//
//  AdminHomeView.swift
//  Chercharge
//
//  Admin home — high-priority document review queue (registration photo + policy).
//

import SwiftUI
import UIKit

struct AdminHomeView: View {
    @Environment(BookingStore.self) private var store
    @Environment(DocumentReviewInbox.self) private var inbox

    @State private var selectedItem: DocumentReviewItem?
    @State private var rejectionReason = ""
    @State private var showingRejectSheet = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    private var queue: [DocumentReviewItem] { inbox.pendingItems }

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Admin home",
                title: "Document review",
                subtitle: "On-device queue. Cloud submissions also appear in Chercharge Admin (Customers tab).",
                systemImage: "checkmark.shield.fill"
            )

            ConciergeCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HIGH PRIORITY QUEUE")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(queue.count)")
                            .font(.system(.largeTitle, design: .serif).weight(.bold))
                            .foregroundStyle(ConciergeLuxe.emerald)
                        Text(queue.count == 1 ? "submission awaiting review" : "submissions awaiting review")
                            .font(.system(.subheadline))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }

                    Text("Registration photo and insurance policy number are reviewed before a customer can book.")
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                }
            }

            if let toastMessage {
                Text(toastMessage)
                    .font(.system(.footnote).weight(.semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote).weight(.medium))
                    .foregroundStyle(Color.red.opacity(0.85))
            }

            if queue.isEmpty {
                ConciergeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ConciergeMedallion(systemImage: "tray", size: 52)
                        Text("No documents waiting")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(ConciergeLuxe.charcoal)
                        Text("Cloud submissions go to Chercharge Admin → Customers. This on-device list is a DEBUG fallback.")
                            .font(.system(.footnote))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }
                }
            } else {
                ForEach(queue) { item in
                    reviewCard(item)
                }
            }
        }
        .navigationTitle("Admin home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.bindDocumentInbox(inbox)
        }
        .sheet(isPresented: $showingRejectSheet) {
            rejectSheet
        }
    }

    private func reviewCard(_ item: DocumentReviewItem) -> some View {
        ConciergeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.vehicleDisplayName)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(ConciergeLuxe.emerald)
                        Text(item.licensePlateDisplay)
                            .font(.system(.footnote).weight(.medium))
                            .foregroundStyle(ConciergeLuxe.muted)
                        Text(customerLine(item))
                            .font(.system(.caption))
                            .foregroundStyle(ConciergeLuxe.muted.opacity(0.95))
                        Text("Submitted \(item.submittedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .font(.system(.caption2))
                            .foregroundStyle(ConciergeLuxe.muted.opacity(0.9))
                    }
                    Spacer(minLength: 8)
                    Text("HIGH PRIORITY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(ConciergeLuxe.goldDark)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(ConciergeLuxe.gold.opacity(0.18))
                                .overlay(Capsule().stroke(ConciergeLuxe.gold.opacity(0.55), lineWidth: 1))
                        )
                }

                HStack(spacing: 8) {
                    ForEach(item.highPriorityItems, id: \.self) { label in
                        priorityChip(label)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Registration photo", systemImage: "doc.viewfinder")
                        .font(.system(.caption).weight(.bold))
                        .foregroundStyle(ConciergeLuxe.goldDark)
                    if let ui = ImageDecodeCache.image(for: item.registrationPhotoData, maxPixelSide: 800) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(ConciergeLuxe.gold.opacity(0.45), lineWidth: 1)
                            )
                    } else {
                        Text("No registration photo on file")
                            .font(.system(.footnote))
                            .foregroundStyle(Color.orange.opacity(0.9))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Policy number", systemImage: "shield.fill")
                        .font(.system(.caption).weight(.bold))
                        .foregroundStyle(ConciergeLuxe.goldDark)
                    Text(item.insurancePolicy)
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.emerald)
                        .textSelection(.enabled)
                    if !item.insuranceCompanyName.isEmpty {
                        Text(item.insuranceCompanyName)
                            .font(.system(.footnote))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        do {
                            try store.approveDocumentReviewItem(itemID: item.id)
                            errorMessage = nil
                            toastMessage = "Approved \(item.vehicleDisplayName)"
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Text("Approve")
                            .font(.system(.subheadline, design: .serif).weight(.semibold))
                            .foregroundStyle(ConciergeLuxe.gold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(ConciergeLuxe.emerald))
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedItem = item
                        rejectionReason = ""
                        showingRejectSheet = true
                    } label: {
                        Text("Reject")
                            .font(.system(.subheadline, design: .serif).weight(.semibold))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().stroke(Color.red.opacity(0.4), lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .brandCardSettle()
    }

    private func customerLine(_ item: DocumentReviewItem) -> String {
        let name = item.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = item.customerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, !email.isEmpty { return "\(name) · \(email)" }
        if !email.isEmpty { return email }
        if !name.isEmpty { return name }
        return "Customer on this device"
    }

    private func priorityChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ConciergeLuxe.emerald)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(ConciergeLuxe.emerald.opacity(0.08))
                    .overlay(Capsule().stroke(ConciergeLuxe.gold.opacity(0.4), lineWidth: 1))
            )
    }

    private var rejectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell the customer what to fix. Registration photo and policy number are the usual issues.")
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                    TextField("Reason for rejection", text: $rejectionReason, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Reject documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRejectSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reject") {
                        guard let item = selectedItem else { return }
                        do {
                            try store.rejectDocumentReviewItem(itemID: item.id, reason: rejectionReason)
                            errorMessage = nil
                            toastMessage = "Rejected \(item.vehicleDisplayName)"
                            showingRejectSheet = false
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
