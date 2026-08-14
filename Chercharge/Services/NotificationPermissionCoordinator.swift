//
//  NotificationPermissionCoordinator.swift
//  Chercharge
//
//  Shows an in-app explanation before the system notification permission prompt.
//  Service (transactional) notifications are separate from optional marketing.
//

import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class NotificationPermissionCoordinator {
    var isPresentingPrePrompt = false

    private static let prePromptCompletedKey = "chercharge.notifications.servicePrePromptCompleted"

    private var hasCompletedPrePrompt: Bool {
        get { UserDefaults.standard.bool(forKey: Self.prePromptCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.prePromptCompletedKey) }
    }

    /// After sign-in: explain service notifications before Apple’s dialog (once while undetermined).
    func considerPresentingAfterSignIn() async {
        guard !hasCompletedPrePrompt else { return }
        let status = await InspectionNotificationService.authorizationStatus()
        guard status == .notDetermined else {
            hasCompletedPrePrompt = true
            return
        }
        isPresentingPrePrompt = true
    }

    /// Settings toggle turned on while OS permission is still undetermined.
    func presentPrePromptForSettingsEnable() async {
        let status = await InspectionNotificationService.authorizationStatus()
        guard status == .notDetermined else { return }
        isPresentingPrePrompt = true
    }

    func enableServiceNotifications() async -> Bool {
        hasCompletedPrePrompt = true
        isPresentingPrePrompt = false
        return await InspectionNotificationService.requestAuthorization()
    }

    func deferServiceNotifications() {
        hasCompletedPrePrompt = true
        isPresentingPrePrompt = false
    }
}
