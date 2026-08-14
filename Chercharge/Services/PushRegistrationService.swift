//
//  PushRegistrationService.swift
//  Chercharge
//
//  Registers for APNs via Firebase Cloud Messaging and uploads the FCM + APNs
//  tokens so Edge Functions can wake the customer app (direct APNs when FCM’s
//  Apple auth fails with THIRD_PARTY_AUTH_ERROR).
//

import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushRegistrationService: NSObject {
    static let shared = PushRegistrationService()

    private var pendingEmail: String?
    private var pendingCustomerID: UUID?
    private var lastUploadedFCMToken: String?
    private var lastUploadedApnsToken: String?
    private var pendingApnsTokenHex: String?

    private override init() {
        super.init()
    }

    /// Call once after Firebase configures.
    func configure() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    /// Request OS permission (if needed), register for remote notifications, upload token.
    func refreshRegistration(
        customerEmail: String?,
        customerID: UUID?,
        optIn: Bool
    ) async {
        let email = customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        pendingEmail = email
        pendingCustomerID = customerID

        guard optIn else { return }
        guard let email, email.contains("@"), !email.hasSuffix("@chercharge.local") else { return }
        guard FirebaseApp.app() != nil else { return }

        let allowed = await InspectionNotificationService.enableForBookingFlow()
        guard allowed else { return }

        // ensureForBookingFlow already registers; call again explicitly on main for clarity.
        UIApplication.shared.registerForRemoteNotifications()

        await refreshAndUploadFCMToken()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        pendingApnsTokenHex = hex
        #if DEBUG
        print("APNs device token registered (\(deviceToken.count) bytes): \(hex.prefix(16))…")
        #endif
        Task { @MainActor in
            await self.refreshAndUploadFCMToken()
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    /// Fetch the current FCM registration token (after APNs is set) and save to device_tokens.
    private func refreshAndUploadFCMToken() async {
        guard FirebaseApp.app() != nil else { return }
        do {
            let token = try await Messaging.messaging().token()
            guard !token.isEmpty else { return }
            await uploadToken(token)
        } catch {
            #if DEBUG
            print("FCM token refresh failed: \(error.localizedDescription)")
            #endif
            // Fall back to any cached token Messaging already has.
            if let cached = Messaging.messaging().fcmToken, !cached.isEmpty {
                await uploadToken(cached)
            }
        }
    }

    private func uploadToken(_ token: String) async {
        // Prefer the explicit APNs callback hex; fall back to Messaging's APNs token
        // (Firebase may mint an FCM token before didRegisterForRemoteNotifications).
        var apnsHex = pendingApnsTokenHex
        if apnsHex == nil, let apnsData = Messaging.messaging().apnsToken, !apnsData.isEmpty {
            apnsHex = apnsData.map { String(format: "%02.2hhx", $0) }.joined()
            pendingApnsTokenHex = apnsHex
        }
        let fcmUnchanged = token == lastUploadedFCMToken
        let apnsUnchanged = apnsHex == nil || apnsHex == lastUploadedApnsToken
        guard !(fcmUnchanged && apnsUnchanged) else { return }
        guard let email = pendingEmail, email.contains("@") else { return }
        guard SupabaseConfig.isConfigured else { return }

        do {
            try await Self.invokeRegister(
                email: email,
                customerID: pendingCustomerID,
                fcmToken: token,
                apnsToken: apnsHex
            )
            lastUploadedFCMToken = token
            if let apnsHex {
                lastUploadedApnsToken = apnsHex
            }
            // #region agent log
            Self.agentDebugLog(
                hypothesisId: "A",
                location: "PushRegistrationService.uploadToken",
                message: "token upload ok",
                data: [
                    "fcmLen": token.count,
                    "apnsLen": apnsHex?.count ?? 0,
                    "hasApns": apnsHex != nil,
                ]
            )
            // #endregion
            #if DEBUG
            print(
                "Push tokens uploaded for \(email) (fcm \(token.prefix(12))… apns \(apnsHex?.prefix(12) ?? "nil")…)"
            )
            #endif
        } catch {
            // #region agent log
            Self.agentDebugLog(
                hypothesisId: "A",
                location: "PushRegistrationService.uploadToken",
                message: "token upload failed",
                data: ["error": error.localizedDescription]
            )
            // #endregion
            // Non-fatal — local notifications + in-app sheet still work.
            #if DEBUG
            print("Push token upload failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func invokeRegister(
        email: String,
        customerID: UUID?,
        fcmToken: String,
        apnsToken: String?
    ) async throws {
        try SupabaseConfig.validate()
        let supabaseURL = try SupabaseConfig.url
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("register-device-token")

        var body: [String: Any] = [
            "customer_email": email,
            "fcm_token": fcmToken,
            "platform": "ios",
        ]
        if let customerID {
            body["customer_id"] = customerID.uuidString
        }
        if let apnsToken, !apnsToken.isEmpty {
            body["apns_token"] = apnsToken
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        try SupabaseConfig.applyClientAPIHeaders(to: &request, authorizationBearer: nil)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PushRegistrationError.backend("Invalid response registering device token.")
        }
        guard http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw PushRegistrationError.backend("Token register failed (\(http.statusCode)). \(raw)")
        }
    }

    enum PushRegistrationError: LocalizedError {
        case backend(String)
        var errorDescription: String? {
            switch self {
            case .backend(let message): return message
            }
        }
    }

    // #region agent log
    private static func agentDebugLog(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any] = [:]
    ) {
        guard let url = URL(string: "http://127.0.0.1:7868/ingest/418cc6ba-2ec5-4f6d-aca9-699e1054421b") else {
            return
        }
        var payload: [String: Any] = [
            "sessionId": "0dc641",
            "runId": "pre-fix",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("0dc641", forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request).resume()
    }
    // #endregion
}

extension PushRegistrationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task { @MainActor in
            await self.uploadToken(fcmToken)
        }
    }
}

extension PushRegistrationService: UNUserNotificationCenterDelegate {
    /// Show banners while the app is foregrounded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
