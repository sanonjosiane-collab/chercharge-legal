//
//  CloudSyncService.swift
//  Chercharge
//
//  Syncs PersistedAppState to Cloud Firestore at users/{firebaseUID}.
//  Local AppPersistence remains the offline cache. Binary photos/videos are
//  never written to Firestore (they exceed request/document size limits).
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Observation

@Observable
@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    var syncError: String?
    var lastSyncedAt: Date?
    var isSyncing = false

    private var pushTask: Task<Void, Never>?
    private var activeUID: String?

    /// Lazily resolved so we never call Firestore before `FirebaseApp.configure()`.
    private var db: Firestore {
        AuthService.configureFirebaseIfNeeded()
        return Firestore.firestore()
    }

    private static let payloadKey = "payloadJSON"
    private static let updatedAtKey = "updatedAt"
    private static let debounceNanoseconds: UInt64 = 800_000_000

    var isEnabled: Bool {
        AuthService.configureFirebaseIfNeeded()
        guard FirebaseApp.app() != nil, FirebaseAppConfigured.isReady else { return false }
        return Auth.auth().currentUser != nil
    }

    var statusLabel: String {
        if isEnabled { return "Firestore" }
        return "On-device only"
    }

    func cancelPendingPush() {
        pushTask?.cancel()
        pushTask = nil
        activeUID = nil
    }

    /// Pull remote state. Returns nil when no document exists or sync is disabled.
    func pull(uid: String) async -> (state: PersistedAppState, updatedAt: Date?)? {
        guard isEnabled else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let snapshot = try await db.collection("users").document(uid).getDocument()
            guard snapshot.exists, let data = snapshot.data() else {
                syncError = nil
                return nil
            }
            guard let json = data[Self.payloadKey] as? String,
                  let payload = json.data(using: .utf8) else {
                syncError = "Cloud document is missing payload."
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedAppState.self, from: payload)
            let updatedAt = (data[Self.updatedAtKey] as? Timestamp)?.dateValue()
            syncError = nil
            lastSyncedAt = Date()
            return (state, updatedAt)
        } catch {
            syncError = error.localizedDescription
            return nil
        }
    }

    /// Immediate push (no debounce). Binary media is stripped — Firestore cannot hold multi‑MB photo/video blobs.
    func pushNow(uid: String, state: PersistedAppState) async {
        guard isEnabled else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let cloudState = state.strippingBinaryMediaForCloudSync()
            let data: Data = try await Task.detached(priority: .utility) {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                return try encoder.encode(cloudState)
            }.value
            // Firestore document limit is 1 MiB; Google API request limit is ~10 MiB.
            let softLimit = 900_000
            if data.count > softLimit {
                syncError =
                    "Cloud sync skipped: account data is still too large after removing photos (\(data.count) bytes). Clear old bookings or contact support."
                return
            }
            guard let json = String(data: data, encoding: .utf8) else {
                syncError = "Could not encode app state for cloud sync."
                return
            }
            try await db.collection("users").document(uid).setData([
                Self.payloadKey: json,
                Self.updatedAtKey: FieldValue.serverTimestamp(),
            ], merge: true)
            syncError = nil
            lastSyncedAt = Date()
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("payload size") {
                syncError =
                    "Cloud sync failed: data too large for Firestore. Photos stay on this device; try again after updating the app."
            } else {
                syncError = message
            }
        }
    }

    /// Debounced push so rapid BookingStore.persist() calls coalesce.
    func schedulePush(uid: String, state: PersistedAppState) {
        guard isEnabled else { return }
        activeUID = uid
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.pushNow(uid: uid, state: state)
        }
    }

    /// Removes the Firestore user document after account deletion.
    func deleteUserDocument(uid: String) async {
        cancelPendingPush()
        guard FirebaseApp.app() != nil else { return }
        do {
            try await db.collection("users").document(uid).delete()
            syncError = nil
        } catch {
            // Best-effort — auth deletion already proceeded.
            syncError = error.localizedDescription
        }
    }
}

/// Tiny helper so CloudSyncService can check Firebase without importing AuthService.
enum FirebaseAppConfigured {
    static var isReady: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
            && SecretsReader.string(for: "FIREBASE_ENABLED")?.lowercased() == "true"
    }
}
