//
//  FoundingAgreementView.swift
//  Chercharge
//
//  Profile → Legal: Pre-Launch Founding Customer Promotional Rate Agreement.
//

import SwiftUI

struct FoundingAgreementView: View {
    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Legal",
                title: FoundingAgreementContent.title,
                subtitle: "Founding promotional rate terms.",
                systemImage: "doc.text.fill"
            )

            ConciergeCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(FoundingAgreementContent.documentTitle)
                        .font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(ConciergeLuxe.charcoal)
                        .fixedSize(horizontal: false, vertical: true)

                    metaLine("Effective Date", FoundingAgreementContent.effectiveDate)
                    metaLine("Last Updated", FoundingAgreementContent.lastUpdated)
                    metaLine("Contracting party", FoundingAgreementContent.legalBusinessName)
                }
            }

            ForEach(FoundingAgreementContent.sections) { section in
                ConciergeCard {
                    VStack(alignment: .leading, spacing: 14) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.system(.caption2).weight(.bold))
                                .tracking(1.4)
                                .foregroundStyle(ConciergeLuxe.goldDark)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    }
                }
            }

            ConciergeInfoRibbon(
                text: "This in-app copy is for review before purchase. The contracting party is Chercharge, INC."
            )
        }
        .navigationTitle("Agreements")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func blockView(_ block: FoundingAgreementContent.Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.system(.footnote))
                .foregroundStyle(ConciergeLuxe.muted)
                .fixedSize(horizontal: false, vertical: true)
        case .emphasis(let text):
            Text(text)
                .font(.system(.footnote).weight(.semibold))
                .foregroundStyle(ConciergeLuxe.charcoal)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 10) {
                Text("•")
                    .font(.system(.footnote).weight(.bold))
                    .foregroundStyle(ConciergeLuxe.goldDark)
                Text(text)
                    .font(.system(.footnote))
                    .foregroundStyle(ConciergeLuxe.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .numbered(let number, let text):
            HStack(alignment: .top, spacing: 10) {
                Text("\(number).")
                    .font(.system(.footnote).weight(.bold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                    .frame(width: 22, alignment: .leading)
                Text(text)
                    .font(.system(.footnote).weight(.medium))
                    .foregroundStyle(ConciergeLuxe.charcoal)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption))
                .foregroundStyle(ConciergeLuxe.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.caption).weight(.semibold))
                .foregroundStyle(ConciergeLuxe.charcoal)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        FoundingAgreementView()
    }
}
