//
//  BookChargeChrome.swift
//  Chercharge
//
//  Luxury chrome used ONLY by BookChargeView — does not affect other screens.
//

import SwiftUI

// MARK: - Palette (Book a Charge only)

enum BookChargePalette {
    /// Warm ivory #FCFAF6
    static let ivory = Color(red: 0.988, green: 0.980, blue: 0.965)
    static let ivoryDeep = Color(red: 0.975, green: 0.965, blue: 0.945)
    /// Emerald #0F4D3C
    static let emerald = Color(red: 0.059, green: 0.302, blue: 0.235)
    static let emeraldDeep = Color(red: 0.04, green: 0.22, blue: 0.17)
    /// Champagne gold #D4AF37
    static let gold = Color(red: 0.831, green: 0.686, blue: 0.216)
    static let goldSoft = Color(red: 0.90, green: 0.78, blue: 0.40)
    static let ink = Color(red: 0.10, green: 0.14, blue: 0.12)
    static let muted = Color(red: 0.42, green: 0.45, blue: 0.42)
    static let card = Color(red: 0.995, green: 0.990, blue: 0.980)

    static let emeraldGradient = LinearGradient(
        colors: [emerald, emeraldDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let goldGradient = LinearGradient(
        colors: [goldSoft, gold, Color(red: 0.65, green: 0.52, blue: 0.15)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cornerRadius: CGFloat = 24
}

// MARK: - Background

struct BookChargeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BookChargePalette.ivory, BookChargePalette.ivoryDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Warm cream wash
            RadialGradient(
                colors: [
                    Color(red: 0.90, green: 0.86, blue: 0.72).opacity(0.18),
                    .clear
                ],
                center: UnitPoint(x: 0.92, y: 0.08),
                startRadius: 10,
                endRadius: 320
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Header

struct BookChargeHeader: View {
    var onBack: (() -> Void)?
    var onOpenProfile: (() -> Void)?

    var body: some View {
        HStack {
            Button {
                onBack?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BookChargePalette.emerald)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(BookChargePalette.ivory))
                    .overlay(Circle().stroke(BookChargePalette.gold.opacity(0.35), lineWidth: 1))
                    .shadow(color: BookChargePalette.ink.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                Image("CherchargeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                VStack(spacing: 1) {
                    Text("CHERCHARGE")
                        .font(.system(.headline, design: .serif).weight(.bold))
                        .foregroundStyle(BookChargePalette.emerald)
                        .tracking(1.6)
                    Text("EV CONCIERGE")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                        .tracking(2)
                }
            }

            Spacer()

            Button {
                onOpenProfile?()
            } label: {
                ZStack {
                    Circle()
                        .fill(BookChargePalette.emeraldGradient)
                        .frame(width: 42, height: 42)
                    Circle()
                        .stroke(BookChargePalette.goldGradient, lineWidth: 1.5)
                        .frame(width: 42, height: 42)
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                }
                .shadow(color: BookChargePalette.ink.opacity(0.08), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(onOpenProfile == nil)
            .opacity(onOpenProfile == nil ? 0.55 : 1)
            .accessibilityLabel("Open profile")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Progress

struct BookChargeProgress: View {
    let step: Int
    let total: Int
    let label: String

    @State private var sparkleX: CGFloat = 0
    @State private var glowPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("STEP \(step) OF \(total)")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(BookChargePalette.gold)
                    .tracking(1.4)
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(BookChargePalette.gold)
                    .tracking(1.4)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let progress = total > 1 ? CGFloat(step - 1) / CGFloat(total - 1) : 0
                let filled = max(10, width * progress)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BookChargePalette.gold.opacity(0.18))
                        .frame(height: 2.5)

                    Capsule()
                        .fill(BookChargePalette.goldGradient)
                        .frame(width: filled, height: 2.5)
                        .shadow(color: BookChargePalette.gold.opacity(glowPulse ? 0.55 : 0.25), radius: glowPulse ? 6 : 3)
                        .animation(.easeInOut(duration: 0.55), value: step)

                    // Traveling sparkle across the active filled section.
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(BookChargePalette.goldSoft)
                        .offset(x: sparkleX * max(0, filled - 10), y: 0)
                        .opacity(filled > 16 ? 0.9 : 0)

                    HStack(spacing: 0) {
                        ForEach(0..<total, id: \.self) { index in
                            let isActive = index == step - 1
                            let isDone = index < step - 1
                            ZStack {
                                Circle()
                                    .fill(
                                        (isDone || isActive)
                                            ? AnyShapeStyle(BookChargePalette.goldGradient)
                                            : AnyShapeStyle(BookChargePalette.gold.opacity(0.22))
                                    )
                                    .frame(width: isActive ? 14 : 8, height: isActive ? 14 : 8)
                                    .shadow(color: isActive ? BookChargePalette.gold.opacity(0.65) : .clear, radius: isActive ? 6 : 0)

                                if isDone {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(BookChargePalette.emeraldDeep)
                                }
                            }
                            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: step)
                            if index < total - 1 { Spacer(minLength: 0) }
                        }
                    }
                }
            }
            .frame(height: 14)
        }
        .onAppear {
            glowPulse = true
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                sparkleX = 1
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .onChange(of: step) { _, _ in
            sparkleX = 0
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                sparkleX = 1
            }
        }
    }
}

// MARK: - Title

struct BookChargeTitle: View {
    let leading: String
    var accent: String? = nil
    var trailing: String? = nil
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            titleText
                .font(.system(size: 34, weight: .bold, design: .serif))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            BookChargeGoldDivider()

            if let subtitle {
                Text(subtitle)
                    .font(.system(.subheadline))
                    .foregroundStyle(Color(red: 0.55, green: 0.52, blue: 0.45))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var titleText: Text {
        var result = Text(leading).foregroundStyle(BookChargePalette.emerald)
        if let accent {
            result = result
                + Text(" \(accent) ")
                .foregroundStyle(BookChargePalette.gold)
                .italic()
        }
        if let trailing {
            result = result + Text(trailing).foregroundStyle(BookChargePalette.emerald)
        }
        return result
    }
}

struct BookChargeGoldDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [BookChargePalette.gold.opacity(0), BookChargePalette.gold.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 44, height: 1)
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BookChargePalette.gold)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [BookChargePalette.gold.opacity(0.7), BookChargePalette.gold.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 44, height: 1)
        }
    }
}

// MARK: - Selection card

struct BookChargeSelectionCard: View {
    let systemImage: String
    let title: String
    var subtitleLines: [String] = []
    let isSelected: Bool
    var isDisabled: Bool = false
    var compact: Bool = false
    let action: () -> Void

    @State private var pressed = false

    private let shape = RoundedRectangle(cornerRadius: BookChargePalette.cornerRadius, style: .continuous)

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                action()
            }
        } label: {
            HStack(spacing: compact ? 10 : 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 17 : 20, weight: .semibold))
                    .foregroundStyle(isSelected ? BookChargePalette.gold : BookChargePalette.gold.opacity(0.35))

                BookChargeMedallion(systemImage: systemImage, size: compact ? 40 : 54)

                VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                    Text(title)
                        .font(.system(compact ? .body : .title3, design: .serif).weight(.bold))
                        .foregroundStyle(isSelected ? .white : BookChargePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    ForEach(subtitleLines, id: \.self) { line in
                        Text(line)
                            .font(.system(compact ? .caption : .footnote))
                            .foregroundStyle(isSelected ? .white.opacity(0.82) : BookChargePalette.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(BookChargePalette.gold)
            }
            .padding(compact ? 12 : 18)
            .frame(maxWidth: .infinity)
            .background(
                shape.fill(
                    isSelected
                        ? AnyShapeStyle(BookChargePalette.emeraldGradient)
                        : AnyShapeStyle(BookChargePalette.card)
                )
            )
            .overlay(
                shape.stroke(
                    isSelected
                        ? AnyShapeStyle(BookChargePalette.goldGradient)
                        : AnyShapeStyle(BookChargePalette.gold.opacity(0.28)),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .shadow(
                color: BookChargePalette.ink.opacity(isSelected ? 0.16 : 0.07),
                radius: isSelected ? 14 : 10,
                y: isSelected ? 6 : 4
            )
            .scaleEffect(pressed ? 0.985 : (isSelected ? 1.01 : 1.0))
            .opacity(isDisabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.12)) { pressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pressed = false }
                }
        )
    }
}

struct BookChargeMedallion: View {
    let systemImage: String
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(BookChargePalette.emeraldGradient)
            Circle().stroke(BookChargePalette.goldGradient, lineWidth: 2)
            Circle()
                .stroke(BookChargePalette.gold.opacity(0.45), lineWidth: 1)
                .padding(4)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(BookChargePalette.gold)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Info banner

struct BookChargeInfoBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 30))
                .foregroundStyle(BookChargePalette.goldGradient)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(BookChargePalette.ink)
                Text(message)
                    .font(.system(.footnote))
                    .foregroundStyle(BookChargePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: BookChargePalette.cornerRadius, style: .continuous)
                .fill(BookChargePalette.card.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: BookChargePalette.cornerRadius, style: .continuous)
                        .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: BookChargePalette.ink.opacity(0.05), radius: 8, y: 3)
        )
    }
}

// MARK: - Continue button (shimmer every 6s)

struct BookChargeContinueButton: View {
    let title: String
    let isEnabled: Bool
    var isLoading: Bool = false
    var showsCrown: Bool = false
    let action: () -> Void

    @State private var shimmer = false

    private let shape = RoundedRectangle(cornerRadius: BookChargePalette.cornerRadius, style: .continuous)

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                ZStack {
                    shape.fill(BookChargePalette.emeraldGradient)

                    // Gold shimmer sweep every ~6 seconds.
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear,
                                BookChargePalette.gold.opacity(0.0),
                                BookChargePalette.gold.opacity(0.45),
                                BookChargePalette.gold.opacity(0.0),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.45)
                        .offset(x: shimmer ? proxy.size.width : -proxy.size.width * 0.45)
                        .blendMode(.plusLighter)
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)

                    Group {
                        if isLoading {
                            ProgressView().tint(BookChargePalette.gold)
                        } else if showsCrown {
                            HStack {
                                Spacer(minLength: 0)
                                Text(title)
                                    .font(.system(size: 16, weight: .bold, design: .serif))
                                    .tracking(3.2)
                                    .foregroundStyle(BookChargePalette.gold)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(BookChargePalette.gold)
                                    .frame(width: 34, height: 34)
                            }
                            .padding(.horizontal, 14)
                        } else {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.18))
                                        .overlay(Circle().stroke(BookChargePalette.gold.opacity(0.55), lineWidth: 1))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(BookChargePalette.gold)
                                }

                                Spacer(minLength: 0)

                                Text(title)
                                    .font(.system(size: 16, weight: .bold, design: .serif))
                                    .tracking(3.2)
                                    .foregroundStyle(BookChargePalette.gold)

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(BookChargePalette.gold)
                                    .frame(width: 34, height: 34)
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .overlay(shape.stroke(BookChargePalette.goldGradient, lineWidth: 1.5))
                .shadow(color: BookChargePalette.emerald.opacity(isEnabled ? 0.45 : 0.15), radius: 14, y: 6)
                .shadow(color: BookChargePalette.gold.opacity(showsCrown && isEnabled ? 0.35 : 0.18), radius: showsCrown ? 12 : 8, y: showsCrown ? 6 : 4)

                if showsCrown && !isLoading {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(BookChargePalette.emeraldDeep)
                                .overlay(Circle().stroke(BookChargePalette.gold.opacity(0.7), lineWidth: 1))
                        )
                        .offset(y: -12)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.5)
        .onAppear { startShimmerLoop() }
    }

    private func startShimmerLoop() {
        shimmer = false
        withAnimation(.easeInOut(duration: 1.2).delay(0.4)) {
            shimmer = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            shimmer = false
            startShimmerLoop()
        }
    }
}

struct BookChargeSecondaryButton: View {
    let title: String
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: BookChargePalette.cornerRadius, style: .continuous)

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(BookChargePalette.emerald)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(shape.fill(BookChargePalette.card))
                .overlay(shape.stroke(BookChargePalette.gold.opacity(0.45), lineWidth: 1.5))
                .shadow(color: BookChargePalette.ink.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating bottom bar (screen-local)

struct BookChargeBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(BookChargePalette.ivory.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(BookChargePalette.gold.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: BookChargePalette.ink.opacity(0.08), radius: 16, y: -2)
                    .padding(.horizontal, 10)
            )
    }
}

// MARK: - Occasional sparkles

struct BookChargeAmbientSparkles: View {
    @State private var phase = 0

    private let spots: [(x: CGFloat, y: CGFloat, delay: Double)] = [
        (0.18, 0.22, 0.0),
        (0.82, 0.18, 1.8),
        (0.72, 0.55, 3.4),
        (0.28, 0.70, 5.1)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(spots.enumerated()), id: \.offset) { index, spot in
                    Image(systemName: "sparkle")
                        .font(.system(size: 8 + CGFloat(index % 2) * 3))
                        .foregroundStyle(BookChargePalette.gold.opacity(phase == index ? 0.55 : 0))
                        .position(
                            x: proxy.size.width * spot.x,
                            y: proxy.size.height * spot.y
                        )
                        .animation(.easeInOut(duration: 1.1), value: phase)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { cycle() }
    }

    private func cycle() {
        for (index, spot) in spots.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + spot.delay) {
                withAnimation { phase = index }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation { if phase == index { phase = -1 } }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) {
            cycle()
        }
    }
}

// MARK: - Floating card chrome helper

struct BookChargeCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: BookChargePalette.cornerRadius, style: .continuous)
                    .fill(BookChargePalette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: BookChargePalette.cornerRadius, style: .continuous)
                            .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: BookChargePalette.ink.opacity(0.07), radius: 10, y: 4)
            )
    }
}

extension View {
    func bookChargeCard() -> some View {
        modifier(BookChargeCardChrome())
    }
}

// MARK: - Step 2 vehicle carousel (mock)

struct BookChargeVehicleCarousel: View {
    let vehicles: [Vehicle]
    @Binding var selectedID: UUID?
    var canBook: (Vehicle) -> Bool

    @State private var index = 0

    private var safeIndex: Int {
        guard !vehicles.isEmpty else { return 0 }
        return min(max(0, index), vehicles.count - 1)
    }

    private var current: Vehicle? {
        guard !vehicles.isEmpty else { return nil }
        return vehicles[safeIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let vehicle = current {
                vehicleCard(vehicle)
            }
        }
        .onAppear { syncIndexFromSelection() }
        .onChange(of: selectedID) { _, _ in syncIndexFromSelection() }
        .onChange(of: index) { _, newValue in
            guard vehicles.indices.contains(newValue) else { return }
            let vehicle = vehicles[newValue]
            if canBook(vehicle) {
                selectedID = vehicle.id
            } else if let bookable = vehicles.first(where: canBook) {
                selectedID = bookable.id
                if let i = vehicles.firstIndex(where: { $0.id == bookable.id }) {
                    index = i
                }
            }
        }
    }

    private func syncIndexFromSelection() {
        if let selectedID,
           let i = vehicles.firstIndex(where: { $0.id == selectedID }) {
            index = i
        } else if let i = vehicles.firstIndex(where: canBook) {
            index = i
            selectedID = vehicles[i].id
        } else if !vehicles.isEmpty {
            index = 0
            selectedID = vehicles[0].id
        }
    }

    private func vehicleCard(_ vehicle: Vehicle) -> some View {
        let bookable = canBook(vehicle)
        return VStack(spacing: 14) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("SELECTED VEHICLE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.9)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 10,
                        topTrailingRadius: 10,
                        style: .continuous
                    )
                    .fill(BookChargePalette.goldGradient)
                )

                Spacer(minLength: 0)

                Text(vehicle.paintColor.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(BookChargePalette.gold)
            }

            // GTA-style interactive garage stage
            VehicleGarage3DStage(vehicle: vehicle, height: 230, autoSpin: true, showsHint: true)
                .opacity(bookable ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 8) {
                Text(vehicle.displayName)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(BookChargePalette.emerald)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 14) {
                    Label {
                        Text("\(vehicle.currentChargePercent)%")
                            .font(.system(size: 12, weight: .semibold))
                    } icon: {
                        Image(systemName: "battery.50percent")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(BookChargePalette.emerald)

                    Label {
                        Text("\(vehicle.estimatedRangeMiles) mi")
                            .font(.system(size: 12, weight: .semibold))
                    } icon: {
                        Image(systemName: "road.lanes")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(BookChargePalette.emerald)

                    Spacer(minLength: 0)

                    HStack(spacing: 5) {
                        Image(systemName: bookable ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(bookable ? BookChargePalette.gold : BookChargePalette.muted)
                        Text(bookable ? "Ready for pickup" : "Needs more range")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(bookable ? BookChargePalette.emerald : BookChargePalette.muted)
                    }
                }
            }

            HStack {
                carouselButton(systemImage: "chevron.left") {
                    guard vehicles.count > 1 else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        index = (safeIndex - 1 + vehicles.count) % vehicles.count
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(vehicles.indices, id: \.self) { i in
                        Circle()
                            .fill(i == safeIndex ? BookChargePalette.emerald : BookChargePalette.muted.opacity(0.28))
                            .frame(width: i == safeIndex ? 7 : 6, height: i == safeIndex ? 7 : 6)
                    }
                }

                Spacer()

                carouselButton(systemImage: "chevron.right") {
                    guard vehicles.count > 1 else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        index = (safeIndex + 1) % vehicles.count
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            BookChargePalette.card,
                            Color(red: 0.99, green: 0.985, blue: 0.975)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(BookChargePalette.gold.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: BookChargePalette.gold.opacity(0.14), radius: 14, y: 5)
                .shadow(color: BookChargePalette.ink.opacity(0.06), radius: 10, y: 4)
        )
    }

    private func carouselButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BookChargePalette.gold)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color(red: 0.96, green: 0.94, blue: 0.90))
                        .overlay(Circle().stroke(BookChargePalette.gold.opacity(0.35), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .opacity(vehicles.count > 1 ? 1 : 0.35)
        .disabled(vehicles.count <= 1)
    }
}

// MARK: - Step 5 review row

struct BookChargeReviewRow: View {
    let systemImage: String
    let label: String
    let value: String
    var showEdit: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BookChargePalette.emeraldGradient)
                        .frame(width: 38, height: 38)
                    Circle()
                        .stroke(BookChargePalette.gold.opacity(0.55), lineWidth: 1.25)
                        .frame(width: 38, height: 38)
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(BookChargePalette.gold)
                    Text(value)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(BookChargePalette.emerald)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if showEdit {
                    HStack(spacing: 2) {
                        Text("Edit")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(BookChargePalette.gold)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!showEdit || action == nil)
    }
}

struct BookChargeSecureBanner: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            // Soft shield watermark + sparkles (mock right graphic)
            ZStack {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 58, weight: .ultraLight))
                    .foregroundStyle(BookChargePalette.gold.opacity(0.16))
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(BookChargePalette.gold.opacity(0.45))
                    .offset(x: 22, y: -18)
                Image(systemName: "sparkle")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(BookChargePalette.gold.opacity(0.35))
                    .offset(x: 30, y: 8)
            }
            .padding(.trailing, 10)
            .allowsHitTesting(false)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BookChargePalette.emeraldGradient)
                        .frame(width: 42, height: 42)
                    Circle()
                        .stroke(BookChargePalette.gold.opacity(0.5), lineWidth: 1)
                        .frame(width: 42, height: 42)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BookChargePalette.gold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Secure & encrypted")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(BookChargePalette.emerald)
                    Text("Your information is safe with us.")
                        .font(.system(size: 12))
                        .foregroundStyle(BookChargePalette.muted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.975, green: 0.955, blue: 0.925).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BookChargePalette.gold.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: BookChargePalette.gold.opacity(0.08), radius: 8, y: 2)
        )
    }
}

// MARK: - Step 3 pickup location card

struct BookChargePickupCard: View {
    let location: LocationPin
    let systemImage: String
    let isSelected: Bool
    var isDefault: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 12) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BookChargePalette.gold)
                    } else {
                        Circle()
                            .stroke(BookChargePalette.gold.opacity(0.45), lineWidth: 1.2)
                            .frame(width: 18, height: 18)
                    }

                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.clear : BookChargePalette.emerald.opacity(0.10))
                            .overlay(
                                Circle().stroke(
                                    isSelected ? BookChargePalette.gold.opacity(0.7) : BookChargePalette.gold.opacity(0.35),
                                    lineWidth: 1.2
                                )
                            )
                            .frame(width: 42, height: 42)
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? BookChargePalette.gold : BookChargePalette.emerald)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.name)
                            .font(.system(size: 17, weight: .bold, design: .serif))
                            .foregroundStyle(isSelected ? .white : BookChargePalette.emerald)

                        Text(location.address)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? .white.opacity(0.82) : BookChargePalette.muted)
                            .lineLimit(2)

                        if isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(isSelected ? BookChargePalette.gold : BookChargePalette.gold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(
                                    Capsule()
                                        .stroke(BookChargePalette.gold.opacity(0.7), lineWidth: 1)
                                )
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? BookChargePalette.gold : BookChargePalette.gold.opacity(0.7))
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(BookChargePalette.emeraldGradient) : AnyShapeStyle(BookChargePalette.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isSelected ? BookChargePalette.gold.opacity(0.45) : BookChargePalette.gold.opacity(0.28),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                    .shadow(
                        color: isSelected ? BookChargePalette.emerald.opacity(0.28) : BookChargePalette.ink.opacity(0.05),
                        radius: isSelected ? 12 : 6,
                        y: 4
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
