//
//  BiometricAuthService.swift
//  Chercharge
//
//  Face ID / Touch ID for account access and sensitive account actions.
//

import Foundation
import LocalAuthentication

enum BiometricAuthService {
    enum AuthError: LocalizedError {
        case unavailable
        case failed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Biometrics are not available on this device."
            case .failed(let message):
                return message
            case .cancelled:
                return "Authentication was cancelled."
            }
        }
    }

    /// Face ID, Touch ID, or Optic ID when enrolled.
    static var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    static var biometryDisplayName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "Biometrics"
        }
    }

    /// Reason shown in the system Face ID sheet — keep aligned with NSFaceIDUsageDescription intent.
    static let accountAccessReason =
        "Chercharge uses Face ID to help securely access your account and protect sensitive account actions."

    @MainActor
    static func authenticate(
        reason: String = accountAccessReason
    ) async -> Result<Void, AuthError> {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fall back to device passcode when biometrics aren't enrolled.
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                return .failure(.unavailable)
            }
            return await evaluate(context: context, policy: .deviceOwnerAuthentication, reason: reason)
        }
        return await evaluate(
            context: context,
            policy: .deviceOwnerAuthenticationWithBiometrics,
            reason: reason
        )
    }

    @MainActor
    private static func evaluate(
        context: LAContext,
        policy: LAPolicy,
        reason: String
    ) async -> Result<Void, AuthError> {
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            return success ? .success(()) : .failure(.failed("Authentication failed."))
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .failure(.cancelled)
            default:
                return .failure(.failed(error.localizedDescription))
            }
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }
}
