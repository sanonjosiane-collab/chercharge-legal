//
//  AppDelegate.swift
//  Chercharge
//
//  Configures Firebase + APNs / FCM before any SwiftUI @State services touch Auth/Firestore.
//

import FirebaseCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AuthService.configureFirebaseIfNeeded()
        PushRegistrationService.shared.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // UIKit delivers this on the main thread; hop through MainActor for isolation.
        Task { @MainActor in
            PushRegistrationService.shared.application(
                application,
                didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
            )
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushRegistrationService.shared.application(
                application,
                didFailToRegisterForRemoteNotificationsWithError: error
            )
        }
    }
}
