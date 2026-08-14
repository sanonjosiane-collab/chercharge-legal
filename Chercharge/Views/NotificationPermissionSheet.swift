//
//  NotificationPermissionSheet.swift
//  Chercharge
//
//  Pre-permission explanation for transactional / service notifications.
//

import SwiftUI

struct NotificationPermissionSheet: View {
    var onEnable: () async -> Void
    var onNotNow: () -> Void

    @State private var isEnabling = false

    private let transactionalExamples = [
        "Booking confirmation",
        "Booking status",
        "Pickup update",
        "Vehicle pickup confirmation",
        "Charging status",
        "Service issue",
        "Return status",
        "Vehicle returned confirmation",
        "Account security alert",
        "Important service notice",
    ]

    var body: some View {
        NavigationStack {
            ConciergeProfilePage {
                ConciergeRoyalBanner(
                    eyebrow: "Stay in the loop",
                    title: "Notifications",
                    subtitle: "Service updates for your Chercharge trips.",
                    systemImage: "bell.badge.fill"
                )

                ConciergeCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("WHY WE ASK")
                            .font(.system(.caption2).weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(ConciergeLuxe.goldDark)

                        Text("Stay updated on your Chercharge service. Enable notifications for booking, pickup, charging, return, and important account updates.")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(ConciergeLuxe.charcoal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ConciergeCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SERVICE NOTIFICATIONS MAY INCLUDE")
                            .font(.system(.caption2).weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(ConciergeLuxe.goldDark)

                        ForEach(transactionalExamples, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(ConciergeLuxe.emerald)
                                Text(item)
                                    .font(.system(.footnote))
                                    .foregroundStyle(ConciergeLuxe.muted)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                ConciergeInfoRibbon(
                    text: "Marketing offers are optional and managed separately in Settings → Offers & updates. They are not required for Chercharge service."
                )

                Button {
                    Task {
                        isEnabling = true
                        defer { isEnabling = false }
                        await onEnable()
                    }
                } label: {
                    HStack {
                        if isEnabling {
                            ProgressView().tint(.white)
                        }
                        Text(isEnabling ? "Continuing…" : "Enable Notifications")
                            .font(.system(.headline, design: .serif).weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)
                            .fill(ConciergeLuxe.emerald)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isEnabling)

                Button("Not Now") {
                    onNotNow()
                }
                .font(.system(.body, design: .serif).weight(.semibold))
                .foregroundStyle(ConciergeLuxe.goldDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .disabled(isEnabling)
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { onNotNow() }
                        .disabled(isEnabling)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isEnabling)
    }
}

#Preview {
    NotificationPermissionSheet(onEnable: {}, onNotNow: {})
}
