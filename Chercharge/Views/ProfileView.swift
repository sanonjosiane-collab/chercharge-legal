//
//  ProfileView.swift
//  Chercharge
//

import SwiftUI

struct ProfileView: View {
    @Environment(BookingStore.self) private var store

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Private suite",
                title: "Your Profile",
                subtitle: "Membership, preferences, and white-glove account details.",
                systemImage: "crown.fill"
            )

            // Identity card
            ConciergeCard {
                HStack(spacing: 16) {
                    ProfilePhotoAvatar(size: 86)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("MEMBER")
                            .font(.system(.caption2).weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(ConciergeLuxe.goldDark)

                        Text(store.profileName)
                            .font(.system(.title2, design: .serif).weight(.bold))
                            .foregroundStyle(ConciergeLuxe.charcoal)

                        Text(store.profileEmail)
                            .font(.system(.subheadline))
                            .foregroundStyle(ConciergeLuxe.muted)

                        Text(store.profilePhotoData == nil ? "Add a portrait for your suite" : "Update your portrait")
                            .font(.system(.caption))
                            .foregroundStyle(ConciergeLuxe.goldDark)
                    }
                }
            }

            sectionLabel("Account atelier")

            VStack(spacing: 12) {
                profileCard("Personal information", "Identity & portrait", "person.text.rectangle", .personalInfo)
                profileCard("Vehicles saved", "Your garage collection", "car.fill", .vehiclesSaved)
                profileCard("Saved addresses", "Private pickup estates", "mappin.and.ellipse", .savedAddresses)
                profileCard("Payment methods", "Cards & checkout", "creditcard.fill", .paymentMethods)
                profileCard("Receipts", "Invoices & payment history", "doc.text", .receipts)
                profileCard("Founding Access", "Reservation fee to lock your rate", "sparkles", .preOrder)
                profileCard("Legal & Privacy", "Policies & agreements", "building.columns.fill", .legalPrivacy)
                profileCard("Membership", "Concierge pricing", "rosette", .membership)
                profileCard("Support", "White-glove assistance", "questionmark.circle.fill", .support)
                profileCard("Settings", "Preferences & account", "gearshape.fill", .settings)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: ProfileRoute.self) { route in
            route.destination
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2).weight(.bold))
            .tracking(1.8)
            .foregroundStyle(ConciergeLuxe.goldDark)
            .padding(.top, 4)
    }

    private func profileCard(_ title: String, _ subtitle: String, _ systemImage: String, _ route: ProfileRoute) -> some View {
        NavigationLink(value: route) {
            ConciergeNavRow(title: title, systemImage: systemImage, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(BookingStore())
}
