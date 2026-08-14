//
//  Brand.swift
//  Chercharge
//

import SwiftUI

enum Brand {
    static let green = Color(red: 0.12, green: 0.55, blue: 0.32)
    static let greenDeep = Color(red: 0.07, green: 0.38, blue: 0.22)
    static let mist = Color(red: 0.93, green: 0.97, blue: 0.94)
    static let ink = Color(red: 0.08, green: 0.14, blue: 0.11)
    static let muted = Color(red: 0.35, green: 0.42, blue: 0.38)
    static let gold = Color(red: 0.72, green: 0.55, blue: 0.24)

    /// Warm ivory — the premium base tone for the app background.
    static let ivory = Color(red: 0.980, green: 0.968, blue: 0.940)
    static let ivoryDeep = Color(red: 0.960, green: 0.945, blue: 0.910)
    static let leaf = Color(red: 0.36, green: 0.62, blue: 0.44)

    /// Deep forest green used for premium filled surfaces (selected cards, CTAs).
    static let forest = Color(red: 0.09, green: 0.22, blue: 0.14)
    static let forestDeep = Color(red: 0.04, green: 0.12, blue: 0.08)
    static let goldBright = Color(red: 0.85, green: 0.68, blue: 0.33)
    /// Card surface — a hair warmer than pure white so it sits on ivory.
    static let card = Color(red: 0.995, green: 0.988, blue: 0.972)

    /// Reusable dark-green gradient for CTAs and selected surfaces.
    static let forestGradient = LinearGradient(
        colors: [forest, forestDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm gold gradient for borders, emblems, and ribbons.
    static let goldGradient = LinearGradient(
        colors: [goldBright, gold, Color(red: 0.60, green: 0.45, blue: 0.20)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.88, green: 0.96, blue: 0.90),
            Color(red: 0.78, green: 0.91, blue: 0.82),
            Color(red: 0.70, green: 0.86, blue: 0.74)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
