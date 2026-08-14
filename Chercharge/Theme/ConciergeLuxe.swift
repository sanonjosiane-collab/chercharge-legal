//
//  ConciergeLuxe.swift
//  Chercharge
//
//  Shared luxury chrome for Reservations, Vehicles, Profile, and the floating tab bar.
//

import SwiftUI

// MARK: - Palette

enum ConciergeLuxe {
    /// Warm ivory #FCFAF5
    static let ivory = Color(red: 0.988, green: 0.980, blue: 0.961)
    static let ivoryDeep = Color(red: 0.975, green: 0.965, blue: 0.940)
    /// Emerald #0F4D3A
    static let emerald = Color(red: 0.059, green: 0.302, blue: 0.227)
    static let emeraldDeep = Color(red: 0.04, green: 0.22, blue: 0.16)
    /// Champagne gold #D4AF37 / dark gold #B8892F
    static let gold = Color(red: 0.831, green: 0.686, blue: 0.216)
    static let goldDark = Color(red: 0.722, green: 0.537, blue: 0.184)
    static let goldSoft = Color(red: 0.90, green: 0.78, blue: 0.42)
    /// Charcoal
    static let charcoal = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let muted = Color(red: 0.40, green: 0.42, blue: 0.40)
    static let card = Color(red: 0.996, green: 0.991, blue: 0.980)

    static let cornerRadius: CGFloat = 26

    static let emeraldGradient = LinearGradient(
        colors: [emerald, emeraldDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let goldGradient = LinearGradient(
        colors: [goldSoft, gold, goldDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let softEase = Animation.easeInOut(duration: 0.45)
}

// MARK: - Background

struct ConciergeLuxeBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [ConciergeLuxe.ivory, ConciergeLuxe.ivoryDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Soft gold light reflections
                Ellipse()
                    .fill(ConciergeLuxe.gold.opacity(0.06))
                    .frame(width: size.width * 0.7, height: size.height * 0.28)
                    .blur(radius: 50)
                    .position(x: size.width * 0.75, y: size.height * 0.12)

                Ellipse()
                    .fill(ConciergeLuxe.gold.opacity(0.04))
                    .frame(width: size.width * 0.55, height: size.height * 0.22)
                    .blur(radius: 40)
                    .position(x: size.width * 0.2, y: size.height * 0.55)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

extension View {
    func conciergeBackground() -> some View {
        background(ConciergeLuxeBackground())
    }
}

// MARK: - Medallion icon

struct ConciergeMedallion: View {
    let systemImage: String
    var size: CGFloat = 46
    var selected: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? AnyShapeStyle(ConciergeLuxe.card.opacity(0.18)) : AnyShapeStyle(ConciergeLuxe.emeraldGradient))
            Circle()
                .stroke(ConciergeLuxe.goldGradient, lineWidth: 1.5)
            Circle()
                .stroke(ConciergeLuxe.gold.opacity(0.35), lineWidth: 0.8)
                .padding(3.5)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(ConciergeLuxe.goldGradient)
        }
        .frame(width: size, height: size)
        .shadow(color: ConciergeLuxe.gold.opacity(0.18), radius: 4, y: 1)
    }
}

// MARK: - Stationery card

struct ConciergeCard<Content: View>: View {
    var selected: Bool = false
    @ViewBuilder var content: Content

    private let shape = RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(
                    selected
                        ? AnyShapeStyle(ConciergeLuxe.emeraldGradient)
                        : AnyShapeStyle(ConciergeLuxe.card)
                )
            )
            .overlay(
                shape.stroke(
                    selected
                        ? AnyShapeStyle(ConciergeLuxe.goldGradient)
                        : AnyShapeStyle(ConciergeLuxe.gold.opacity(0.28)),
                    lineWidth: selected ? 1.5 : 1
                )
            )
            .shadow(
                color: ConciergeLuxe.charcoal.opacity(selected ? 0.14 : 0.06),
                radius: selected ? 14 : 10,
                y: selected ? 6 : 4
            )
    }
}

// MARK: - Navigation row card

struct ConciergeNavRow: View {
    let title: String
    let systemImage: String
    var badge: String? = nil
    var subtitle: String? = nil

    var body: some View {
        ConciergeCard {
            HStack(spacing: 14) {
                ConciergeMedallion(systemImage: systemImage, size: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.charcoal)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(.footnote))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }
                }

                Spacer(minLength: 8)

                if let badge {
                    ConciergeBadge(text: badge)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.gold)
            }
        }
    }
}

// MARK: - Badge

struct ConciergeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption2).weight(.bold))
            .foregroundStyle(ConciergeLuxe.goldDark)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(ConciergeLuxe.ivory)
                    .overlay(Capsule().stroke(ConciergeLuxe.gold, lineWidth: 1))
            )
    }
}

// MARK: - Section title

struct ConciergeSectionTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(ConciergeLuxe.charcoal)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.subheadline))
                    .foregroundStyle(ConciergeLuxe.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Gold flourish

struct ConciergeGoldFlourish: View {
    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [ConciergeLuxe.gold.opacity(0), ConciergeLuxe.gold.opacity(0.65)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 28, height: 1)
            Image(systemName: "diamond.fill")
                .font(.system(size: 5))
                .foregroundStyle(ConciergeLuxe.gold)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [ConciergeLuxe.gold.opacity(0.65), ConciergeLuxe.gold.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 28, height: 1)
        }
        .opacity(0.85)
    }
}

// MARK: - Royal decorative banner (Profile tab)

struct ConciergeRoyalBanner: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "crown.fill"

    var body: some View {
        VStack(spacing: 14) {
            ConciergeGoldFlourish()

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ConciergeLuxe.emeraldGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(ConciergeLuxe.goldGradient, lineWidth: 1.5)
                    )
                    .shadow(color: ConciergeLuxe.emerald.opacity(0.35), radius: 16, y: 8)

                // Soft gold wash
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                ConciergeLuxe.gold.opacity(0.18),
                                .clear,
                                ConciergeLuxe.gold.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)

                // Corner ornaments
                bannerCornerOrnaments

                VStack(spacing: 8) {
                    ConciergeMedallion(systemImage: systemImage, size: 48, selected: true)

                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(ConciergeLuxe.goldSoft)

                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(ConciergeLuxe.card)
                        .multilineTextAlignment(.center)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(.footnote))
                            .foregroundStyle(ConciergeLuxe.card.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
            }

            ConciergeGoldFlourish()
        }
    }

    private var bannerCornerOrnaments: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 10
            ForEach(0..<4, id: \.self) { index in
                Image(systemName: "diamond.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(ConciergeLuxe.gold.opacity(0.7))
                    .position(
                        x: index % 2 == 0 ? inset + 6 : proxy.size.width - inset - 6,
                        y: index < 2 ? inset + 6 : proxy.size.height - inset - 6
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Profile page shell

struct ConciergeProfilePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            ConciergeLuxeBackground()

            // Same botanical leaf format as Home.
            CherchargeBotanicalBranches()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                // Extra clearance so the last rows (e.g. Settings) sit above the floating tab bar.
                .padding(.bottom, 110)
            }
        }
    }
}

// MARK: - Royal field card (forms)

struct ConciergeFieldCard<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        ConciergeCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased())
                    .font(.system(.caption2).weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(ConciergeLuxe.goldDark)
                content
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(ConciergeLuxe.charcoal)
            }
        }
    }
}

// MARK: - Gold outline button

struct ConciergeGoldOutlineButton: View {
    let title: String
    var systemImage: String = "plus.circle.fill"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(.body, design: .serif).weight(.semibold))
            }
            .foregroundStyle(ConciergeLuxe.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)
                    .fill(ConciergeLuxe.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)
                            .stroke(ConciergeLuxe.gold.opacity(0.5), lineWidth: 1.5)
                    )
                    .shadow(color: ConciergeLuxe.charcoal.opacity(0.06), radius: 10, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info ribbon

struct ConciergeInfoRibbon: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ConciergeLuxe.gold)
            Text(text)
                .font(.system(.caption))
                .foregroundStyle(ConciergeLuxe.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ConciergeLuxe.card.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ConciergeLuxe.gold.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

// MARK: - Primary shimmer button

struct ConciergePrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var shimmer = false

    private let shape = RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)

    var body: some View {
        Button(action: action) {
            ZStack {
                shape.fill(ConciergeLuxe.emeraldGradient)

                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            .clear,
                            ConciergeLuxe.gold.opacity(0.0),
                            ConciergeLuxe.gold.opacity(0.4),
                            ConciergeLuxe.gold.opacity(0.0),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.4)
                    .offset(x: shimmer ? proxy.size.width : -proxy.size.width * 0.4)
                    .blendMode(.plusLighter)
                }
                .clipShape(shape)
                .allowsHitTesting(false)

                Text(title)
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(ConciergeLuxe.gold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .overlay(shape.stroke(ConciergeLuxe.goldGradient, lineWidth: 1.5))
            .shadow(color: ConciergeLuxe.emerald.opacity(isEnabled ? 0.35 : 0.12), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onAppear { startShimmer() }
    }

    private func startShimmer() {
        shimmer = false
        withAnimation(.easeInOut(duration: 1.4).delay(0.6)) {
            shimmer = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            shimmer = false
            startShimmer()
        }
    }
}

// MARK: - Floating tab bar

struct ConciergeFloatingTabBar: View {
    @Binding var selection: MainTab
    var reservationsBadge: Int = 0

    private let tabs: [(MainTab, String, String)] = [
        (.home, "Home", "TabHome"),
        (.bookings, "Reservations", "TabReservations"),
        (.vehicles, "Vehicles", "TabVehicles"),
        (.profile, "Profile", "TabProfile")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab, title, asset in
                tabButton(tab: tab, title: title, asset: asset)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(ConciergeLuxe.ivory.opacity(0.94))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(ConciergeLuxe.gold.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: ConciergeLuxe.charcoal.opacity(0.10), radius: 14, y: 4)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
    }

    private func tabButton(tab: MainTab, title: String, asset: String) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(ConciergeLuxe.softEase) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.90, green: 0.90, blue: 0.88))
                                .frame(width: 58, height: 34)
                        }
                        Image(asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                    }
                    .frame(width: 58, height: 34)

                    if tab == .bookings, reservationsBadge > 0 {
                        Text("\(reservationsBadge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ConciergeLuxe.goldDark)
                            .frame(width: 15, height: 15)
                            .background(
                                Circle()
                                    .fill(ConciergeLuxe.ivory)
                                    .overlay(Circle().stroke(ConciergeLuxe.gold, lineWidth: 1))
                            )
                            .offset(x: 2, y: -4)
                    }
                }

                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? ConciergeLuxe.gold : ConciergeLuxe.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
