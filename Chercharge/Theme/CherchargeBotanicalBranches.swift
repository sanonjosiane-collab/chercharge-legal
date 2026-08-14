//
//  CherchargeBotanicalBranches.swift
//  Chercharge
//
//  Shared Home-style botanical watermark: bottom-left + bottom-right rising
//  branches and a top-right cascade growing downward.
//

import SwiftUI

/// Cream-screen foliage watermark matching the Home tab layout.
struct CherchargeBotanicalBranches: View {
    var body: some View {
        GeometryReader { proxy in
            let branchWidth = min(proxy.size.width * 0.55, 260)
            let topBranchWidth = min(proxy.size.width * 0.48, 230)

            ZStack {
                // LEFT — stem at bottom-left, leaves rising up the left edge.
                Image("HomeBotanicalFoliage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: branchWidth)
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(-8), anchor: .bottom)
                    .opacity(0.28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .offset(x: -branchWidth * 0.22, y: proxy.size.height * 0.02)

                // RIGHT — stem at bottom-right, leaves rising up the right edge.
                Image("HomeBotanicalFoliage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: branchWidth)
                    .rotationEffect(.degrees(8), anchor: .bottom)
                    .opacity(0.28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: branchWidth * 0.22, y: proxy.size.height * 0.02)

                // TOP RIGHT — stem at top-right, leaves cascading downward.
                Image("HomeBotanicalFoliage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: topBranchWidth)
                    .scaleEffect(x: 1, y: -1)
                    .rotationEffect(.degrees(-12), anchor: .top)
                    .opacity(0.26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: topBranchWidth * 0.18, y: -proxy.size.height * 0.02)
            }
            .compositingGroup()
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
