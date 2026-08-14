//
//  BrandMotion.swift
//  Chercharge
//
//  Restrained brand motion — gold bead, leaf fade, card settle.
//  Prefer these over dashboard sparkle or bounce spam.
//

import SwiftUI

enum BrandMotion {
    static let settle = Animation.easeOut(duration: 0.55)
    static let leafFade = Animation.easeInOut(duration: 0.9)
    static let bead = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
    static let soft = ConciergeLuxe.softEase
}

/// Thin gold rules with a soft pulsing center bead.
struct GoldBeadDivider: View {
    var width: CGFloat = 120
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(ConciergeLuxe.gold.opacity(0.45))
                .frame(width: width * 0.38, height: 1)
            Circle()
                .fill(ConciergeLuxe.gold)
                .frame(width: pulse ? 6 : 4.5, height: pulse ? 6 : 4.5)
                .shadow(color: ConciergeLuxe.gold.opacity(pulse ? 0.55 : 0.25), radius: pulse ? 5 : 2)
            Capsule()
                .fill(ConciergeLuxe.gold.opacity(0.45))
                .frame(width: width * 0.38, height: 1)
        }
        .onAppear {
            withAnimation(BrandMotion.bead) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Soft upward settle used for empty-state and receipt cards.
    func brandCardSettle(delay: Double = 0.05) -> some View {
        modifier(BrandCardSettleModifier(delay: delay))
    }

    /// Gentle opacity rise for botanical / empty heroes.
    func brandLeafFade(delay: Double = 0.08) -> some View {
        modifier(BrandLeafFadeModifier(delay: delay))
    }
}

private struct BrandCardSettleModifier: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(BrandMotion.settle.delay(delay)) {
                    shown = true
                }
            }
    }
}

private struct BrandLeafFadeModifier: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0.35)
            .scaleEffect(shown ? 1 : 0.97, anchor: .center)
            .onAppear {
                withAnimation(BrandMotion.leafFade.delay(delay)) {
                    shown = true
                }
            }
    }
}
