//
//  AppLockController.swift
//  Chercharge
//
//  Locks the signed-in app behind Face ID when enabled in Privacy & Account.
//

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppLockController {
    var isLocked = false
    var isAuthenticating = false
    var lastError: String?

    func handleScenePhase(_ phase: ScenePhase, isSignedIn: Bool, faceIDEnabled: Bool) {
        guard isSignedIn, faceIDEnabled, BiometricAuthService.isBiometricsAvailable else {
            isLocked = false
            return
        }
        switch phase {
        case .background, .inactive:
            // Lock when leaving the active app so resume requires Face ID.
            if phase == .background {
                isLocked = true
            }
        case .active:
            break
        @unknown default:
            break
        }
    }

    func lockIfEnabled(isSignedIn: Bool, faceIDEnabled: Bool) {
        guard isSignedIn, faceIDEnabled, BiometricAuthService.isBiometricsAvailable else {
            isLocked = false
            return
        }
        isLocked = true
    }

    func unlockWithBiometrics() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let result = await BiometricAuthService.authenticate()
        switch result {
        case .success:
            isLocked = false
            lastError = nil
        case .failure(.cancelled):
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }
}
