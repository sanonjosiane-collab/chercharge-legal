//
//  PrimaryButtonStyle.swift
//  Chercharge
//

import SwiftUI

/// Primary CTA — deep forest green with a gold border, gold serif label, and a
/// subtle sparkle. Matches the luxe design language app-wide.
struct PrimaryButtonStyle: ButtonStyle {
    var showsSparkle: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return configuration.label
            .font(.system(.headline, design: .serif).weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(Brand.goldBright)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(shape.fill(Brand.forestGradient))
            .overlay(shape.stroke(Brand.goldGradient, lineWidth: 1.5))
            .overlay(alignment: .trailing) {
                if showsSparkle {
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.goldBright.opacity(0.9))
                        .padding(.trailing, 20)
                }
            }
            .shadow(color: Brand.forestDeep.opacity(0.35), radius: 10, y: 5)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary CTA — ivory fill with a gold outline and forest-green serif label.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return configuration.label
            .font(.system(.headline, design: .serif).weight(.semibold))
            .foregroundStyle(Brand.greenDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(shape.fill(Brand.card))
            .overlay(shape.stroke(Brand.gold.opacity(0.6), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
