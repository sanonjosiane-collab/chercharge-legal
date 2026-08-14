//
//  CherchargeApp.swift
//  Chercharge
//

import SwiftUI
import UIKit

@main
struct CherchargeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = BookingStore()
    @State private var documentInbox = DocumentReviewInbox()
    @State private var customerNotifications = CustomerNotificationInbox()
    @State private var teslaAuth = TeslaAuthService()
    @State private var auth = AuthService()
    @State private var appLock = AppLockController()
    @State private var notificationPermissions = NotificationPermissionCoordinator()
    @State private var userLocation = UserLocationService()

    init() {
        // Belt-and-suspenders: AppDelegate configures first; this covers previews / odd launch paths.
        AuthService.configureFirebaseIfNeeded()
        Self.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(documentInbox)
                .environment(customerNotifications)
                .environment(teslaAuth)
                .environment(auth)
                .environment(appLock)
                .environment(notificationPermissions)
                .environment(userLocation)
                .tint(Brand.greenDeep)
                .onAppear {
                    store.bindDocumentInbox(documentInbox)
                    store.bindCustomerNotifications(customerNotifications)
                }
        }
    }

    private static func configureAppearance() {
        let ivory = UIColor(Brand.ivory)
        let ink = UIColor(Brand.ink)
        let gold = UIColor(Brand.gold)

        let serifLarge = serifFont(size: 30, weight: .bold)
        let serifInline = serifFont(size: 17, weight: .semibold)

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = ivory
        navBar.shadowColor = .clear
        navBar.titleTextAttributes = [
            .foregroundColor: ink,
            .font: serifInline
        ]
        navBar.largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: serifLarge
        ]
        let backButton = UIBarButtonItemAppearance()
        backButton.normal.titleTextAttributes = [.foregroundColor: gold]
        navBar.buttonAppearance = backButton
        navBar.backButtonAppearance = backButton

        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
        UINavigationBar.appearance().tintColor = gold

        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = ivory
        tabBar.shadowColor = UIColor(Brand.gold.opacity(0.35))
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }

    private static func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}
