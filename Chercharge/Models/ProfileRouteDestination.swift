//
//  ProfileRouteDestination.swift
//  Chercharge
//
//  Shared destinations for ProfileRoute so every NavigationStack that presents
//  Settings / Legal / Pre-order can resolve the same routes.
//

import SwiftUI

extension ProfileRoute {
    @ViewBuilder
    var destination: some View {
        switch self {
        case .personalInfo:
            PersonalInformationView()
        case .vehiclesSaved:
            VehiclesSavedView()
        case .savedAddresses:
            SavedAddressesView()
        case .paymentMethods:
            PaymentMethodsView()
        case .receipts:
            ReceiptsView()
        case .preOrder:
            PreOrderView()
        case .foundingAgreement:
            FoundingAgreementView()
        case .legalPrivacy:
            LegalPrivacyView()
        case .membership:
            MembershipView()
        case .support:
            SupportView()
        case .settings:
            SettingsView()
        case .privacyAccount:
            PrivacyAccountView()
        case .adminDocumentReview:
            AdminHomeView()
        }
    }
}

struct ProfileRouteNavigationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: ProfileRoute.self) { route in
            route.destination
        }
    }
}

extension View {
    /// Registers every `ProfileRoute` destination on this stack.
    func profileRouteDestinations() -> some View {
        modifier(ProfileRouteNavigationModifier())
    }
}
