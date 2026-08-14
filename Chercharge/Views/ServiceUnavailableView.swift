//
//  ServiceUnavailableView.swift
//  Chercharge
//
//  Shown when Book a Charge or Live Status is opened while live concierge is offline.
//

import SwiftUI

enum ServiceUnavailableKind {
    case bookACharge
    case liveStatus

    var eyebrow: String {
        switch self {
        case .bookACharge: return "Book a Charge"
        case .liveStatus: return "Live status"
        }
    }

    var message: String {
        switch self {
        case .bookACharge: return CherchargeServiceAvailability.bookMessage
        case .liveStatus: return CherchargeServiceAvailability.liveStatusMessage
        }
    }

    var systemImage: String {
        switch self {
        case .bookACharge: return "calendar.badge.exclamationmark"
        case .liveStatus: return "location.slash.fill"
        }
    }
}

struct ServiceUnavailableView: View {
    @Binding var path: NavigationPath
    let kind: ServiceUnavailableKind
    var onBackHome: (() -> Void)? = nil

    var body: some View {
        ZStack {
            BrandBackground()

            VStack(spacing: 0) {
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
                        .foregroundStyle(ConciergeLuxe.emerald)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(ConciergeLuxe.card)
                                .overlay(Capsule().stroke(ConciergeLuxe.gold.opacity(0.45), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 24)

                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(ConciergeLuxe.emerald.opacity(0.1))
                            .frame(width: 88, height: 88)
                        Circle()
                            .stroke(ConciergeLuxe.gold.opacity(0.45), lineWidth: 1.2)
                            .frame(width: 88, height: 88)
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(ConciergeLuxe.emerald)
                    }

                    Text(kind.eyebrow.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text(CherchargeServiceAvailability.notAvailableTitle)
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundStyle(ConciergeLuxe.emerald)
                        .multilineTextAlignment(.center)

                    Text(kind.message)
                        .font(.system(size: 15))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    VStack(spacing: 12) {
                        Button {
                            path = NavigationPath()
                            path.append(AppRoute.preOrder)
                        } label: {
                            Text("Explore Founding Access")
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundStyle(ConciergeLuxe.gold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    Capsule()
                                        .fill(ConciergeLuxe.emeraldGradient)
                                        .overlay(Capsule().stroke(ConciergeLuxe.gold.opacity(0.5), lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)

                        Link(destination: CherchargeLegalLinks.support) {
                            Text("Contact Support")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ConciergeLuxe.emerald)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(ConciergeLuxe.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(ConciergeLuxe.gold.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: ConciergeLuxe.charcoal.opacity(0.08), radius: 16, y: 6)
                )
                .padding(.horizontal, 22)

                Spacer(minLength: 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        ServiceUnavailableView(path: .constant(NavigationPath()), kind: .bookACharge)
    }
}
