//
//  LuxeComponents.swift
//  Chercharge
//
//  Shared premium UI building blocks (ornate titles, gold-ring emblems,
//  selection cards, info banners, step progress, and the flow header) so every
//  screen reads with the same luxury-spa design language.
//

import SwiftUI

// MARK: - Brand logo

/// The Chercharge crowned "CC" logo, rendered at a given point size.
struct CCLogo: View {
    var size: CGFloat = 24

    var body: some View {
        Image("CherchargeLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - Ornament divider

/// A thin gold rule with a centered diamond ornament.
struct LuxeOrnamentDivider: View {
    var width: CGFloat = 120

    var body: some View {
        HStack(spacing: 6) {
            rule
            Image(systemName: "diamond.fill")
                .font(.system(size: 7))
                .foregroundStyle(Brand.gold)
            rule
        }
        .frame(width: width)
    }

    private var rule: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Brand.gold.opacity(0), Brand.gold.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

// MARK: - Section title

/// Large serif title with an optional gold italic accent word, an ornament
/// divider, and a muted subtitle. Centered by default to match the mockups.
struct LuxeSectionTitle: View {
    let leading: String
    var accent: String? = nil
    var trailing: String? = nil
    var subtitle: String? = nil
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 12) {
            title
                .font(.system(size: 30, weight: .bold, design: .serif))
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)

            LuxeOrnamentDivider()

            if let subtitle {
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private var title: Text {
        var result = Text(leading).foregroundStyle(Brand.greenDeep)
        if let accent {
            result = result
                + Text(" \(accent) ")
                .foregroundStyle(Brand.gold)
                .italic()
        }
        if let trailing {
            result = result + Text(trailing).foregroundStyle(Brand.greenDeep)
        }
        return result
    }
}

// MARK: - Gold-ring emblem

/// An ornate circular emblem — forest-green disc, double gold ring, gold glyph.
struct LuxeEmblem: View {
    let systemImage: String
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle().fill(Brand.forestGradient)
            Circle().stroke(Brand.goldGradient, lineWidth: 2.5)
            Circle()
                .stroke(Brand.gold.opacity(0.5), lineWidth: 1)
                .padding(4)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Brand.goldGradient)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Selection card

/// A premium selectable row with a gold-ring emblem, title/subtitle, a
/// radio/check indicator, and (when selected) a forest fill with a gold
/// crown ribbon in the corner.
struct LuxeSelectionCard: View {
    let systemImage: String
    let title: String
    var subtitleLines: [String] = []
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Brand.goldBright : Brand.muted.opacity(0.5))

                LuxeEmblem(systemImage: systemImage, size: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .foregroundStyle(isSelected ? .white : Brand.ink)
                    ForEach(subtitleLines, id: \.self) { line in
                        Text(line)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : Brand.muted)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Brand.goldBright : Brand.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(shape.fill(isSelected ? AnyShapeStyle(Brand.forestGradient) : AnyShapeStyle(Brand.card)))
            .overlay(
                shape.stroke(
                    isSelected ? AnyShapeStyle(Brand.goldGradient) : AnyShapeStyle(Brand.gold.opacity(0.22)),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .clipShape(shape)
            .shadow(color: Brand.ink.opacity(isSelected ? 0.18 : 0.06), radius: isSelected ? 12 : 7, y: 4)
            .opacity(isDisabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Info banner

/// Ivory reassurance banner with a gold shield emblem, bold serif headline,
/// and a supporting line.
struct LuxeInfoBanner: View {
    var systemImage: String = "shield.lefthalf.filled"
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 34))
                .foregroundStyle(Brand.goldGradient)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(Brand.ink)
                Text(message)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Brand.card.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Brand.gold.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Step progress

/// The "STEP X OF Y · LABEL" indicator with a gold node track.
struct LuxeStepProgress: View {
    let step: Int
    let total: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("STEP \(step) OF \(total)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.gold)
                    .tracking(1)
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.muted)
                    .tracking(1)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let progress = total > 1 ? CGFloat(step - 1) / CGFloat(total - 1) : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Brand.muted.opacity(0.2))
                        .frame(height: 3)

                    Capsule()
                        .fill(Brand.goldGradient)
                        .frame(width: max(6, width * progress), height: 3)

                    HStack(spacing: 0) {
                        ForEach(0..<total, id: \.self) { index in
                            Circle()
                                .fill(index < step ? AnyShapeStyle(Brand.goldGradient) : AnyShapeStyle(Brand.muted.opacity(0.25)))
                                .frame(width: index == step - 1 ? 12 : 8, height: index == step - 1 ? 12 : 8)
                                .overlay {
                                    if index == step - 1 {
                                        Circle().stroke(Brand.card, lineWidth: 2)
                                    }
                                }
                            if index < total - 1 { Spacer(minLength: 0) }
                        }
                    }
                }
            }
            .frame(height: 12)
        }
    }
}

// MARK: - Flow header

/// Centered CHERCHARGE wordmark with a circular back button — the header used
/// across the booking flow and detail screens.
struct LuxeFlowHeader: View {
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack {
            circleButton(systemImage: "chevron.left", action: onBack)

            Spacer()

            HStack(spacing: 8) {
                CCLogo(size: 26)
                VStack(spacing: 0) {
                    Text("CHERCHARGE")
                        .font(.system(.headline, design: .serif).weight(.bold))
                        .foregroundStyle(Brand.ink)
                        .tracking(1.5)
                    Text("EV CONCIERGE")
                        .font(.system(size: 8, weight: .semibold, design: .serif))
                        .foregroundStyle(Brand.muted)
                        .tracking(2)
                }
            }

            Spacer()

            // Balances the leading back button so the wordmark stays centered.
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func circleButton(systemImage: String, action: (() -> Void)?, gold: Bool = false) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(gold ? AnyShapeStyle(Brand.goldGradient) : AnyShapeStyle(Brand.greenDeep))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Brand.card))
                .overlay(Circle().stroke(Brand.gold.opacity(0.55), lineWidth: 1.5))
                .shadow(color: Brand.ink.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(action == nil ? 0.35 : 1)
        .disabled(action == nil)
    }

}
