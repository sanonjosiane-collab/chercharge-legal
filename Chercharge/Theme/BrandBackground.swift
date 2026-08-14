//
//  BrandBackground.swift
//  Chercharge
//
//  A calm, premium, spa-inspired app background: warm ivory base with
//  translucent blurred botanical leaves tucked into the corners and faint
//  glowing organic curves suggesting wind / energy. No sharp edges,
//  no repeating patterns.
//

import SwiftUI

struct BrandBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                // Warm ivory base with a barely-there vertical warmth shift.
                LinearGradient(
                    colors: [Brand.ivory, Brand.ivoryDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Soft gold parchment glow
                Ellipse()
                    .fill(Brand.gold.opacity(0.06))
                    .frame(width: size.width * 0.75, height: size.height * 0.28)
                    .blur(radius: 48)
                    .position(x: size.width * 0.72, y: size.height * 0.10)

                // Faint glowing organic curves (wind / energy).
                energyCurves(in: size)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    // MARK: - Glowing energy curves

    private func energyCurves(in size: CGSize) -> some View {
        ZStack {
            EnergyCurve(sweep: 0.32)
                .stroke(
                    Brand.leaf.opacity(0.05),
                    style: StrokeStyle(lineWidth: 46, lineCap: .round)
                )
                .blur(radius: 34)

            EnergyCurve(sweep: 0.58)
                .stroke(
                    Brand.gold.opacity(0.04),
                    style: StrokeStyle(lineWidth: 38, lineCap: .round)
                )
                .blur(radius: 40)

            EnergyCurve(sweep: 0.74)
                .stroke(
                    Brand.green.opacity(0.045),
                    style: StrokeStyle(lineWidth: 30, lineCap: .round)
                )
                .blur(radius: 30)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Energy curve

/// A single sweeping, organic curve that flows across the canvas.
private struct EnergyCurve: Shape {
    /// Vertical anchor (0...1) for where the curve crosses the canvas.
    var sweep: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let baseY = height * sweep

        path.move(to: CGPoint(x: -width * 0.1, y: baseY + height * 0.12))
        path.addCurve(
            to: CGPoint(x: width * 0.5, y: baseY),
            control1: CGPoint(x: width * 0.12, y: baseY - height * 0.10),
            control2: CGPoint(x: width * 0.30, y: baseY - height * 0.16)
        )
        path.addCurve(
            to: CGPoint(x: width * 1.1, y: baseY - height * 0.14),
            control1: CGPoint(x: width * 0.72, y: baseY + height * 0.14),
            control2: CGPoint(x: width * 0.92, y: baseY + height * 0.06)
        )
        return path
    }
}

// MARK: - Convenience modifier

extension View {
    /// Places the premium ivory background behind this view.
    func brandBackground() -> some View {
        background(BrandBackground())
    }
}

#Preview {
    VStack {
        Spacer()
        Text("Chercharge")
            .font(.system(.largeTitle, design: .serif))
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .brandBackground()
}
