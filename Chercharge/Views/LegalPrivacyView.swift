//
//  LegalPrivacyView.swift
//  Chercharge
//
//  Profile → Settings → Legal & Privacy
//

import SwiftUI

enum CherchargeLegalLinks {
    /// Primary customer / App Review contact email.
    static let supportEmail = "chercharging@gmail.com"

    /// Public GitHub Pages legal & support site (App Store Privacy / Support URLs).
    static let websiteBase = "https://sanonjosiane-collab.github.io/chercharge-legal"

    static let privacyPolicy = url("\(websiteBase)/privacy/")
    static let termsOfService = url("\(websiteBase)/terms/")
    static let support = url("\(websiteBase)/support/")
    /// Account deletion, privacy requests, and related choices are covered on Support.
    static let privacyChoices = support
    /// Refunds and cancellation are covered in Terms of Service.
    static let cancellationRefund = termsOfService

    static var supportMailURL: URL {
        mailto(to: supportEmail, subject: "Chercharge Support")
    }

    /// Kept for callers that still need a mailto fallback for policy requests.
    static var privacyPolicyMailURL: URL { privacyPolicy }
    static var privacyChoicesMailURL: URL { privacyChoices }
    static var termsOfServiceMailURL: URL { termsOfService }
    static var cancellationRefundMailURL: URL { cancellationRefund }

    private static func url(_ string: String) -> URL {
        URL(string: string)!
    }

    private static func mailto(to email: String, subject: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
        ]
        return components.url ?? URL(string: "mailto:\(email)")!
    }
}

struct LegalPrivacyView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Legal",
                title: "Legal & Privacy",
                subtitle: "Policies, agreements, and support disclosures.",
                systemImage: "building.columns.fill"
            )

            ConciergeCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LEGAL ENTITY")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text(FoundingAgreementContent.legalBusinessName)
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.charcoal)

                    Text("Chercharge, INC is the legal contracting party. Chercharge is the business and service brand.")
                        .font(.system(.caption))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SUPPORT CONTACT")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text(CherchargeLegalLinks.supportEmail)
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                        .foregroundStyle(ConciergeLuxe.emerald)

                    Text("Email this address for customer support, privacy requests, account help, billing questions, and App Review follow-up. Public policy pages are also available below.")
                        .font(.system(.caption))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openURL(CherchargeLegalLinks.support)
                    } label: {
                        Text("Open Support page")
                            .font(.system(.subheadline).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ConciergeLuxe.emerald)
                    .padding(.top, 4)

                    Button {
                        openURL(CherchargeLegalLinks.supportMailURL)
                    } label: {
                        Text("Email Chercharge Support")
                            .font(.system(.subheadline).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(ConciergeLuxe.emerald)
                }
            }

            sectionLabel("In-app agreements")

            VStack(spacing: 12) {
                NavigationLink(value: ProfileRoute.foundingAgreement) {
                    ConciergeNavRow(
                        title: "Founding Customer Agreement",
                        systemImage: "doc.text.fill",
                        subtitle: "Founding promotional rate terms"
                    )
                }
                .buttonStyle(.plain)
            }

            sectionLabel("Policies & support")

            VStack(spacing: 12) {
                linkRow(
                    title: "Privacy Policy",
                    subtitle: "Open public HTTPS policy page",
                    systemImage: "hand.raised.fill",
                    url: CherchargeLegalLinks.privacyPolicy
                )
                linkRow(
                    title: "Privacy Choices",
                    subtitle: "Account deletion & privacy requests",
                    systemImage: "slider.horizontal.3",
                    url: CherchargeLegalLinks.privacyChoices
                )
                linkRow(
                    title: "Terms of Service",
                    subtitle: "Open public HTTPS terms page",
                    systemImage: "doc.plaintext.fill",
                    url: CherchargeLegalLinks.termsOfService
                )
                linkRow(
                    title: "Support",
                    subtitle: "Open public HTTPS support page",
                    systemImage: "questionmark.circle.fill",
                    url: CherchargeLegalLinks.support
                )
            }

            ConciergeInfoRibbon(
                text: "Public HTTPS Privacy and Support pages are live on the Chercharge legal site. Email \(CherchargeLegalLinks.supportEmail) for direct contact."
            )
        }
        .navigationTitle("Legal & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2).weight(.bold))
            .tracking(1.8)
            .foregroundStyle(ConciergeLuxe.goldDark)
            .padding(.top, 4)
    }

    private func linkRow(
        title: String,
        subtitle: String,
        systemImage: String,
        url: URL
    ) -> some View {
        Button {
            openURL(url)
        } label: {
            ConciergeNavRow(title: title, systemImage: systemImage, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        LegalPrivacyView()
    }
}
