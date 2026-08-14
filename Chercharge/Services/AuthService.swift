//
//  AuthService.swift
//  Chercharge
//
//  Customer authentication:
//  - Firebase Auth when FIREBASE_ENABLED=true (Firestore sync)
//  - Supabase Auth when Secrets.plist is configured (Edge Functions / Founding Access)
//  - When both are configured, sign-in establishes BOTH sessions (same email/password)
//  - Local email/password (Keychain) as fully functional fallback
//

import FirebaseAuth
import FirebaseCore
import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AuthService {
    private let client = SupabaseClientProvider.shared

    var session: Session?
    /// Local / Firebase signed-in user when Supabase session isn't used.
    var localUserID: UUID?
    var localEmail: String?
    var localFullName: String?

    var isLoading = true
    var errorMessage: String?
    var configError: String?

    /// Backend mode shown in Settings.
    var authBackendLabel: String {
        if usesFirebase && hasSupabaseSession { return "Firebase + Supabase" }
        if usesFirebase { return "Firebase Auth" }
        if usesSupabase { return "Supabase Auth" }
        return "Local Auth"
    }

    var isSignedIn: Bool {
        session != nil || localUserID != nil
    }

    var userID: UUID? {
        session?.user.id ?? localUserID
    }

    /// Supabase Auth user id only (nil for local/Firebase-only sessions).
    var supabaseUserID: UUID? {
        session?.user.id
    }

    var displayEmail: String? {
        session?.user.email ?? localEmail
    }

    var displayName: String? {
        if let meta = session?.user.userMetadata["full_name"],
           case let .string(name) = meta {
            return name
        }
        return localFullName
    }

    /// Supabase access token for authenticated Edge Function calls (pre-order, etc.).
    var supabaseAccessToken: String? {
        session?.accessToken
    }

    var hasSupabaseSession: Bool {
        session != nil
    }

    /// Firebase is signed in but payments still need a Supabase JWT.
    var needsSupabaseLinkForPayments: Bool {
        usesSupabase
            && !hasSupabaseSession
            && localUserID != nil
            && !(localEmail?.hasSuffix("@chercharge.local") ?? false)
    }

    /// Firebase Auth UID for Firestore paths. Nil for guest / local / Supabase-only sessions.
    var firebaseUID: String? {
        guard usesFirebase else { return nil }
        Self.configureFirebaseIfNeeded()
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.uid
    }

    private var usesSupabase: Bool { configError == nil && SupabaseConfig.isConfigured }
    private var usesFirebase: Bool {
        SecretsReader.string(for: "FIREBASE_ENABLED")?.lowercased() == "true"
            && Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    init() {
        Self.configureFirebaseIfNeeded()
        do {
            try SupabaseConfig.validate()
        } catch {
            // Local / Firebase auth remains available — not a hard failure.
            configError = error.localizedDescription
        }
        Task { await restoreSession() }
    }

    /// Safe to call more than once; no-ops if already configured or disabled.
    static func configureFirebaseIfNeeded() {
        let enabled = SecretsReader.string(for: "FIREBASE_ENABLED")?.lowercased() == "true"
        guard enabled,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    func restoreSession() async {
        isLoading = true
        defer { isLoading = false }
        AppleReviewDemoAccount.isSessionActive = false

        // Prefer restoring the permanent App Store Review demo session (local, never expires).
        if let email = KeychainStore.string(forKey: "local.auth.email"),
           AppleReviewDemoAccount.isDemoEmail(email),
           KeychainStore.string(forKey: "local.auth.session") == "1" {
            await establishAppleReviewDemoSession()
            errorMessage = nil
            return
        }

        if usesFirebase {
            Self.configureFirebaseIfNeeded()
            guard FirebaseApp.app() != nil else {
                clearLocalSession()
                session = nil
                return
            }
            if let user = Auth.auth().currentUser {
                applyFirebaseUser(user)
                if usesSupabase {
                    // Never hang forever on a stalled Supabase session restore.
                    do {
                        session = try await TaskTimeout.run(seconds: 6) { [client] in
                            try await client.auth.session
                        }
                    } catch {
                        session = nil
                    }
                }
                errorMessage = nil
                return
            }
            clearLocalSession()
        }

        if usesSupabase {
            do {
                session = try await TaskTimeout.run(seconds: 6) { [client] in
                    try await client.auth.session
                }
                clearLocalSession()
                errorMessage = nil
                return
            } catch {
                session = nil
            }
        }

        // Restore local session.
        if let email = KeychainStore.string(forKey: "local.auth.email"),
           let idString = KeychainStore.string(forKey: "local.auth.userID"),
           let id = UUID(uuidString: idString),
           KeychainStore.string(forKey: "local.auth.session") == "1" {
            localUserID = id
            localEmail = email
            localFullName = KeychainStore.string(forKey: "local.auth.fullName")
            AppleReviewDemoAccount.isSessionActive = AppleReviewDemoAccount.isDemoEmail(email)
        }
    }

    func signUp(email: String, password: String, fullName: String) async {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)

        if AppleReviewDemoAccount.isDemoEmail(trimmedEmail) {
            errorMessage = "That email is reserved for App Store Review. Sign in with the review credentials instead."
            return
        }

        if usesFirebase {
            do {
                let result = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
                if !trimmedName.isEmpty {
                    let change = result.user.createProfileChangeRequest()
                    change.displayName = trimmedName
                    try await change.commitChanges()
                }
                applyFirebaseUser(result.user, fallbackName: trimmedName)
                await ensureSupabaseSession(
                    email: trimmedEmail,
                    password: password,
                    fullName: trimmedName,
                    allowSignUp: true
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        if usesSupabase {
            do {
                let response = try await client.auth.signUp(
                    email: trimmedEmail,
                    password: password,
                    data: ["full_name": .string(trimmedName)]
                )
                session = response.session
                if session == nil {
                    session = try? await client.auth.session
                }
                if session == nil {
                    errorMessage = "Account created. If email confirmation is enabled, confirm then sign in."
                }
                clearLocalSession()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        // Local account
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        guard trimmedEmail.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }

        let existing = KeychainStore.string(forKey: "local.account.\(trimmedEmail).password")
        if existing != nil {
            errorMessage = "An account with this email already exists. Sign in instead."
            return
        }

        let id = UUID()
        KeychainStore.set(password, forKey: "local.account.\(trimmedEmail).password")
        KeychainStore.set(id.uuidString, forKey: "local.account.\(trimmedEmail).id")
        KeychainStore.set(trimmedName, forKey: "local.account.\(trimmedEmail).name")
        establishLocalSession(id: id, email: trimmedEmail, fullName: trimmedName)
        session = nil
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Permanent App Store Review account — local session + await Supabase for payments.
        if AppleReviewDemoAccount.matches(email: trimmedEmail, password: password) {
            await establishAppleReviewDemoSession()
            errorMessage = nil
            return
        }

        if usesFirebase {
            do {
                let result = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password)
                AppleReviewDemoAccount.isSessionActive = false
                applyFirebaseUser(result.user)
                await ensureSupabaseSession(
                    email: trimmedEmail,
                    password: password,
                    fullName: result.user.displayName ?? "",
                    allowSignUp: true
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        if usesSupabase {
            do {
                session = try await client.auth.signIn(email: trimmedEmail, password: password)
                AppleReviewDemoAccount.isSessionActive = false
                clearLocalSession()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        guard let stored = KeychainStore.string(forKey: "local.account.\(trimmedEmail).password") else {
            errorMessage = "No account found for that email. Create one with Sign up."
            return
        }
        guard stored == password else {
            errorMessage = "Incorrect password."
            return
        }

        let idString = KeychainStore.string(forKey: "local.account.\(trimmedEmail).id") ?? UUID().uuidString
        let id = UUID(uuidString: idString) ?? UUID()
        let name = KeychainStore.string(forKey: "local.account.\(trimmedEmail).name") ?? trimmedEmail
        AppleReviewDemoAccount.isSessionActive = false
        establishLocalSession(id: id, email: trimmedEmail, fullName: name)
        session = nil
    }

    /// One-tap App Store Review sandbox sign-in (no credentials entry).
    func signInAsAppleReviewer() {
        errorMessage = nil
        Task { await establishAppleReviewDemoSession() }
    }

    /// Links Supabase for Founding Access when the user is already on Firebase-only auth.
    func linkSupabaseForPayments(password: String) async -> Bool {
        errorMessage = nil
        guard usesSupabase else {
            errorMessage = "Supabase is not configured."
            return false
        }
        guard let email = localEmail ?? displayEmail, !email.isEmpty else {
            errorMessage = "Sign in with email first, then try again."
            return false
        }
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            errorMessage = "Enter the password for \(email)."
            return false
        }
        await ensureSupabaseSession(
            email: email.lowercased(),
            password: trimmed,
            fullName: localFullName ?? "",
            allowSignUp: true
        )
        if hasSupabaseSession {
            errorMessage = nil
            return true
        }
        if errorMessage == nil {
            errorMessage = "Could not enable payments for this account. Check your password and try again."
        }
        return false
    }

    /// Continues as a guest without creating credentials (still enters the app).
    func continueAsGuest(name: String = "Guest") {
        errorMessage = nil
        AppleReviewDemoAccount.isSessionActive = false
        session = nil
        let id = UUID()
        let email = "guest-\(id.uuidString.prefix(8))@chercharge.local"
        establishLocalSession(id: id, email: email, fullName: name)
    }

    func signOut() async {
        errorMessage = nil
        AppleReviewDemoAccount.isSessionActive = false
        CloudSyncService.shared.cancelPendingPush()
        if usesFirebase {
            do {
                try Auth.auth().signOut()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if usesSupabase, session != nil {
            do {
                try await client.auth.signOut()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        session = nil
        clearLocalSession()
        KeychainStore.delete(forKey: "local.auth.session")
        KeychainStore.delete(forKey: "local.auth.email")
        KeychainStore.delete(forKey: "local.auth.userID")
        KeychainStore.delete(forKey: "local.auth.fullName")
    }

    /// Permanently deletes the signed-in Chercharge account across Firebase, Supabase, and local storage.
    /// - Parameter password: Required to re-authenticate email accounts (not guest).
    @discardableResult
    func deleteAccount(password: String) async -> Bool {
        errorMessage = nil
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (displayEmail ?? localEmail)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isGuest = email?.hasSuffix("@chercharge.local") == true
        let isAppleReviewDemo = AppleReviewDemoAccount.isDemoEmail(email)

        // App Review demo is a permanent local sandbox — do not destroy credentials.
        if isAppleReviewDemo {
            errorMessage = "The App Store Review demo account cannot be deleted. Sign out instead."
            return false
        }

        if !isGuest {
            guard let email, !email.isEmpty else {
                errorMessage = "No account email found. Sign in again, then retry."
                return false
            }
            guard trimmedPassword.count >= 6 else {
                errorMessage = "Enter your account password to confirm deletion."
                return false
            }
        }

        let firebaseUIDToDelete = firebaseUID
        let firebaseUser = usesFirebase ? Auth.auth().currentUser : nil

        // 1) Reauthenticate Firebase early (required before delete; keeps session until later).
        if let user = firebaseUser, !isGuest {
            do {
                guard let email else { return false }
                let credential = EmailAuthProvider.credential(withEmail: email, password: trimmedPassword)
                try await user.reauthenticate(with: credential)
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }

        // 2) Ensure Supabase JWT, then delete Auth user (cascades profile data).
        if usesSupabase {
            if session == nil, !isGuest, let email {
                await ensureSupabaseSession(
                    email: email,
                    password: trimmedPassword,
                    fullName: localFullName ?? "",
                    allowSignUp: false
                )
            }
            if let token = supabaseAccessToken {
                do {
                    try await invokeDeleteAccount(token: token)
                    session = nil
                } catch {
                    errorMessage = error.localizedDescription
                    return false
                }
            } else if !isGuest, firebaseUser == nil {
                errorMessage = "Could not verify your Chercharge account session for deletion."
                return false
            }
        }

        // 3) Delete Firebase Auth user
        if let user = firebaseUser, !isGuest {
            do {
                try await user.delete()
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }

        // 4) Local Keychain account (email/password fallback)
        if let email, !isGuest {
            KeychainStore.delete(forKey: "local.account.\(email).password")
            KeychainStore.delete(forKey: "local.account.\(email).id")
            KeychainStore.delete(forKey: "local.account.\(email).name")
            if let uid = firebaseUIDToDelete {
                KeychainStore.delete(forKey: "firebase.uid.\(uid).uuid")
            }
        } else if isGuest {
            // Guest has no remote account — clearing session is enough.
        }

        // 5) Firestore user document (best effort)
        if let uid = firebaseUIDToDelete {
            await CloudSyncService.shared.deleteUserDocument(uid: uid)
        }

        // 6) Clear session flags
        CloudSyncService.shared.cancelPendingPush()
        session = nil
        clearLocalSession()
        KeychainStore.delete(forKey: "local.auth.session")
        KeychainStore.delete(forKey: "local.auth.email")
        KeychainStore.delete(forKey: "local.auth.userID")
        KeychainStore.delete(forKey: "local.auth.fullName")
        errorMessage = nil
        return true
    }

    private func invokeDeleteAccount(token: String) async throws {
        let supabaseURL = try SupabaseConfig.url
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("delete-account")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try SupabaseConfig.applyClientAPIHeaders(to: &request, authorizationBearer: token)
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeleteAccountError.backend("Invalid response from account server.")
        }
        if http.statusCode == 200 { return }

        if let decoded = try? JSONDecoder().decode(DeleteAccountErrorBody.self, from: data),
           let message = decoded.error {
            throw DeleteAccountError.backend(message)
        }
        throw DeleteAccountError.backend("Account deletion failed (\(http.statusCode)).")
    }

    // MARK: - Private

    /// Sign in (or create) the matching Supabase user so Edge Functions get a JWT.
    private func ensureSupabaseSession(
        email: String,
        password: String,
        fullName: String,
        allowSignUp: Bool
    ) async {
        guard usesSupabase else { return }

        do {
            session = try await client.auth.signIn(email: email, password: password)
            return
        } catch {
            guard allowSignUp else {
                errorMessage = error.localizedDescription
                return
            }
        }

        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(fullName)]
            )
            session = response.session
            if session == nil {
                session = try? await client.auth.session
            }
            if session == nil {
                // Account may need email confirmation; try sign-in in case confirmations are off.
                session = try? await client.auth.signIn(email: email, password: password)
            }
            if session == nil {
                errorMessage =
                    "Account linked, but email confirmation may be required before Founding Access payment works."
            }
        } catch {
            // Keep Firebase session; surface why payments may still be blocked.
            errorMessage = error.localizedDescription
        }
    }

    private func applyFirebaseUser(_ user: FirebaseAuth.User, fallbackName: String = "") {
        let id = uuidForFirebaseUID(user.uid)
        let email = user.email ?? ""
        let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? email
        establishLocalSession(id: id, email: email, fullName: name)
    }

    /// Stable UUID mapped to a Firebase UID (Firebase UIDs are not UUID-formatted).
    private func uuidForFirebaseUID(_ uid: String) -> UUID {
        let key = "firebase.uid.\(uid).uuid"
        if let existing = KeychainStore.string(forKey: key),
           let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let uuid = UUID()
        KeychainStore.set(uuid.uuidString, forKey: key)
        return uuid
    }

    private func establishLocalSession(id: UUID, email: String, fullName: String) {
        localUserID = id
        localEmail = email
        localFullName = fullName
        KeychainStore.set("1", forKey: "local.auth.session")
        KeychainStore.set(email, forKey: "local.auth.email")
        KeychainStore.set(id.uuidString, forKey: "local.auth.userID")
        KeychainStore.set(fullName, forKey: "local.auth.fullName")
    }

    /// Local App Store Review sign-in, then link Supabase so Founding Access uses live Stripe like any customer.
    private func establishAppleReviewDemoSession() async {
        session = nil
        AppleReviewDemoAccount.isSessionActive = true
        establishLocalSession(
            id: AppleReviewDemoAccount.userID,
            email: AppleReviewDemoAccount.email,
            fullName: AppleReviewDemoAccount.displayName
        )
        // Await so Accept & Pay has a JWT ready (or a clear failure) instead of racing a background Task.
        await ensureSupabaseSession(
            email: AppleReviewDemoAccount.email,
            password: AppleReviewDemoAccount.password,
            fullName: AppleReviewDemoAccount.displayName,
            allowSignUp: true
        )
        // Review can still use Stripe PaymentSheet without a JWT via create-payment-intent.
        // Don't leave a blocking auth error on the Sign In screen after a successful local review login.
        if hasSupabaseSession || AppleReviewDemoAccount.isSessionActive {
            errorMessage = nil
        }
    }

    private func clearLocalSession() {
        localUserID = nil
        localEmail = nil
        localFullName = nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum DeleteAccountError: LocalizedError {
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .backend(let message): return message
        }
    }
}

private struct DeleteAccountErrorBody: Decodable {
    let error: String?
}
