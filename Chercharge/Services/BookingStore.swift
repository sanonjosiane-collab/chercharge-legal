//
//  BookingStore.swift
//  Chercharge
//

import Foundation
import Observation
import UserNotifications

/// Customer booking store with local persistence and optional Firestore sync
/// when the user is signed in with Firebase Auth.
@Observable
@MainActor
final class BookingStore {
    let station: LocationPin = SampleLocations.station
    let chargingStations: [ChargingStation] = SampleMapData.chargingStations
    let nearbyDrivers: [NearbyDriver] = SampleMapData.nearbyDrivers
    let assignedDriverName = "Alex Rivera"

    var vehicles: [Vehicle] = []
    var savedAddresses: [LocationPin] = []
    var activeJob: ChargeJob?
    var lastCompletedJob: ChargeJob?
    var pastJobs: [ChargeJob] = []
    var upcomingJobs: [ChargeJob] = []
    var isLoading = false
    var errorMessage: String?
    /// False until on-disk state (including embedded photos) has been applied.
    var isHydrated = false

    var profileName = ""
    var profileEmail = ""
    var profilePhone = ""
    var profilePhotoData: Data?

    var paymentMethods: [SavedPaymentMethod] = []
    var membership: MembershipState = .standard
    var preorder: PreorderState = PreorderState()
    var preorderQuote: PreorderQuote?
    var settings: AppSettings = .default
    var supportTickets: [SupportTicket] = []

    /// Non-fatal cloud sync status for Settings.
    var cloudSyncLabel: String = "On-device only"
    var cloudSyncError: String?

    /// When true, UI should present the service-notification pre-permission sheet.
    var shouldOfferNotificationPrePrompt = false

    /// Device-wide admin inbox (injected from CherchargeApp). Not cleared on sign-out.
    @ObservationIgnored private var documentInbox: DocumentReviewInbox?
    /// Home bell inbox for customer-facing admin decisions.
    @ObservationIgnored private var customerNotifications: CustomerNotificationInbox?

    @ObservationIgnored private var progressionTask: Task<Void, Never>?
    @ObservationIgnored private var cloudBookingSyncTask: Task<Void, Never>?
    @ObservationIgnored private var approvalTimerTask: Task<Void, Never>?
    @ObservationIgnored private var documentSyncGeneration = 0
    @ObservationIgnored private var isCompletingDriverPreTrip = false
    @ObservationIgnored private var isCompletingDriverPostTrip = false
    @ObservationIgnored private var suppressPersist = false
    @ObservationIgnored private var localStateUpdatedAt = Date()
    @ObservationIgnored private var hadExistingLocalFile = false
    @ObservationIgnored private var cloudUID: String?
    /// When true, auto status progression pauses so the driver console can advance steps.
    var driverManualControl = false
    /// Non-fatal message when driver dispatch fails after payment.
    var bookingDispatchError: String?

    init() {
        suppressPersist = true
        // fileExists only — never decode the photo-heavy JSON twice at launch.
        hadExistingLocalFile = AppPersistence.fileExists
        profilePhotoData = Self.loadProfilePhoto()

        if hadExistingLocalFile {
            // Paint the splash while decoding off the main thread.
            isHydrated = false
            suppressPersist = false
            Task { await hydrateFromDisk() }
        } else {
            loadPersistedState()
            isHydrated = true
            suppressPersist = false
            persist()
        }
    }

    /// Decode persisted JSON (often photo-heavy) off the main thread, then apply once.
    private func hydrateFromDisk() async {
        let loaded = await AppPersistence.loadAsync()
        suppressPersist = true
        if let loaded {
            apply(loaded)
            applyPendingPreorderResetIfNeeded()
        } else {
            // Corrupt / unreadable file — start clean rather than hang.
            hadExistingLocalFile = false
            loadPersistedState()
        }
        isHydrated = true
        suppressPersist = false
        persist()
    }

    /// Pull admin Approve/Reject (and enqueue new pending docs).
    /// - Parameter preferredEmail: Auth email override when profile email is empty/stale.
    func syncVehicleDocumentsWithAdmin(
        customerID: UUID?,
        preferredEmail: String? = nil
    ) async {
        // Coalesce rapid callers without cancelling an in-flight apply (that dropped decisions).
        documentSyncGeneration += 1
        let generation = documentSyncGeneration
        try? await Task.sleep(for: .milliseconds(250))
        guard generation == documentSyncGeneration else { return }
        await performVehicleDocumentSync(
            customerID: customerID,
            preferredEmail: preferredEmail
        )
    }

    private func performVehicleDocumentSync(
        customerID: UUID?,
        preferredEmail: String?
    ) async {
        guard CustomerVehicleDocumentService.shared.isAvailable else { return }

        let email = resolvedDocumentSyncEmail(preferredEmail: preferredEmail)
        guard email.contains("@"), !email.hasSuffix("@chercharge.local") else {
            documentCloudSyncError =
                "Sign in with email and password (not Guest) so admin can review documents."
            return
        }
        if profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profileEmail = email
        }

        // 1) Pull admin decisions FIRST — never re-upsert before reading, or Approve/Reject is wiped.
        var cloudByVehicleID: [UUID: CustomerVehicleDocumentDTO] = [:]
        var lastError: String?
        do {
            let rows = try await CustomerVehicleDocumentService.shared.fetchStatusesByEmail(
                email: email,
                localVehicleIDs: vehicles.map(\.id)
            )
            var changed = false
            for row in rows {
                cloudByVehicleID[row.localVehicleId] = row
                guard let index = vehicles.firstIndex(where: {
                    $0.id == row.localVehicleId
                }) else { continue }

                let current = vehicles[index]
                let nextStatus = row.approvalStatus
                guard nextStatus == .approved || nextStatus == .rejected else { continue }

                let statusChanged = current.documentApprovalStatus != nextStatus
                let reasonChanged = current.documentRejectionReason != row.reviewerNote
                guard statusChanged || reasonChanged else { continue }

                vehicles[index] = current.withDocumentApproval(
                    status: nextStatus,
                    submittedAt: current.documentsSubmittedAt ?? row.submittedAt,
                    reviewedAt: row.reviewedAt ?? Date(),
                    rejectionReason: nextStatus == .rejected ? row.reviewerNote : nil
                )
                changed = true
                if statusChanged {
                    let approved = nextStatus == .approved
                    let reason = nextStatus == .rejected ? row.reviewerNote : nil
                    customerNotifications?.post(
                        .documentsDecision(
                            vehicleID: current.id,
                            vehicleName: current.displayName,
                            approved: approved,
                            reason: reason
                        )
                    )
                    InspectionNotificationService.notifyVehicleDocumentsDecision(
                        vehicleID: current.id,
                        vehicleName: current.displayName,
                        approved: approved,
                        reason: reason
                    )
                }
            }
            if changed {
                persist()
                // Keep Firestore from overwriting an approval with a stale pending snapshot.
                if let uid = cloudUID {
                    await CloudSyncService.shared.pushNow(
                        uid: uid,
                        state: currentPersistedState()
                    )
                }
            }
            documentCloudSyncError = nil
        } catch {
            lastError = error.localizedDescription
        }

        // 2) Only enqueue vehicles that still need review AND are not already on the admin queue.
        for vehicle in vehicles where vehicle.documentApprovalStatus == .pendingReview {
            if let cloud = cloudByVehicleID[vehicle.id],
               cloud.approvalStatus == .pendingReview
                || cloud.approvalStatus == .approved
                || cloud.approvalStatus == .rejected {
                continue
            }
            do {
                _ = try await CustomerVehicleDocumentService.shared.submitForAdminReview(
                    vehicle: vehicle,
                    customerID: customerID,
                    customerName: profileName,
                    customerEmail: email
                )
            } catch {
                lastError = error.localizedDescription
            }
        }

        documentCloudSyncError = lastError
    }

    private func resolvedDocumentSyncEmail(preferredEmail: String?) -> String {
        let candidates = [
            preferredEmail,
            profileEmail,
        ]
        for raw in candidates {
            let email = (raw ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if email.contains("@"), !email.hasSuffix("@chercharge.local") {
                return email
            }
        }
        return ""
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        let state = AppPersistence.load() ?? {
            var fresh = AppPersistence.makeDefault()
            // Seed sample history only on first launch when live concierge demos are enabled.
            if CherchargeServiceAvailability.isLiveConciergeAvailable {
                let vehicle = SampleVehicles.all[0]
                let pickup = SampleLocations.pickups[0]
                let quote = Pricing.quote(from: vehicle.currentChargePercent, to: 80, membership: .standard)
                fresh.upcomingJobs = [
                    ChargeJob(
                        id: UUID(uuidString: "C1111111-1111-1111-1111-111111111111")!,
                        vehicle: vehicle,
                        pickup: pickup,
                        station: SampleLocations.station,
                        targetChargePercent: 80,
                        startingChargePercent: vehicle.currentChargePercent,
                        status: .requested,
                        estimatedPrice: quote.price,
                        estimatedMinutes: quote.estimatedMinutes,
                        createdAt: Date().addingTimeInterval(60 * 60 * 3),
                        receiptNumber: nil,
                        scheduledFor: Date().addingTimeInterval(60 * 60 * 3)
                    )
                ]
                let completedVehicle = SampleVehicles.all[1]
                let completedQuote = Pricing.quote(from: 22, to: 90, membership: .standard)
                fresh.pastJobs = [
                    ChargeJob(
                        id: UUID(uuidString: "C2222222-2222-2222-2222-222222222222")!,
                        vehicle: completedVehicle,
                        pickup: SampleLocations.pickups[1],
                        station: SampleLocations.station,
                        targetChargePercent: 90,
                        startingChargePercent: 22,
                        status: .delivered,
                        estimatedPrice: completedQuote.price,
                        estimatedMinutes: completedQuote.estimatedMinutes,
                        createdAt: Date().addingTimeInterval(-60 * 60 * 26),
                        paymentIntentID: "pi_local_seed",
                        paymentMethodLabel: "Visa •••• 4242",
                        receiptNumber: "CH-2026-100001",
                        completedAt: Date().addingTimeInterval(-60 * 60 * 24)
                    )
                ]
            }
            return fresh
        }()

        apply(state)
        applyPendingPreorderResetIfNeeded()
        persist()
    }

    /// One-time local reset so the pre-order screen can be used again after testing.
    private static let preorderResetTokenKey = "chercharge.preorder.reset.token"
    /// Bump this whenever stuck local founding state must be cleared for all installs.
    private static let preorderResetToken = "2026-07-14-live-stripe-pay-v2"

    /// Public wrapper so Pre-order can force the one-time stuck-state reset.
    func applyPendingPreorderResetIfNeededPublic() {
        applyPendingPreorderResetIfNeeded()
    }

    private func applyPendingPreorderResetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.preorderResetTokenKey) != Self.preorderResetToken else { return }
        preorder = PreorderState()
        preorderQuote = nil
        defaults.set(Self.preorderResetToken, forKey: Self.preorderResetTokenKey)
    }

    func resetPreorder() {
        preorder = PreorderState()
        preorderQuote = nil
        persist()
    }

    /// Wipes on-device customer data after the auth account is deleted.
    func clearAfterAccountDeletion() {
        progressionTask?.cancel()
        progressionTask = nil
        cloudBookingSyncTask?.cancel()
        cloudBookingSyncTask = nil
        approvalTimerTask?.cancel()
        approvalTimerTask = nil
        CloudSyncService.shared.cancelPendingPush()
        cloudUID = nil
        cloudSyncLabel = "On-device only"
        cloudSyncError = nil
        AppleReviewDemoAccount.isSessionActive = false
        AppPersistence.clear()
        hadExistingLocalFile = false
        apply(AppPersistence.makeDefault())
        profilePhotoData = nil
        preorderQuote = nil
        errorMessage = nil
        isHydrated = true
        localStateUpdatedAt = Date()
    }

    /// Attach the shared admin document inbox and sync pending garage vehicles into it.
    func bindDocumentInbox(_ inbox: DocumentReviewInbox) {
        documentInbox = inbox
        reconcileDocumentInbox()
    }

    func bindCustomerNotifications(_ inbox: CustomerNotificationInbox) {
        customerNotifications = inbox
    }

    private func reconcileDocumentInbox() {
        guard let inbox = documentInbox else { return }
        if inbox.applyDecisions(to: &vehicles) {
            // Decisions applied from admin — persist garage without re-enqueue loops.
            persist()
        }
        inbox.backfill(
            from: vehicles,
            customerName: profileName,
            customerEmail: profileEmail
        )
    }

    private func enqueueDocumentReviewIfNeeded(for vehicle: Vehicle) {
        documentInbox?.enqueueSubmission(
            for: vehicle,
            customerName: profileName,
            customerEmail: profileEmail
        )
    }

    /// Last cloud document-submit error for UI (cleared on success).
    var documentCloudSyncError: String?

    private func apply(_ state: PersistedAppState) {
        profileName = state.profileName
        profileEmail = state.profileEmail
        profilePhone = state.profilePhone
        vehicles = state.vehicles
        savedAddresses = state.savedAddresses
        activeJob = state.activeJob
        lastCompletedJob = state.lastCompletedJob
        pastJobs = state.pastJobs
        upcomingJobs = state.upcomingJobs
        paymentMethods = state.paymentMethods
        membership = state.membership
        preorder = state.preorder ?? PreorderState()
        // Migrate older “$10 credit” founding completions to locked per-charge rates.
        if preorder.isCompleted, preorder.lockedTier == nil {
            let inferredPaid = preorder.paidAmount > 0 ? preorder.paidAmount : preorder.accountCredit
            preorder.lockedTier = PreOrderService.inferredLockedTier(paidAmount: inferredPaid)
                ?? (preorder.promoApplied ? .lifetime : nil)
            if preorder.lockedTier != nil {
                preorder.accountCredit = 0
                preorder.creditConsumed = true
            }
        }
        settings = state.settings
        supportTickets = state.supportTickets

        if CherchargeServiceAvailability.isLiveConciergeAvailable {
            if let job = activeJob, job.isActive {
                if job.isCloudDispatched {
                    startCloudBookingSync()
                } else {
                    startProgression()
                }
                resumeApprovalTimerIfNeeded()
            }
        } else if activeJob != nil {
            // Do not resume simulated live trips while concierge service is offline.
            progressionTask?.cancel()
            progressionTask = nil
            approvalTimerTask?.cancel()
            approvalTimerTask = nil
            activeJob = nil
        }

        reconcileDocumentInbox()
    }

    func persist() {
        guard !suppressPersist else { return }
        localStateUpdatedAt = Date()
        let state = currentPersistedState()
        AppPersistence.save(state)
        if let uid = cloudUID {
            CloudSyncService.shared.schedulePush(uid: uid, state: state)
        }
    }

    private func currentPersistedState() -> PersistedAppState {
        PersistedAppState(
            profileName: profileName,
            profileEmail: profileEmail,
            profilePhone: profilePhone,
            vehicles: vehicles,
            savedAddresses: savedAddresses,
            activeJob: activeJob,
            lastCompletedJob: lastCompletedJob,
            pastJobs: pastJobs,
            upcomingJobs: upcomingJobs,
            paymentMethods: paymentMethods,
            membership: membership,
            preorder: preorder,
            settings: settings,
            supportTickets: supportTickets,
            teslaConnected: false,
            teslaEmail: nil,
            hasCompletedOnboarding: true
        )
    }

    /// Pull/merge Firestore state for a Firebase Auth user. Call after sign-in.
    func reloadFromCloud(firebaseUID: String?, displayName: String?, displayEmail: String?) async {
        if AppleReviewDemoAccount.isSessionActive || AppleReviewDemoAccount.isDemoEmail(displayEmail) {
            AppleReviewDemoAccount.isSessionActive = true
            cloudUID = nil
            cloudSyncLabel = "On-device"
            CloudSyncService.shared.cancelPendingPush()
            // Keep any real progress (e.g. Founding paid via Stripe). Only seed a blank
            // customer profile the first time this review account lands on an empty install.
            let isBlankCustomer = vehicles.isEmpty
                && pastJobs.isEmpty
                && upcomingJobs.isEmpty
                && activeJob == nil
                && !hasCompletedFoundingAccess
            if isBlankCustomer {
                applyAppleReviewDemoProfile()
            } else {
                if profileEmail.isEmpty {
                    profileEmail = displayEmail ?? AppleReviewDemoAccount.email
                }
                if profileName.isEmpty {
                    profileName = displayName ?? AppleReviewDemoAccount.displayName
                }
                persist()
            }
            return
        }

        cloudUID = firebaseUID
        cloudSyncLabel = firebaseUID != nil ? "Firestore" : "On-device only"
        guard let uid = firebaseUID else {
            CloudSyncService.shared.cancelPendingPush()
            applySignedInUser(name: displayName, email: displayEmail)
            return
        }

        suppressPersist = true
        defer { suppressPersist = false }

        if let remote = await CloudSyncService.shared.pull(uid: uid) {
            cloudSyncError = CloudSyncService.shared.syncError
            let preferRemote = !hadExistingLocalFile
                || remote.updatedAt.map { $0 >= localStateUpdatedAt } ?? true
            if preferRemote {
                let localSnapshot = currentPersistedState()
                apply(remote.state.rehydratingBinaryMedia(from: localSnapshot))
                clearUnverifiedLocalPreorderIfNeeded()
                if profileName.isEmpty || profileName == "Josiane",
                   let displayName, !displayName.isEmpty {
                    profileName = displayName
                }
                if profileEmail.isEmpty || profileEmail.contains("example.com"),
                   let displayEmail, !displayEmail.isEmpty {
                    profileEmail = displayEmail
                }
                AppPersistence.save(currentPersistedState())
                hadExistingLocalFile = true
                localStateUpdatedAt = remote.updatedAt ?? Date()
                return
            }
        } else {
            cloudSyncError = CloudSyncService.shared.syncError
        }

        applySignedInUser(name: displayName, email: displayEmail)
        await CloudSyncService.shared.pushNow(uid: uid, state: currentPersistedState())
        cloudSyncError = CloudSyncService.shared.syncError
        hadExistingLocalFile = true
    }

    func stopCloudSync() {
        cloudUID = nil
        cloudSyncLabel = "On-device only"
        CloudSyncService.shared.cancelPendingPush()
    }

    func clearBookingHistory() {
        progressionTask?.cancel()
        progressionTask = nil
        cloudBookingSyncTask?.cancel()
        cloudBookingSyncTask = nil
        approvalTimerTask?.cancel()
        approvalTimerTask = nil
        pastJobs = []
        lastCompletedJob = nil
        upcomingJobs = []
        activeJob = nil
        errorMessage = nil
        bookingDispatchError = nil
        persist()
    }

    /// Clears the active trip and any scheduled pickups so Book a Charge is available again.
    func clearOpenBookings() {
        progressionTask?.cancel()
        progressionTask = nil
        cloudBookingSyncTask?.cancel()
        cloudBookingSyncTask = nil
        approvalTimerTask?.cancel()
        approvalTimerTask = nil
        activeJob = nil
        upcomingJobs = []
        errorMessage = nil
        bookingDispatchError = nil
        persist()
        if let uid = cloudUID {
            Task {
                await CloudSyncService.shared.pushNow(uid: uid, state: currentPersistedState())
            }
        }
    }

    // MARK: - Profile

    func updateProfile(name: String, email: String, phone: String) {
        profileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profileEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        profilePhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func applySignedInUser(name: String?, email: String?) {
        var changed = false
        if let name, !name.isEmpty, profileName != name {
            profileName = name
            changed = true
        }
        if let email, !email.isEmpty, profileEmail != email {
            profileEmail = email
            changed = true
        }
        if changed { persist() }
    }

    /// Resets on-device state for the App Review sign-in account (fresh customer, no auto Founding).
    func applyAppleReviewDemoProfile() {
        progressionTask?.cancel()
        progressionTask = nil
        cloudBookingSyncTask?.cancel()
        cloudBookingSyncTask = nil
        approvalTimerTask?.cancel()
        approvalTimerTask = nil
        CloudSyncService.shared.cancelPendingPush()
        cloudUID = nil
        cloudSyncLabel = "On-device"
        cloudSyncError = nil
        AppleReviewDemoAccount.isSessionActive = true

        suppressPersist = true
        apply(AppleReviewDemoAccount.freshPersistedState())
        profilePhotoData = nil
        preorderQuote = nil
        errorMessage = nil
        bookingDispatchError = nil
        hadExistingLocalFile = true
        localStateUpdatedAt = Date()
        suppressPersist = false
        persist()
    }

    func setProfilePhoto(_ data: Data) {
        profilePhotoData = data
        Self.saveProfilePhoto(data)
    }

    func clearProfilePhoto() {
        profilePhotoData = nil
        Self.deleteProfilePhoto()
    }

    private static var profilePhotoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile-photo.jpg")
    }

    private static func loadProfilePhoto() -> Data? {
        try? Data(contentsOf: profilePhotoURL)
    }

    private static func saveProfilePhoto(_ data: Data) {
        try? data.write(to: profilePhotoURL, options: .atomic)
    }

    private static func deleteProfilePhoto() {
        try? FileManager.default.removeItem(at: profilePhotoURL)
    }

    // MARK: - Settings / membership / payments / support

    func updateSettings(_ newSettings: AppSettings) {
        let enablingPush = newSettings.pushNotificationsEnabled && !settings.pushNotificationsEnabled
        let enablingInspectionAlerts =
            newSettings.inspectionAlertsEnabled && !settings.inspectionAlertsEnabled
        settings = newSettings
        persist()

        if enablingPush || enablingInspectionAlerts {
            Task {
                let status = await InspectionNotificationService.authorizationStatus()
                switch status {
                case .authorized, .provisional, .ephemeral:
                    await PushRegistrationService.shared.refreshRegistration(
                        customerEmail: profileEmail,
                        customerID: nil,
                        optIn: true
                    )
                case .notDetermined:
                    // Revert preference until the in-app pre-prompt + system dialog complete.
                    if enablingPush {
                        settings.pushNotificationsEnabled = false
                        persist()
                        shouldOfferNotificationPrePrompt = true
                    }
                case .denied:
                    if enablingPush {
                        settings.pushNotificationsEnabled = false
                        persist()
                        errorMessage =
                            "Notifications are off in iOS Settings. Enable them for Chercharge to get booking updates."
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    func setMembershipTier(_ tier: MembershipTier) {
        membership.tier = tier
        if tier != .standard {
            membership.renewsAt = Calendar.current.date(byAdding: .month, value: 1, to: Date())
        } else {
            membership.renewsAt = nil
            membership.stripeSubscriptionID = nil
        }
        persist()
    }

    func setNotifyWhenPlusLaunches(_ value: Bool) {
        membership.notifyWhenPlusLaunches = value
        persist()
    }

    // MARK: - Pre-order

    /// Clears local "completed" preorders that never received a real Stripe PaymentIntent.
    /// Keeps Review/DEBUG sandbox founding completions while mock checkout is allowed.
    func clearUnverifiedLocalPreorderIfNeeded() {
        guard preorder.status == .completed || preorder.paymentIntentID != nil else { return }
        if Self.hasCompletedFoundingAccess(preorder) { return }
        preorder = PreorderState()
        persist()
    }

    /// Real Stripe PaymentIntent ids look like `pi_3N…`. Local mocks use `pi_local_…` / `pi_credit_…`.
    static func isVerifiedStripePaymentIntentID(_ id: String?) -> Bool {
        guard let id else { return false }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("pi_") else { return false }
        if trimmed.hasPrefix("pi_local") || trimmed.hasPrefix("pi_credit") || trimmed.hasPrefix("pi_review") {
            return false
        }
        return trimmed.count >= 16
    }

    /// True when Founding Access is paid via a verified Stripe PaymentIntent.
    /// DEBUG mock completions may count for local testing — never for App Review.
    static func hasCompletedFoundingAccess(_ state: PreorderState) -> Bool {
        guard state.isCompleted else { return false }
        if isVerifiedStripePaymentIntentID(state.paymentIntentID) { return true }
        guard PaymentService.allowsLocalMockPayments else { return false }
        guard !AppleReviewDemoAccount.isSessionActive else { return false }
        guard let id = state.paymentIntentID?.trimmingCharacters(in: .whitespacesAndNewlines),
              id.hasPrefix("pi_") else { return false }
        return true
    }

    var hasCompletedFoundingAccess: Bool {
        Self.hasCompletedFoundingAccess(preorder)
    }

    func refreshPreorderQuote(auth: AuthService) async {
        clearUnverifiedLocalPreorderIfNeeded()
        do {
            preorderQuote = try await PreOrderService.fetchQuote(auth: auth, localState: preorder)
            errorMessage = nil
            if let quote = preorderQuote {
                preorder.accountCredit = quote.accountCredit
                preorder.creditConsumed = quote.creditConsumed
                if quote.existingStatus == .completed {
                    preorder.status = .completed
                    if let tier = quote.tier {
                        preorder.lockedTier = tier
                    } else if preorder.lockedTier == nil {
                        preorder.lockedTier = PreOrderService.inferredLockedTier(paidAmount: preorder.paidAmount)
                    }
                    // Founding is a locked rate — clear leftover one-time credit semantics.
                    preorder.accountCredit = 0
                    preorder.creditConsumed = true
                } else if PreOrderService.isLivePreorderAvailable,
                          preorder.status == .completed,
                          quote.existingStatus != .completed,
                          !Self.isVerifiedStripePaymentIntentID(preorder.paymentIntentID) {
                    preorder = PreorderState()
                }
                persist()
            }
        } catch {
            errorMessage = error.localizedDescription
            // Keep Accept & pay visible with a local preview when the network drops.
            if preorderQuote == nil
                || preorderQuote?.tier == nil
                || preorderQuote?.existingStatus == .completed {
                preorderQuote = PreOrderService.localPreviewQuote(state: PreorderState())
            }
        }
    }

    func purchasePreorder(auth: AuthService, agreementAccepted: Bool) async throws -> PreorderPaymentResult {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        clearUnverifiedLocalPreorderIfNeeded()

        guard agreementAccepted else {
            throw PreOrderServiceError.backend(
                "You must accept the Founding Access agreement before paying."
            )
        }

        // Preferred path: Supabase JWT + create-preorder-payment + Stripe PaymentSheet.
        if PreOrderService.isLivePreorderAvailable, auth.hasSupabaseSession {
            do {
                let purchase = try await PreOrderService.purchase(
                    auth: auth,
                    localState: preorder,
                    agreementAccepted: agreementAccepted
                )
                guard Self.isVerifiedStripePaymentIntentID(purchase.result.paymentIntentID) else {
                    throw PreOrderServiceError.unverifiedPayment
                }
                preorder = purchase.updatedState
                preorderQuote = try await PreOrderService.fetchQuote(auth: auth, localState: preorder)
                persist()
                return purchase.result
            } catch {
                // App Review must still reach Stripe PaymentSheet even if inventory RPC fails.
                if AppleReviewDemoAccount.isSessionActive, PaymentService.isStripeConfigured {
                    return try await purchaseFoundingViaCheckout(auth: auth)
                }
                throw error
            }
        }

        // App Review / customers without a Supabase JWT yet: still require live Stripe PaymentSheet.
        // Never silently grant Founding Access.
        if AppleReviewDemoAccount.isSessionActive {
            guard PaymentService.isStripeConfigured else {
                throw PreOrderServiceError.notConfigured
            }
            return try await purchaseFoundingViaCheckout(auth: auth)
        }

        guard PaymentService.allowsLocalMockPayments || PaymentService.isStripeConfigured else {
            if PreOrderService.isLivePreorderAvailable {
                throw PreOrderServiceError.requiresSupabaseAuth
            }
            throw PreOrderServiceError.notConfigured
        }

        return try await purchaseFoundingViaCheckout(auth: auth)
    }

    /// Charges Founding Access through PaymentSheet (when Stripe is live) or the Review sandbox card.
    private func purchaseFoundingViaCheckout(auth: AuthService) async throws -> PreorderPaymentResult {
        let quote = preorderQuote ?? PreOrderService.localPreviewQuote(state: preorder)
        guard quote.promoApplied, let tier = quote.tier else {
            throw PreOrderServiceError.slotsFilled
        }
        if quote.existingStatus == .completed || Self.hasCompletedFoundingAccess(preorder) {
            throw PreOrderServiceError.alreadyPreordered
        }

        let method = paymentMethods.first(where: \.isDefault) ?? paymentMethods.first
        let charged = try await PaymentService.charge(
            amount: tier.price,
            method: method,
            flow: "founding_access"
        )

        var updated = preorder
        updated.status = .completed
        updated.paidAmount = charged.amount
        updated.promoApplied = true
        updated.paymentIntentID = charged.paymentIntentID
        updated.completedAt = Date()
        updated.accountCredit = 0
        updated.creditConsumed = true
        updated.lockedTier = tier
        updated.localSlotsClaimed = max(updated.localSlotsClaimed, 1)
        preorder = updated
        preorderQuote = PreOrderService.localPreviewQuote(state: updated)
        // Refresh live quote when possible so inventory stays honest after a real Stripe charge.
        if auth.hasSupabaseSession, PreOrderService.isLivePreorderAvailable {
            if let live = try? await PreOrderService.fetchQuote(auth: auth, localState: preorder) {
                preorderQuote = live
                if let locked = live.tier {
                    preorder.lockedTier = locked
                }
            }
        }
        persist()

        return PreorderPaymentResult(
            paymentIntentID: charged.paymentIntentID,
            amount: charged.amount,
            promoApplied: true,
            creditGranted: 0
        )
    }

    func quoteDueToday(for vehicle: Vehicle, targetChargePercent: Int) -> (
        quote: ChargeQuote,
        creditApplied: Decimal,
        amountDue: Decimal,
        foundingTier: PreorderTier?
    ) {
        let quote = quote(for: vehicle, targetChargePercent: targetChargePercent)
        let foundingTier = PreOrderService.activeLockedTier(for: preorder)
        let due = PreOrderService.amountDue(for: quote.price, state: preorder)
        let savings = PreOrderService.foundingSavings(for: quote.price, state: preorder)
        return (quote, savings, due, foundingTier)
    }

    var defaultPaymentMethod: SavedPaymentMethod? {
        paymentMethods.first(where: \.isDefault) ?? paymentMethods.first
    }

    func addPaymentMethod(_ method: SavedPaymentMethod) {
        if method.isDefault {
            for index in paymentMethods.indices {
                paymentMethods[index].isDefault = false
            }
        }
        paymentMethods.append(method)
        persist()
    }

    func setDefaultPaymentMethod(id: UUID) {
        for index in paymentMethods.indices {
            paymentMethods[index].isDefault = paymentMethods[index].id == id
        }
        persist()
    }

    func removePaymentMethod(id: UUID) {
        paymentMethods.removeAll { $0.id == id }
        if !paymentMethods.isEmpty, !paymentMethods.contains(where: \.isDefault) {
            paymentMethods[0].isDefault = true
        }
        persist()
    }

    /// Replaces Stripe-linked cards while preserving DEBUG local mock methods and default selection.
    func replaceStripePaymentMethods(with remote: [SavedPaymentMethod]) {
        let previousDefaultStripeID = paymentMethods
            .first(where: \.isDefault)?
            .stripePaymentMethodID
        let localMocks = paymentMethods.filter(\.isLocalMock)

        var merged = localMocks
        for method in remote where !method.isLocalMock {
            var copy = method
            if let previousDefaultStripeID,
               copy.stripePaymentMethodID == previousDefaultStripeID {
                copy.isDefault = true
            } else {
                copy.isDefault = false
            }
            // Preserve stable local UUID when the same Stripe PM already exists.
            if let existing = paymentMethods.first(where: {
                $0.stripePaymentMethodID == copy.stripePaymentMethodID
            }) {
                copy = SavedPaymentMethod(
                    id: existing.id,
                    brand: copy.brand,
                    last4: copy.last4,
                    expiryMonth: copy.expiryMonth,
                    expiryYear: copy.expiryYear,
                    isDefault: copy.isDefault,
                    stripePaymentMethodID: copy.stripePaymentMethodID,
                    createdAt: existing.createdAt
                )
            }
            merged.append(copy)
        }

        if !merged.isEmpty, !merged.contains(where: \.isDefault) {
            if let firstStripe = merged.firstIndex(where: { !$0.isLocalMock }) {
                merged[firstStripe].isDefault = true
            } else {
                merged[0].isDefault = true
            }
        }

        paymentMethods = merged
        persist()
    }

    func submitSupportTicket(subject: String, body: String) {
        let ticket = SupportTicket(
            id: UUID(),
            subject: subject,
            body: body,
            createdAt: Date(),
            status: "Open"
        )
        supportTickets.insert(ticket, at: 0)
        persist()
    }

    // MARK: - Derived

    var pickupLocations: [LocationPin] { savedAddresses }

    var canAddVehicle: Bool {
        vehicles.count < Pricing.maxSavedVehicles
    }

    var primaryVehicle: Vehicle? {
        vehicles.first(where: \.isTesla) ?? vehicles.first
    }

    var primaryVehicleLocationName: String {
        savedAddresses.first?.name ?? "Home"
    }

    var nextAvailableDriver: NearbyDriver? {
        nearbyDrivers
            .filter { $0.status == .available }
            .min { $0.etaMinutes < $1.etaMinutes }
            ?? nearbyDrivers.min { $0.etaMinutes < $1.etaMinutes }
    }

    func quote(for vehicle: Vehicle, targetChargePercent: Int) -> ChargeQuote {
        Pricing.quote(
            from: vehicle.currentChargePercent,
            to: targetChargePercent,
            membership: membership
        )
    }

    func refresh() async {
        // Keep on-device garage and addresses as the user left them — never reseed sample data.
        persist()
    }

    // MARK: - Vehicles / addresses

    @discardableResult
    func addVehicle(
        make: String,
        model: String,
        year: Int,
        insurancePolicy: String,
        insuranceCompanyName: String,
        registrationExpirationDate: Date,
        insurancePolicyExpirationDate: Date,
        registrationPhotoData: Data,
        insuranceCardPhotoData: Data? = nil,
        paintColor: TeslaPaint = .pearlWhite,
        smokingInVehicle: Bool = false,
        licensePlate: String,
        licensePlateState: String,
        currentChargePercent: Int = 40
    ) throws -> Vehicle {
        guard canAddVehicle else {
            throw StoreError.vehicleLimitReached
        }

        let trimmedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPolicy = insurancePolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCarrier = insuranceCompanyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlate = licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedState = licensePlateState.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !trimmedMake.isEmpty,
              !trimmedModel.isEmpty,
              (1990...2030).contains(year),
              !trimmedPlate.isEmpty,
              USLicensePlateState(rawValue: trimmedState) != nil,
              !trimmedPolicy.isEmpty,
              !trimmedCarrier.isEmpty,
              !registrationPhotoData.isEmpty else {
            throw StoreError.vehicleIncomplete
        }

        let submittedAt = Date()
        let vehicle = Vehicle(
            id: UUID(),
            name: "\(trimmedMake) \(trimmedModel)",
            make: trimmedMake,
            model: trimmedModel,
            year: year,
            licensePlate: trimmedPlate,
            licensePlateState: trimmedState,
            registrationExpirationDate: registrationExpirationDate,
            insurancePolicy: trimmedPolicy,
            insuranceCompanyName: trimmedCarrier,
            insurancePolicyExpirationDate: insurancePolicyExpirationDate,
            currentChargePercent: currentChargePercent,
            estimatedRangeMiles: Pricing.estimatedMiles(fromChargePercent: currentChargePercent),
            registrationPhotoData: registrationPhotoData,
            insuranceCardPhotoData: insuranceCardPhotoData,
            teslaVIN: nil,
            isTeslaLinked: false,
            paintColor: paintColor,
            smokingInVehicle: smokingInVehicle,
            documentApprovalStatus: .pendingReview,
            documentsSubmittedAt: submittedAt,
            documentsReviewedAt: nil,
            documentRejectionReason: nil
        )
        vehicles.append(vehicle)
        enqueueDocumentReviewIfNeeded(for: vehicle)
        persist()
        return vehicle
    }

    @discardableResult
    func updateVehicle(
        id: UUID,
        make: String,
        model: String,
        year: Int,
        insurancePolicy: String,
        insuranceCompanyName: String,
        registrationExpirationDate: Date,
        insurancePolicyExpirationDate: Date,
        registrationPhotoData: Data,
        insuranceCardPhotoData: Data? = nil,
        paintColor: TeslaPaint,
        smokingInVehicle: Bool,
        licensePlate: String? = nil,
        licensePlateState: String? = nil
    ) throws -> Vehicle {
        guard let index = vehicles.firstIndex(where: { $0.id == id }) else {
            throw StoreError.vehicleNotFound
        }

        let existing = vehicles[index]
        let trimmedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPolicy = insurancePolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCarrier = insuranceCompanyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let plate = (licensePlate ?? existing.licensePlate)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let state = (licensePlateState ?? existing.licensePlateState)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !trimmedMake.isEmpty,
              !trimmedModel.isEmpty,
              (1990...2030).contains(year),
              !plate.isEmpty,
              USLicensePlateState(rawValue: state) != nil,
              !trimmedPolicy.isEmpty,
              !trimmedCarrier.isEmpty,
              !registrationPhotoData.isEmpty else {
            throw StoreError.vehicleIncomplete
        }

        let sensitiveDocsChanged =
            registrationPhotoData != existing.registrationPhotoData
            || trimmedPolicy != existing.insurancePolicy
            || trimmedCarrier != existing.insuranceCompanyName
            || registrationExpirationDate != existing.registrationExpirationDate
            || insurancePolicyExpirationDate != existing.insurancePolicyExpirationDate
            || insuranceCardPhotoData != existing.insuranceCardPhotoData

        let approvalStatus: VehicleDocumentApprovalStatus
        let submittedAt: Date?
        let reviewedAt: Date?
        let rejectionReason: String?
        if sensitiveDocsChanged || existing.documentApprovalStatus != .approved {
            approvalStatus = .pendingReview
            submittedAt = Date()
            reviewedAt = nil
            rejectionReason = nil
        } else {
            approvalStatus = existing.documentApprovalStatus
            submittedAt = existing.documentsSubmittedAt
            reviewedAt = existing.documentsReviewedAt
            rejectionReason = existing.documentRejectionReason
        }

        let updated = Vehicle(
            id: existing.id,
            name: existing.isTeslaLinked ? existing.name : "\(trimmedMake) \(trimmedModel)",
            make: trimmedMake,
            model: trimmedModel,
            year: year,
            licensePlate: plate,
            licensePlateState: state,
            registrationExpirationDate: registrationExpirationDate,
            insurancePolicy: trimmedPolicy,
            insuranceCompanyName: trimmedCarrier,
            insurancePolicyExpirationDate: insurancePolicyExpirationDate,
            currentChargePercent: existing.currentChargePercent,
            estimatedRangeMiles: existing.estimatedRangeMiles,
            registrationPhotoData: registrationPhotoData,
            insuranceCardPhotoData: insuranceCardPhotoData,
            teslaVIN: existing.teslaVIN,
            isTeslaLinked: existing.isTeslaLinked,
            paintColor: paintColor,
            smokingInVehicle: smokingInVehicle,
            documentApprovalStatus: approvalStatus,
            documentsSubmittedAt: submittedAt,
            documentsReviewedAt: reviewedAt,
            documentRejectionReason: rejectionReason
        )
        vehicles[index] = updated
        if approvalStatus == .pendingReview {
            enqueueDocumentReviewIfNeeded(for: updated)
        }
        errorMessage = nil
        persist()
        return updated
    }

    /// Apply an admin inbox decision to the matching garage vehicle (if present).
    @discardableResult
    func applyDocumentReviewDecision(
        vehicleId: UUID,
        status: VehicleDocumentApprovalStatus,
        rejectionReason: String?
    ) -> Vehicle? {
        guard let index = vehicles.firstIndex(where: { $0.id == vehicleId }) else {
            return nil
        }
        let existing = vehicles[index]
        let updated = existing.withDocumentApproval(
            status: status,
            submittedAt: existing.documentsSubmittedAt,
            reviewedAt: Date(),
            rejectionReason: rejectionReason
        )
        vehicles[index] = updated
        errorMessage = nil
        persist()
        return updated
    }

    @discardableResult
    func approveVehicleDocuments(id: UUID) throws -> Vehicle {
        guard let inbox = documentInbox,
              let item = inbox.pendingItems.first(where: { $0.vehicleId == id })
                ?? inbox.items.first(where: { $0.vehicleId == id && $0.status == .pending }) else {
            // Fallback: approve directly on garage vehicle.
            guard let index = vehicles.firstIndex(where: { $0.id == id }) else {
                throw StoreError.vehicleNotFound
            }
            let existing = vehicles[index]
            guard existing.documentApprovalStatus == .pendingReview
                    || existing.documentApprovalStatus == .rejected else {
                throw StoreError.documentReviewUnavailable
            }
            let updated = existing.withDocumentApproval(
                status: .approved,
                submittedAt: existing.documentsSubmittedAt,
                reviewedAt: Date(),
                rejectionReason: nil
            )
            vehicles[index] = updated
            persist()
            return updated
        }
        let reviewed = try inbox.approve(itemID: item.id)
        if let updated = applyDocumentReviewDecision(
            vehicleId: reviewed.vehicleId,
            status: .approved,
            rejectionReason: nil
        ) {
            return updated
        }
        return Vehicle(
            id: reviewed.vehicleId,
            name: reviewed.vehicleDisplayName,
            make: reviewed.make,
            model: reviewed.model,
            year: reviewed.year,
            licensePlate: reviewed.licensePlateDisplay,
            registrationExpirationDate: reviewed.registrationExpirationDate,
            insurancePolicy: reviewed.insurancePolicy,
            insuranceCompanyName: reviewed.insuranceCompanyName,
            insurancePolicyExpirationDate: reviewed.insurancePolicyExpirationDate,
            currentChargePercent: 0,
            estimatedRangeMiles: 0,
            registrationPhotoData: reviewed.registrationPhotoData,
            insuranceCardPhotoData: reviewed.insuranceCardPhotoData,
            teslaVIN: nil,
            isTeslaLinked: false,
            documentApprovalStatus: .approved,
            documentsSubmittedAt: reviewed.submittedAt,
            documentsReviewedAt: reviewed.reviewedAt,
            documentRejectionReason: nil
        )
    }

    @discardableResult
    func rejectVehicleDocuments(id: UUID, reason: String) throws -> Vehicle {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.documentRejectionIncomplete
        }
        guard let inbox = documentInbox,
              let item = inbox.pendingItems.first(where: { $0.vehicleId == id })
                ?? inbox.items.first(where: { $0.vehicleId == id && $0.status == .pending }) else {
            guard let index = vehicles.firstIndex(where: { $0.id == id }) else {
                throw StoreError.vehicleNotFound
            }
            let existing = vehicles[index]
            guard existing.documentApprovalStatus == .pendingReview
                    || existing.documentApprovalStatus == .approved else {
                throw StoreError.documentReviewUnavailable
            }
            let updated = existing.withDocumentApproval(
                status: .rejected,
                submittedAt: existing.documentsSubmittedAt,
                reviewedAt: Date(),
                rejectionReason: trimmed
            )
            vehicles[index] = updated
            persist()
            return updated
        }
        let reviewed = try inbox.reject(itemID: item.id, reason: trimmed)
        if let updated = applyDocumentReviewDecision(
            vehicleId: reviewed.vehicleId,
            status: .rejected,
            rejectionReason: trimmed
        ) {
            return updated
        }
        // Inbox updated; garage vehicle may belong to another signed-in session.
        return Vehicle(
            id: reviewed.vehicleId,
            name: reviewed.vehicleDisplayName,
            make: reviewed.make,
            model: reviewed.model,
            year: reviewed.year,
            licensePlate: reviewed.licensePlateDisplay,
            registrationExpirationDate: reviewed.registrationExpirationDate,
            insurancePolicy: reviewed.insurancePolicy,
            insuranceCompanyName: reviewed.insuranceCompanyName,
            insurancePolicyExpirationDate: reviewed.insurancePolicyExpirationDate,
            currentChargePercent: 0,
            estimatedRangeMiles: 0,
            registrationPhotoData: reviewed.registrationPhotoData,
            insuranceCardPhotoData: reviewed.insuranceCardPhotoData,
            teslaVIN: nil,
            isTeslaLinked: false,
            documentApprovalStatus: .rejected,
            documentsSubmittedAt: reviewed.submittedAt,
            documentsReviewedAt: reviewed.reviewedAt,
            documentRejectionReason: trimmed
        )
    }

    /// Approve from admin inbox item id (preferred path for Admin Home).
    func approveDocumentReviewItem(itemID: UUID) throws {
        guard let inbox = documentInbox else {
            throw StoreError.documentReviewUnavailable
        }
        let reviewed = try inbox.approve(itemID: itemID)
        _ = applyDocumentReviewDecision(
            vehicleId: reviewed.vehicleId,
            status: .approved,
            rejectionReason: nil
        )
    }

    /// Reject from admin inbox item id (preferred path for Admin Home).
    func rejectDocumentReviewItem(itemID: UUID, reason: String) throws {
        guard let inbox = documentInbox else {
            throw StoreError.documentReviewUnavailable
        }
        let reviewed = try inbox.reject(itemID: itemID, reason: reason)
        _ = applyDocumentReviewDecision(
            vehicleId: reviewed.vehicleId,
            status: .rejected,
            rejectionReason: reviewed.rejectionReason
        )
    }

    @discardableResult
    func removeVehicle(id: UUID) -> Bool {
        if let active = activeJob, active.vehicle.id == id {
            errorMessage = "This vehicle is on an active booking and can’t be removed yet."
            return false
        }
        if upcomingJobs.contains(where: { $0.vehicle.id == id }) {
            errorMessage = "This vehicle has an upcoming booking. Cancel it before removing the vehicle."
            return false
        }
        vehicles.removeAll { $0.id == id }
        errorMessage = nil
        persist()
        return true
    }

    @discardableResult
    func addAddress(
        name: String,
        address: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        gateCode: String? = nil,
        apartmentUnit: String? = nil,
        parkingSpot: String? = nil,
        pickupInstructions: String? = nil,
        vehicleNotes: String? = nil,
        isDefault: Bool = false
    ) throws -> LocationPin {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAddress.isEmpty else {
            throw StoreError.addressIncomplete
        }

        let makeDefault = isDefault || savedAddresses.isEmpty
        var pin = LocationPin(
            id: UUID(),
            name: trimmedName,
            address: trimmedAddress,
            latitude: latitude ?? 37.7749,
            longitude: longitude ?? -122.4194,
            gateCode: gateCode,
            apartmentUnit: apartmentUnit,
            parkingSpot: parkingSpot,
            pickupInstructions: pickupInstructions,
            vehicleNotes: vehicleNotes,
            isDefault: makeDefault
        )
        if makeDefault {
            savedAddresses = savedAddresses.map {
                var copy = $0
                copy.isDefault = false
                return copy
            }
            savedAddresses.insert(pin, at: 0)
        } else {
            savedAddresses.append(pin)
        }
        persist()
        return pin
    }

    @discardableResult
    func updateAddress(
        id: UUID,
        name: String,
        address: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        gateCode: String? = nil,
        apartmentUnit: String? = nil,
        parkingSpot: String? = nil,
        pickupInstructions: String? = nil,
        vehicleNotes: String? = nil,
        isDefault: Bool? = nil
    ) throws -> LocationPin {
        guard let index = savedAddresses.firstIndex(where: { $0.id == id }) else {
            throw StoreError.addressNotFound
        }

        let existing = savedAddresses[index]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAddress.isEmpty else {
            throw StoreError.addressIncomplete
        }

        let makeDefault = isDefault ?? existing.isDefault
        var updated = LocationPin(
            id: existing.id,
            name: trimmedName,
            address: trimmedAddress,
            latitude: latitude ?? existing.latitude,
            longitude: longitude ?? existing.longitude,
            gateCode: gateCode,
            apartmentUnit: apartmentUnit,
            parkingSpot: parkingSpot,
            pickupInstructions: pickupInstructions,
            vehicleNotes: vehicleNotes,
            isDefault: makeDefault
        )

        savedAddresses.remove(at: index)
        if makeDefault {
            savedAddresses = savedAddresses.map {
                var copy = $0
                copy.isDefault = false
                return copy
            }
            savedAddresses.insert(updated, at: 0)
        } else {
            let insertAt = min(index, savedAddresses.count)
            savedAddresses.insert(updated, at: insertAt)
            if !savedAddresses.contains(where: \.isDefault), !savedAddresses.isEmpty {
                savedAddresses[0].isDefault = true
            }
        }
        errorMessage = nil
        persist()
        return updated
    }

    @discardableResult
    func removeAddress(id: UUID) -> Bool {
        if let active = activeJob, active.pickup.id == id {
            errorMessage = "This address is used by an active booking and can’t be removed yet."
            return false
        }
        if upcomingJobs.contains(where: { $0.pickup.id == id }) {
            errorMessage = "This address has an upcoming booking. Cancel it before removing the address."
            return false
        }
        savedAddresses.removeAll { $0.id == id }
        errorMessage = nil
        persist()
        return true
    }

    func importTeslaVehicles(_ linked: [Vehicle]) {
        vehicles.removeAll { $0.isTeslaLinked }
        let remaining = max(0, Pricing.maxSavedVehicles - vehicles.count)
        for vehicle in linked.prefix(remaining) where !vehicles.contains(where: { $0.id == vehicle.id }) {
            vehicles.append(vehicle)
        }
        persist()
    }

    func removeTeslaLinkedVehicles() {
        vehicles.removeAll { $0.isTeslaLinked }
        persist()
    }

    func canBook(_ vehicle: Vehicle) -> Bool {
        vehicle.meetsMinimumRange && vehicle.isDocumentsApprovedForBooking
    }

    func bookingBlockReason(for vehicle: Vehicle) -> String? {
        if !vehicle.isDocumentsApprovedForBooking {
            switch vehicle.documentApprovalStatus {
            case .pendingReview:
                return "Registration photo and insurance policy are awaiting admin approval."
            case .rejected:
                return vehicle.documentRejectionReason
                    ?? "Documents were rejected. Update registration or policy details and resubmit."
            case .incomplete:
                return "Add a registration photo and insurance policy, then wait for admin approval."
            case .approved:
                break
            }
        }
        if !vehicle.meetsMinimumRange {
            return "Needs at least \(Pricing.minimumRangeMiles) miles of range for pickup."
        }
        return nil
    }

    // MARK: - Booking

    @discardableResult
    func createJob(
        vehicle: Vehicle,
        pickup: LocationPin,
        dropoff: LocationPin? = nil,
        targetChargePercent: Int,
        paymentMethod: SavedPaymentMethod? = nil,
        scheduledFor: Date? = nil,
        customerEmail: String? = nil,
        customerName: String? = nil
    ) async throws -> ChargeJob {
        guard CherchargeServiceAvailability.isLiveConciergeAvailable else {
            throw StoreError.serviceUnavailable
        }
        guard vehicle.isDocumentsApprovedForBooking else {
            throw StoreError.documentsPendingApproval
        }
        guard vehicle.meetsMinimumRange else {
            throw StoreError.insufficientRange
        }

        let email = (customerEmail ?? profileEmail)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let name = {
            let trimmed = (customerName ?? profileName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? email.split(separator: "@").first.map(String.init) ?? "Customer" : trimmed
        }()

        // App Review uses the same driver-dispatch path as any signed-in customer.
        if CustomerBookingDispatchService.shared.isAvailable {
            guard email.contains("@"), !email.hasSuffix("@chercharge.local") else {
                throw StoreError.driverDispatchNeedsAccount
            }
        }

        let quote = self.quote(for: vehicle, targetChargePercent: targetChargePercent)
        let amountDue = PreOrderService.amountDue(for: quote.price, state: preorder)
        let bookingPrice = amountDue
        let method = paymentMethod ?? defaultPaymentMethod
        if amountDue > 0,
           !PaymentService.isStripeConfigured,
           PaymentService.allowsLocalMockPayments,
           method == nil {
            throw StoreError.noPaymentMethod
        }

        progressionTask?.cancel()
        cloudBookingSyncTask?.cancel()
        errorMessage = nil
        bookingDispatchError = nil
        lastCompletedJob = nil
        isLoading = true
        defer { isLoading = false }

        // Charge first, then dispatch so drivers only see paid (or $0 founding) requests.
        let charge: PaymentChargeResult
        if amountDue > 0 {
            charge = try await PaymentService.charge(
                amount: amountDue,
                method: method
            )
        } else {
            charge = PaymentChargeResult(
                paymentIntentID: "pi_credit_\(UUID().uuidString.prefix(12))",
                amount: 0,
                methodLabel: "Founding rate",
                receiptNumber: makeLocalReceiptNumber()
            )
        }

        var jobID = UUID()
        var isCloudDispatched = false

        if CustomerBookingDispatchService.shared.isAvailable {
            do {
                let remote = try await CustomerBookingDispatchService.shared.createBooking(
                    customerEmail: email,
                    customerName: name,
                    vehicle: vehicle,
                    pickup: pickup,
                    station: station,
                    targetChargePercent: targetChargePercent,
                    estimatedPrice: bookingPrice,
                    estimatedMinutes: quote.estimatedMinutes,
                    paymentIntentID: charge.paymentIntentID
                )
                jobID = remote.id
                isCloudDispatched = true
                if profileEmail.isEmpty { profileEmail = email }
                if profileName.isEmpty { profileName = name }
            } catch {
                throw StoreError.driverDispatchFailed(error.localizedDescription)
            }
        } else if !PaymentService.allowsLocalMockPayments {
            // Production / Stripe builds must reach the driver pool.
            throw StoreError.driverDispatchFailed(
                "Driver dispatch isn’t available. Check Supabase configuration and try again."
            )
        }

        var job = makeJob(
            id: jobID,
            vehicle: vehicle,
            pickup: pickup,
            targetChargePercent: targetChargePercent,
            startingChargePercent: vehicle.currentChargePercent,
            status: .requested,
            estimatedPrice: bookingPrice,
            estimatedMinutes: quote.estimatedMinutes,
            createdAt: Date(),
            dropoff: dropoff ?? pickup,
            scheduledFor: scheduledFor,
            isCloudDispatched: isCloudDispatched
        )
        job.paymentIntentID = charge.paymentIntentID
        if let foundingTier = PreOrderService.activeLockedTier(for: preorder) {
            job.paymentMethodLabel = "\(charge.methodLabel) · \(foundingTier.shortRateLabel)"
        } else {
            job.paymentMethodLabel = charge.methodLabel
        }
        job.receiptNumber = charge.receiptNumber

        activeJob = job
        persist()

        if isCloudDispatched {
            // Wait for a driver to claim / advance — do not simulate locally.
            startCloudBookingSync()
        } else {
            startProgression()
        }

        // Prefer service notifications for the trip — never imply marketing is required.
        settings.inspectionAlertsEnabled = true
        persist()
        Task {
            if await InspectionNotificationService.isAuthorizedForAlerts() {
                settings.pushNotificationsEnabled = true
                persist()
                InspectionNotificationService.notifyBookingConfirmed(
                    jobID: job.id,
                    scheduledFor: nil
                )
            } else if await InspectionNotificationService.authorizationStatus() == .notDetermined {
                shouldOfferNotificationPrePrompt = true
            }
        }

        return job
    }

    func clearCompletedJob() {
        lastCompletedJob = nil
        persist()
    }

    func cancelActiveJob() {
        progressionTask?.cancel()
        progressionTask = nil
        cloudBookingSyncTask?.cancel()
        cloudBookingSyncTask = nil
        approvalTimerTask?.cancel()
        approvalTimerTask = nil
        activeJob = nil
        errorMessage = nil
        bookingDispatchError = nil
        persist()
    }

    func cancelUpcomingJob(id: UUID) {
        upcomingJobs.removeAll { $0.id == id }
        persist()
    }

    func rescheduleUpcomingJob(id: UUID) {
        guard let index = upcomingJobs.firstIndex(where: { $0.id == id }) else { return }
        let job = upcomingJobs[index]
        let newDate = Date().addingTimeInterval(60 * 60 * 24)
        upcomingJobs[index] = makeJob(
            id: job.id,
            vehicle: job.vehicle,
            pickup: job.pickup,
            targetChargePercent: job.targetChargePercent,
            startingChargePercent: job.startingChargePercent,
            status: job.status,
            estimatedPrice: job.estimatedPrice,
            estimatedMinutes: job.estimatedMinutes,
            createdAt: newDate,
            preTripInspection: job.preTripInspection,
            postTripInspection: job.postTripInspection,
            customerApprovedPickupAt: job.customerApprovedPickupAt,
            issueReports: job.issueReports,
            paymentIntentID: job.paymentIntentID,
            paymentMethodLabel: job.paymentMethodLabel,
            receiptNumber: job.receiptNumber,
            scheduledFor: newDate
        )
        persist()
    }

    func startUpcomingNow(id: UUID) {
        guard CherchargeServiceAvailability.isLiveConciergeAvailable else { return }
        guard activeJob == nil,
              let index = upcomingJobs.firstIndex(where: { $0.id == id }) else { return }
        let upcoming = upcomingJobs.remove(at: index)
        activeJob = makeJob(
            id: upcoming.id,
            vehicle: upcoming.vehicle,
            pickup: upcoming.pickup,
            targetChargePercent: upcoming.targetChargePercent,
            startingChargePercent: upcoming.startingChargePercent,
            status: .requested,
            estimatedPrice: upcoming.estimatedPrice,
            estimatedMinutes: upcoming.estimatedMinutes,
            createdAt: Date(),
            paymentIntentID: upcoming.paymentIntentID,
            paymentMethodLabel: upcoming.paymentMethodLabel,
            receiptNumber: upcoming.receiptNumber
        )
        persist()
        startProgression()
    }

    func submitInspection(_ inspection: VehicleInspection) async throws {
        guard var job = activeJob, job.id == inspection.jobID else {
            throw StoreError.inspectionUnavailable
        }
        guard inspection.isComplete else {
            throw StoreError.inspectionIncomplete
        }

        var uploaded = inspection
        let urls = await InspectionStorageService.shared.uploadMedia(for: inspection)
        uploaded.storageURLs = urls
        uploaded.uploadedAt = Date()

        switch inspection.phase {
        case .preTrip:
            guard job.status == .driverArrived else {
                throw StoreError.inspectionUnavailable
            }
            job.preTripInspection = uploaded
            job.status = .awaitingCustomerApproval
            job.inspectionApprovalDeadline = Date().addingTimeInterval(ChargeJob.customerApprovalWindow)
            activeJob = job
            persist()
            startApprovalAutoApproveTimer()
            if settings.inspectionAlertsEnabled || settings.pushNotificationsEnabled {
                InspectionNotificationService.notifyInspectionReadyForReview(jobID: job.id, phase: .preTrip)
            }

        case .postTrip:
            guard job.status == .awaitingPostTripInspection else {
                throw StoreError.inspectionUnavailable
            }
            job.postTripInspection = uploaded
            job.status = .awaitingReturnApproval
            job.returnApprovalDeadline = Date().addingTimeInterval(ChargeJob.returnApprovalWindow)
            job.customerApprovedReturnAt = nil
            activeJob = job
            persist()
            startReturnApprovalAutoApproveTimer()
            if settings.inspectionAlertsEnabled || settings.pushNotificationsEnabled {
                InspectionNotificationService.notifyInspectionReadyForReview(jobID: job.id, phase: .postTrip)
            }
        }
    }

    func approvePickup(jobID: UUID) async throws {
        guard var job = activeJob, job.id == jobID else {
            throw StoreError.inspectionUnavailable
        }
        guard job.status == .awaitingCustomerApproval, job.preTripInspection != nil else {
            throw StoreError.approvalUnavailable
        }

        let isCloud = job.isCloudDispatched
        let email = profileEmail

        approvalTimerTask?.cancel()
        approvalTimerTask = nil
        job.customerApprovedPickupAt = Date()
        job.inspectionApprovalDeadline = nil
        job.status = .pickedUp
        activeJob = job
        persist()
        if settings.pushNotificationsEnabled {
            InspectionNotificationService.notifyPickupApproved(jobID: job.id)
        }

        if isCloud {
            do {
                try await CustomerBookingDispatchService.shared.approvePickup(
                    customerEmail: email,
                    bookingID: jobID
                )
            } catch {
                bookingDispatchError =
                    "Pickup approved locally, but driver sync failed: \(error.localizedDescription)"
            }
            startCloudBookingSync()
        } else {
            startProgression()
        }
    }

    /// Called when the local countdown reaches the server deadline.
    /// Cloud trips: only nudge the backend — status poll applies the result.
    func autoApprovePickupIfNeeded() {
        guard let job = activeJob, job.needsCustomerApproval else { return }
        if let deadline = job.inspectionApprovalDeadline, Date() < deadline {
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if job.isCloudDispatched {
                _ = await CustomerBookingDispatchService.shared.autoApproveDue(bookingID: job.id)
                if let remote = try? await CustomerBookingDispatchService.shared.fetchStatus(
                    customerEmail: self.profileEmail,
                    bookingID: job.id
                ) {
                    self.applyCloudBookingUpdate(remote, bookingID: job.id)
                }
                return
            }
            try? await self.approvePickup(jobID: job.id)
        }
    }

    func approveReturn(jobID: UUID) async throws {
        guard var job = activeJob, job.id == jobID else {
            throw StoreError.inspectionUnavailable
        }
        guard job.status == .awaitingReturnApproval, job.postTripInspection != nil else {
            throw StoreError.approvalUnavailable
        }

        let isCloud = job.isCloudDispatched
        let email = profileEmail

        approvalTimerTask?.cancel()
        approvalTimerTask = nil
        job.customerApprovedReturnAt = Date()
        job.returnApprovalDeadline = nil
        job.status = .delivered
        job.completedAt = Date()
        activeJob = nil
        lastCompletedJob = job
        pastJobs.insert(job, at: 0)
        progressionTask?.cancel()
        progressionTask = nil
        cloudBookingSyncTask?.cancel()
        cloudBookingSyncTask = nil
        persist()
        if settings.pushNotificationsEnabled {
            InspectionNotificationService.notifyReturnApproved(jobID: job.id)
            InspectionNotificationService.notifyJobStatusChanged(jobID: job.id, status: .delivered)
        }

        if isCloud {
            do {
                try await CustomerBookingDispatchService.shared.approveReturn(
                    customerEmail: email,
                    bookingID: jobID
                )
            } catch {
                bookingDispatchError =
                    "Return approved locally, but driver sync failed: \(error.localizedDescription)"
            }
        }
    }

    /// Called when the local countdown reaches the server return deadline.
    /// Cloud trips: only nudge the backend — status poll applies the result.
    func autoApproveReturnIfNeeded() {
        guard let job = activeJob, job.needsReturnApproval else { return }
        if let deadline = job.returnApprovalDeadline, Date() < deadline {
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if job.isCloudDispatched {
                _ = await CustomerBookingDispatchService.shared.autoApproveDue(bookingID: job.id)
                if let remote = try? await CustomerBookingDispatchService.shared.fetchStatus(
                    customerEmail: self.profileEmail,
                    bookingID: job.id
                ) {
                    self.applyCloudBookingUpdate(remote, bookingID: job.id)
                }
                return
            }
            try? await self.approveReturn(jobID: job.id)
        }
    }

    // MARK: - Trip feedback

    func submitTripFeedback(jobID: UUID, tipAmount: Decimal, rating: Int) throws {
        let clampedRating = min(5, max(1, rating))
        let tip = max(Decimal(0), tipAmount)

        func applyFeedback(to job: inout ChargeJob) {
            job.tipAmount = tip > 0 ? tip : nil
            job.driverRating = clampedRating
            job.feedbackSubmittedAt = Date()
        }

        if var job = lastCompletedJob, job.id == jobID {
            applyFeedback(to: &job)
            lastCompletedJob = job
            if let index = pastJobs.firstIndex(where: { $0.id == jobID }) {
                pastJobs[index] = job
            }
            persist()
            return
        }

        guard let index = pastJobs.firstIndex(where: { $0.id == jobID }) else {
            throw StoreError.jobUnavailable
        }
        var job = pastJobs[index]
        applyFeedback(to: &job)
        pastJobs[index] = job
        persist()
    }

    // MARK: - Driver console (scaffolding)

    func setDriverManualControl(_ enabled: Bool) {
        driverManualControl = enabled
        if enabled {
            progressionTask?.cancel()
            progressionTask = nil
        } else if let job = activeJob, job.isActive {
            startProgression()
        }
    }

    func performDriverAction(_ action: DriverAction) async throws {
        guard CherchargeServiceAvailability.isLiveConciergeAvailable else {
            throw StoreError.serviceUnavailable
        }
        guard var job = activeJob else {
            throw StoreError.jobUnavailable
        }

        switch action {
        case .acceptRequest:
            guard job.status == .requested else { throw StoreError.driverActionUnavailable }
            job.status = .driverEnRoute
            activeJob = job
            persist()
            notifyDriverStatus(job.id, .driverEnRoute)

        case .markEnRoute:
            guard job.status == .requested else { throw StoreError.driverActionUnavailable }
            job.status = .driverEnRoute
            activeJob = job
            persist()
            notifyDriverStatus(job.id, .driverEnRoute)

        case .markArrived:
            guard job.status == .driverEnRoute else { throw StoreError.driverActionUnavailable }
            job.status = .driverArrived
            activeJob = job
            persist()
            notifyDriverStatus(job.id, .driverArrived)

        case .submitPreTripInspection:
            guard job.status == .driverArrived, job.preTripInspection == nil else {
                throw StoreError.driverActionUnavailable
            }
            await completeDriverPreTripInspection()

        case .departForStation:
            throw StoreError.waitingOnCustomer

        case .startCharging:
            guard job.status == .pickedUp else { throw StoreError.driverActionUnavailable }
            job.status = .charging
            activeJob = job
            persist()
            notifyDriverStatus(job.id, .charging)

        case .beginReturn:
            guard job.status == .charging else { throw StoreError.driverActionUnavailable }
            job.status = .returning
            activeJob = job
            persist()
            notifyDriverStatus(job.id, .returning)

        case .submitPostTripInspection:
            guard job.status == .returning || job.status == .awaitingPostTripInspection,
                  job.postTripInspection == nil else {
                throw StoreError.driverActionUnavailable
            }
            if job.status == .returning {
                job.status = .awaitingPostTripInspection
                activeJob = job
                persist()
            }
            await completeDriverPostTripInspection()

        case .completeDelivery:
            throw StoreError.waitingOnCustomer
        }
    }

    private func notifyDriverStatus(_ jobID: UUID, _ status: JobStatus) {
        if settings.pushNotificationsEnabled {
            InspectionNotificationService.notifyJobStatusChanged(jobID: jobID, status: status)
        }
    }

    func reportInspectionIssue(
        jobID: UUID,
        category: String,
        details: String,
        highlightedDamage: [String]
    ) throws {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.issueReportIncomplete
        }

        let report = InspectionIssueReport(
            id: UUID(),
            jobID: jobID,
            category: category,
            details: trimmed,
            highlightedDamage: highlightedDamage,
            createdAt: Date()
        )

        if var job = activeJob, job.id == jobID {
            guard job.canCompareInspections else { throw StoreError.comparisonUnavailable }
            job.issueReports.insert(report, at: 0)
            activeJob = job
            persist()
            return
        }

        if var job = lastCompletedJob, job.id == jobID {
            guard job.canCompareInspections else { throw StoreError.comparisonUnavailable }
            job.issueReports.insert(report, at: 0)
            lastCompletedJob = job
            if let index = pastJobs.firstIndex(where: { $0.id == jobID }) {
                pastJobs[index] = job
            }
            persist()
            return
        }

        guard let index = pastJobs.firstIndex(where: { $0.id == jobID }) else {
            throw StoreError.comparisonUnavailable
        }
        var job = pastJobs[index]
        guard job.canCompareInspections else { throw StoreError.comparisonUnavailable }
        job.issueReports.insert(report, at: 0)
        pastJobs[index] = job
        persist()
    }

    // MARK: - Internals

    private func makeJob(
        id: UUID,
        vehicle: Vehicle,
        pickup: LocationPin,
        targetChargePercent: Int,
        startingChargePercent: Int,
        status: JobStatus,
        estimatedPrice: Decimal,
        estimatedMinutes: Int,
        createdAt: Date,
        dropoff: LocationPin? = nil,
        preTripInspection: VehicleInspection? = nil,
        postTripInspection: VehicleInspection? = nil,
        customerApprovedPickupAt: Date? = nil,
        customerApprovedReturnAt: Date? = nil,
        inspectionApprovalDeadline: Date? = nil,
        returnApprovalDeadline: Date? = nil,
        issueReports: [InspectionIssueReport] = [],
        paymentIntentID: String? = nil,
        paymentMethodLabel: String? = nil,
        receiptNumber: String? = nil,
        completedAt: Date? = nil,
        scheduledFor: Date? = nil,
        isCloudDispatched: Bool = false
    ) -> ChargeJob {
        ChargeJob(
            id: id,
            vehicle: vehicle,
            pickup: pickup,
            station: station,
            dropoff: dropoff ?? pickup,
            targetChargePercent: targetChargePercent,
            startingChargePercent: startingChargePercent,
            status: status,
            estimatedPrice: estimatedPrice,
            estimatedMinutes: estimatedMinutes,
            createdAt: createdAt,
            preTripInspection: preTripInspection,
            postTripInspection: postTripInspection,
            customerApprovedPickupAt: customerApprovedPickupAt,
            customerApprovedReturnAt: customerApprovedReturnAt,
            inspectionApprovalDeadline: inspectionApprovalDeadline,
            returnApprovalDeadline: returnApprovalDeadline,
            issueReports: issueReports,
            paymentIntentID: paymentIntentID,
            paymentMethodLabel: paymentMethodLabel,
            receiptNumber: receiptNumber,
            completedAt: completedAt,
            scheduledFor: scheduledFor,
            isCloudDispatched: isCloudDispatched
        )
    }

    private func startProgression() {
        guard CherchargeServiceAvailability.isLiveConciergeAvailable else { return }
        guard !driverManualControl else { return }
        guard activeJob?.isCloudDispatched != true else { return }
        progressionTask?.cancel()
        progressionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await self?.advanceStatus()
            }
        }
    }

    /// Poll Supabase for driver claim / trip status + inspection updates on cloud-dispatched jobs.
    private func startCloudBookingSync() {
        cloudBookingSyncTask?.cancel()
        guard let job = activeJob, job.isCloudDispatched, job.isActive else { return }
        let bookingID = job.id
        let email = profileEmail

        // Ensure we can surface local inspection alerts while the trip is live.
        if !settings.inspectionAlertsEnabled {
            settings.inspectionAlertsEnabled = true
            persist()
        }
        Task {
            _ = await InspectionNotificationService.enableForBookingFlow()
            await PushRegistrationService.shared.refreshRegistration(
                customerEmail: email,
                customerID: nil,
                optIn: true
            )
        }

        cloudBookingSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let syncEmail = self.profileEmail.isEmpty ? email : self.profileEmail
                if let remote = try? await CustomerBookingDispatchService.shared.fetchStatus(
                    customerEmail: syncEmail,
                    bookingID: bookingID
                ) {
                    self.applyCloudBookingUpdate(remote, bookingID: bookingID)
                } else {
                    // #region agent log
                    // Surface decode/network failures that previously left UI stuck on driverArrived.
                    do {
                        _ = try await CustomerBookingDispatchService.shared.fetchStatus(
                            customerEmail: syncEmail,
                            bookingID: bookingID
                        )
                    } catch {
                        Self.agentDebugLog(
                            hypothesisId: "DECODE",
                            location: "BookingStore.startCloudBookingSync",
                            message: "fetchStatus failed",
                            data: ["error": error.localizedDescription]
                        )
                        #if DEBUG
                        print("cloud booking sync fetchStatus failed: \(error.localizedDescription)")
                        #endif
                    }
                    // #endregion
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func applyCloudBookingUpdate(_ remote: CustomerBookingStatusDTO, bookingID: UUID) {
        guard var job = activeJob, job.id == bookingID else {
            cloudBookingSyncTask?.cancel()
            cloudBookingSyncTask = nil
            return
        }

        let previousStatus = job.status
        let hadPreTrip = job.preTripInspection != nil
        let hadPostTrip = job.postTripInspection != nil
        var changed = false

        if let payload = remote.preTripInspection {
            let inspection = VehicleInspection.fromCloudPayload(payload)
            let missingOrLocalOnly = job.preTripInspection.map { !$0.hasRemoteMedia } ?? true
            if missingOrLocalOnly {
                job.preTripInspection = inspection
                changed = true
            }
        }
        if let payload = remote.postTripInspection {
            let inspection = VehicleInspection.fromCloudPayload(payload)
            let missingOrLocalOnly = job.postTripInspection.map { !$0.hasRemoteMedia } ?? true
            if missingOrLocalOnly {
                job.postTripInspection = inspection
                changed = true
            }
        }

        if let approvedAt = remote.customerApprovedPickupAt, job.customerApprovedPickupAt == nil {
            job.customerApprovedPickupAt = approvedAt
            changed = true
        }
        if let approvedAt = remote.customerApprovedReturnAt, job.customerApprovedReturnAt == nil {
            job.customerApprovedReturnAt = approvedAt
            changed = true
        }

        // Prefer server-stored deadlines — never invent a new 15s window on each poll.
        if let serverDeadline = remote.customerApprovalDeadline,
           job.inspectionApprovalDeadline != serverDeadline {
            job.inspectionApprovalDeadline = serverDeadline
            changed = true
        }
        if let serverDeadline = remote.returnApprovalDeadline,
           job.returnApprovalDeadline != serverDeadline {
            job.returnApprovalDeadline = serverDeadline
            changed = true
        }

        if let nextStatus = remote.jobStatus, job.status != nextStatus {
            job.status = nextStatus
            changed = true
        }

        // Explicit notification poll check (same pattern as getNotifications → inspection_ready).
        if let inspection = remote.notifications.first(where: {
            $0.type == "inspection_ready"
                && $0.bookingId == bookingID
                && $0.readAt == nil
        }) ?? remote.unreadInspectionNotification {
            setInspectionReadyFromNotification(
                inspection,
                on: &job,
                bookingID: bookingID,
                changed: &changed
            )
        } else if remote.inspectionReady {
            // Server flagged ready even if the row list was empty/truncated.
            let phase: InspectionPhase = job.postTripInspection != nil && job.customerApprovedPickupAt != nil
                ? .postTrip
                : .preTrip
            setInspectionReady(
                phase: phase,
                on: &job,
                bookingID: bookingID,
                pushEventID: remote.pendingPush?.id,
                changed: &changed
            )
        }

        // Server-side push_events backup — banner for non-inspection unread pushes.
        if let pending = remote.pendingPush, pending.inspectionPhase == nil {
            // #region agent log
            Self.agentDebugLog(
                hypothesisId: "E",
                location: "BookingStore.applyCloudBookingUpdate",
                message: "pending_push received",
                data: [
                    "event": pending.event ?? "",
                    "hasInspectionPhase": false,
                    "status": job.status.rawValue,
                ]
            )
            // #endregion
            if let status = pending.jobStatusHint {
                InspectionNotificationService.notifyJobStatusChanged(
                    jobID: bookingID,
                    status: status
                )
            } else if let title = pending.title, let body = pending.body {
                InspectionNotificationService.notifyCustomBanner(
                    jobID: bookingID,
                    title: title,
                    body: body,
                    kind: pending.event ?? "push"
                )
            }
            if let pushID = pending.id {
                let email = profileEmail
                Task {
                    await CustomerBookingDispatchService.shared.acknowledgePendingPush(
                        customerEmail: email,
                        bookingID: bookingID,
                        pushEventID: pushID
                    )
                }
            }
            changed = true
        }

        guard changed else { return }

        let newlyReadyPreTrip = !hadPreTrip && job.preTripInspection != nil
            && (job.status == .awaitingCustomerApproval || remote.jobStatus == .awaitingCustomerApproval)
        let newlyReadyPostTrip = !hadPostTrip && job.postTripInspection != nil
            && (job.status == .awaitingReturnApproval || remote.jobStatus == .awaitingReturnApproval)

        // Fallback only when the server has not yet stamped a deadline column.
        if job.status == .awaitingCustomerApproval, job.preTripInspection != nil,
           job.inspectionApprovalDeadline == nil {
            job.inspectionApprovalDeadline = remote.customerApprovalDeadline
                ?? Date().addingTimeInterval(ChargeJob.customerApprovalWindow)
        }
        if job.status == .awaitingReturnApproval, job.postTripInspection != nil,
           job.returnApprovalDeadline == nil {
            job.returnApprovalDeadline = remote.returnApprovalDeadline
                ?? Date().addingTimeInterval(ChargeJob.returnApprovalWindow)
        }

        // Server already advanced past approval — clear local timers.
        if job.customerApprovedPickupAt != nil || job.status == .pickedUp
            || job.status.stepIndex > JobStatus.awaitingCustomerApproval.stepIndex {
            job.inspectionApprovalDeadline = nil
            approvalTimerTask?.cancel()
            approvalTimerTask = nil
        }
        if job.customerApprovedReturnAt != nil || job.status == .delivered {
            job.returnApprovalDeadline = nil
        }

        if job.status == .delivered {
            job.completedAt = Date()
            pastJobs.insert(job, at: 0)
            lastCompletedJob = job
            activeJob = nil
            cloudBookingSyncTask?.cancel()
            cloudBookingSyncTask = nil
            persist()
            if settings.pushNotificationsEnabled, previousStatus != .delivered {
                InspectionNotificationService.notifyJobStatusChanged(jobID: bookingID, status: .delivered)
            }
            return
        }

        activeJob = job
        persist()

        // Inspection-ready alerts always fire for cloud trips (don’t depend on settings alone).
        // Skip if we already surfaced via unread inspection_ready notification above.
        let surfacedViaNotification = remote.inspectionReady
            || remote.unreadInspectionNotification != nil
        if !surfacedViaNotification {
            if newlyReadyPreTrip || (previousStatus != .awaitingCustomerApproval && job.needsCustomerApproval) {
                InspectionNotificationService.notifyInspectionReadyForReview(jobID: bookingID, phase: .preTrip)
            } else if newlyReadyPostTrip || (previousStatus != .awaitingReturnApproval && job.needsReturnApproval) {
                InspectionNotificationService.notifyInspectionReadyForReview(jobID: bookingID, phase: .postTrip)
            } else if settings.pushNotificationsEnabled, previousStatus != job.status {
                let waitingOnInspection =
                    (job.status == .awaitingCustomerApproval && job.preTripInspection == nil)
                    || (job.status == .awaitingReturnApproval && job.postTripInspection == nil)
                if !waitingOnInspection {
                    InspectionNotificationService.notifyJobStatusChanged(jobID: bookingID, status: job.status)
                }
            }
        } else if settings.pushNotificationsEnabled, previousStatus != job.status,
                  !job.needsAnyInspectionApproval {
            InspectionNotificationService.notifyJobStatusChanged(jobID: bookingID, status: job.status)
        }

        resumeApprovalTimerIfNeeded()
    }

    /// Mirrors: notifications.find(n => n.type === "inspection_ready" && !n.readAt) → setInspectionReady(true)
    private func setInspectionReadyFromNotification(
        _ notification: BookingNotificationDTO,
        on job: inout ChargeJob,
        bookingID: UUID,
        changed: inout Bool
    ) {
        let phase = notification.phase
            ?? (notification.event == "inspection_ready_postTrip" ? .postTrip : .preTrip)
        setInspectionReady(
            phase: phase,
            on: &job,
            bookingID: bookingID,
            pushEventID: notification.id,
            changed: &changed
        )
    }

    private func setInspectionReady(
        phase: InspectionPhase,
        on job: inout ChargeJob,
        bookingID: UUID,
        pushEventID: UUID?,
        changed: inout Bool
    ) {
        switch phase {
        case .preTrip:
            if job.status == .driverArrived || job.status == .driverEnRoute {
                job.status = .awaitingCustomerApproval
                changed = true
            }
            if job.status == .awaitingCustomerApproval, job.inspectionApprovalDeadline == nil {
                job.inspectionApprovalDeadline = Date().addingTimeInterval(ChargeJob.customerApprovalWindow)
                changed = true
            }
        case .postTrip:
            if job.status == .awaitingPostTripInspection || job.status == .returning {
                job.status = .awaitingReturnApproval
                changed = true
            }
            if job.status == .awaitingReturnApproval, job.returnApprovalDeadline == nil {
                job.returnApprovalDeadline = Date().addingTimeInterval(ChargeJob.returnApprovalWindow)
                changed = true
            }
        }

        InspectionNotificationService.notifyInspectionReadyForReview(jobID: bookingID, phase: phase)
        if settings.inspectionAlertsEnabled == false {
            settings.inspectionAlertsEnabled = true
            changed = true
        }

        if let pushEventID {
            let email = profileEmail
            Task {
                await CustomerBookingDispatchService.shared.acknowledgePendingPush(
                    customerEmail: email,
                    bookingID: bookingID,
                    pushEventID: pushEventID
                )
            }
        }
        changed = true
    }

    private func startApprovalAutoApproveTimer() {
        approvalTimerTask?.cancel()
        guard let job = activeJob, job.needsCustomerApproval,
              let deadline = job.inspectionApprovalDeadline else { return }

        approvalTimerTask = Task { [weak self] in
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            self?.autoApprovePickupIfNeeded()
        }
    }

    private func startReturnApprovalAutoApproveTimer() {
        approvalTimerTask?.cancel()
        guard let job = activeJob, job.needsReturnApproval,
              let deadline = job.returnApprovalDeadline else { return }

        approvalTimerTask = Task { [weak self] in
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            self?.autoApproveReturnIfNeeded()
        }
    }

    private func resumeApprovalTimerIfNeeded() {
        guard var job = activeJob else { return }

        if job.needsCustomerApproval {
            // Cloud: wait for server deadline; only invent a local one for offline demos.
            if job.inspectionApprovalDeadline == nil {
                if job.isCloudDispatched {
                    return
                }
                job.inspectionApprovalDeadline = Date().addingTimeInterval(ChargeJob.customerApprovalWindow)
                activeJob = job
                persist()
            }
            if let deadline = job.inspectionApprovalDeadline, Date() >= deadline {
                autoApprovePickupIfNeeded()
                return
            }
            startApprovalAutoApproveTimer()
            return
        }

        if job.needsReturnApproval {
            if job.returnApprovalDeadline == nil {
                if job.isCloudDispatched {
                    return
                }
                job.returnApprovalDeadline = Date().addingTimeInterval(ChargeJob.returnApprovalWindow)
                activeJob = job
                persist()
            }
            if let deadline = job.returnApprovalDeadline, Date() >= deadline {
                autoApproveReturnIfNeeded()
                return
            }
            startReturnApprovalAutoApproveTimer()
        }
    }

    private func advanceStatus() {
        guard !driverManualControl else { return }
        guard var job = activeJob else {
            progressionTask?.cancel()
            progressionTask = nil
            return
        }
        // Cloud-dispatched trips are advanced by the driver app / server.
        guard !job.isCloudDispatched else {
            progressionTask?.cancel()
            progressionTask = nil
            return
        }

        // Driver completes pre-trip off-app; customer only sees the finished inspection.
        if job.status == .driverArrived, job.preTripInspection == nil {
            guard !isCompletingDriverPreTrip else { return }
            isCompletingDriverPreTrip = true
            Task {
                await completeDriverPreTripInspection()
                isCompletingDriverPreTrip = false
            }
            return
        }

        // Driver completes post-trip off-app; customer sees it when the booking completes.
        if job.status == .awaitingPostTripInspection, job.postTripInspection == nil {
            guard !isCompletingDriverPostTrip else { return }
            isCompletingDriverPostTrip = true
            Task {
                await completeDriverPostTripInspection()
                isCompletingDriverPostTrip = false
            }
            return
        }

        if job.status.pausesAutoProgression {
            return
        }

        guard let next = job.status.next else {
            progressionTask?.cancel()
            progressionTask = nil
            return
        }

        if next == .delivered {
            return
        }

        job.status = next
        activeJob = job
        persist()

        if settings.pushNotificationsEnabled {
            InspectionNotificationService.notifyJobStatusChanged(jobID: job.id, status: next)
        }
    }

    /// Simulates the driver finishing pre-trip inspection so the customer can review it.
    private func completeDriverPreTripInspection() async {
        guard let job = activeJob, job.status == .driverArrived, job.preTripInspection == nil else {
            return
        }

        let placeholder = Data("chercharge-inspection".utf8)
        let inspection = VehicleInspection(
            id: UUID(),
            jobID: job.id,
            phase: .preTrip,
            driverName: assignedDriverName,
            frontPhotoData: placeholder,
            rearPhotoData: placeholder,
            leftSidePhotoData: placeholder,
            roofPhotoData: placeholder,
            interiorVideoData: placeholder,
            odometerPhotoData: placeholder,
            batteryPercent: job.startingChargePercent,
            damageChecklist: DamageChecklist(),
            tireCondition: .good,
            capturedAt: Date(),
            latitude: job.pickup.latitude,
            longitude: job.pickup.longitude,
            storageURLs: InspectionMediaURLs(),
            uploadedAt: nil
        )

        try? await submitInspection(inspection)
    }

    /// Simulates the driver finishing post-trip inspection so the customer can review it.
    private func completeDriverPostTripInspection() async {
        guard let job = activeJob, job.status == .awaitingPostTripInspection, job.postTripInspection == nil else {
            return
        }

        let placeholder = Data("chercharge-inspection".utf8)
        let inspection = VehicleInspection(
            id: UUID(),
            jobID: job.id,
            phase: .postTrip,
            driverName: assignedDriverName,
            frontPhotoData: placeholder,
            rearPhotoData: placeholder,
            leftSidePhotoData: placeholder,
            roofPhotoData: placeholder,
            interiorVideoData: placeholder,
            odometerPhotoData: placeholder,
            batteryPercent: job.targetChargePercent,
            damageChecklist: job.preTripInspection?.damageChecklist ?? DamageChecklist(),
            tireCondition: job.preTripInspection?.tireCondition ?? .good,
            capturedAt: Date(),
            latitude: job.pickup.latitude,
            longitude: job.pickup.longitude,
            storageURLs: InspectionMediaURLs(),
            uploadedAt: nil
        )

        try? await submitInspection(inspection)
    }

    private func makeLocalReceiptNumber() -> String {
        "CH-\(Calendar.current.component(.year, from: Date()))-\(Int.random(in: 100000...999999))"
    }

    enum StoreError: LocalizedError {
        case insufficientRange
        case documentsPendingApproval
        case documentReviewUnavailable
        case documentRejectionIncomplete
        case vehicleLimitReached
        case vehicleNotFound
        case vehicleIncomplete
        case addressIncomplete
        case addressNotFound
        case inspectionUnavailable
        case inspectionIncomplete
        case approvalUnavailable
        case comparisonUnavailable
        case issueReportIncomplete
        case noPaymentMethod
        case serviceUnavailable
        case jobUnavailable
        case driverActionUnavailable
        case waitingOnCustomer
        case driverDispatchNeedsAccount
        case driverDispatchFailed(String)

        var errorDescription: String? {
            switch self {
            case .insufficientRange:
                return "Needs at least \(Pricing.minimumRangeMiles) miles of range for pickup."
            case .documentsPendingApproval:
                return "An admin must approve the registration photo and insurance policy before booking."
            case .documentReviewUnavailable:
                return "This vehicle isn’t waiting for document review."
            case .documentRejectionIncomplete:
                return "Add a short reason so the customer knows what to fix."
            case .vehicleLimitReached:
                return "You can save up to \(Pricing.maxSavedVehicles) vehicles."
            case .vehicleNotFound:
                return "That vehicle could not be found."
            case .vehicleIncomplete:
                return "Make, model, year, license plate, plate state, registration expiration, insurance company, policy number, policy expiration, and a registration photo are required."
            case .addressIncomplete:
                return "Add a label and street address to save this spot."
            case .addressNotFound:
                return "That address could not be found."
            case .inspectionUnavailable:
                return "Inspection is not available for this booking right now."
            case .inspectionIncomplete:
                return "Complete every required inspection item before continuing."
            case .approvalUnavailable:
                return "Approve pickup is only available after the pre-trip inspection is uploaded."
            case .comparisonUnavailable:
                return "Pickup and return inspections are required before reporting an issue."
            case .issueReportIncomplete:
                return "Add a short description so support can follow up."
            case .noPaymentMethod:
                return "Add a payment method in Profile before booking."
            case .serviceUnavailable:
                return CherchargeServiceAvailability.bookMessage
            case .jobUnavailable:
                return "That charge booking isn’t available."
            case .driverActionUnavailable:
                return "That driver step isn’t available for the current job status."
            case .waitingOnCustomer:
                return "Waiting on the customer to approve inspection before this step."
            case .driverDispatchNeedsAccount:
                return "Sign in with your email and password (not Guest) so we can send your request to a driver."
            case .driverDispatchFailed(let message):
                return "Couldn’t send your request to drivers. \(message)"
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
        let payload: [String: Any] = [
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
