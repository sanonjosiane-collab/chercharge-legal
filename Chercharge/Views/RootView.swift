//
//  RootView.swift
//  Chercharge
//

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BookingStore.self) private var store
    @Environment(AppLockController.self) private var appLock
    @Environment(NotificationPermissionCoordinator.self) private var notificationPermissions
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.isLoading || !store.isHydrated {
                ZStack {
                    ConciergeLuxeBackground()
                    ProgressView()
                        .tint(ConciergeLuxe.emerald)
                }
            } else if auth.isSignedIn {
                ZStack {
                    ContentView()
                        .task(id: auth.firebaseUID ?? auth.userID?.uuidString ?? "signed-in") {
                            // Wait until local photo-heavy state is ready before cloud merge / uploads.
                            while !store.isHydrated {
                                try? await Task.sleep(for: .milliseconds(50))
                            }
                            await store.reloadFromCloud(
                                firebaseUID: auth.firebaseUID,
                                displayName: auth.displayName,
                                displayEmail: auth.displayEmail
                            )
                            // Uses profile email so Firebase/local customers still sync to admin.
                            if store.profileEmail.isEmpty, let email = auth.displayEmail {
                                store.profileEmail = email
                            }
                            await store.syncVehicleDocumentsWithAdmin(
                                customerID: auth.supabaseUserID,
                                preferredEmail: auth.displayEmail
                            )
                            await notificationPermissions.considerPresentingAfterSignIn()
                            await PushRegistrationService.shared.refreshRegistration(
                                customerEmail: auth.displayEmail ?? store.profileEmail,
                                customerID: auth.supabaseUserID,
                                optIn: store.settings.pushNotificationsEnabled
                                    || store.settings.inspectionAlertsEnabled
                            )
                        }

                    if appLock.isLocked, store.settings.faceIDEnabled {
                        faceIDLockOverlay
                            .transition(.opacity)
                            .zIndex(10)
                    }
                }
                .sheet(isPresented: Binding(
                    get: {
                        notificationPermissions.isPresentingPrePrompt || store.shouldOfferNotificationPrePrompt
                    },
                    set: { presented in
                        if !presented {
                            notificationPermissions.deferServiceNotifications()
                            store.shouldOfferNotificationPrePrompt = false
                        }
                    }
                )) {
                    NotificationPermissionSheet(
                        onEnable: {
                            let allowed = await notificationPermissions.enableServiceNotifications()
                            store.shouldOfferNotificationPrePrompt = false
                            var next = store.settings
                            next.pushNotificationsEnabled = allowed
                            if allowed { next.inspectionAlertsEnabled = true }
                            store.settings = next
                            store.persist()
                            if allowed {
                                await PushRegistrationService.shared.refreshRegistration(
                                    customerEmail: auth.displayEmail ?? store.profileEmail,
                                    customerID: auth.supabaseUserID,
                                    optIn: true
                                )
                            }
                            if allowed, let job = store.activeJob {
                                InspectionNotificationService.notifyBookingConfirmed(
                                    jobID: job.id,
                                    scheduledFor: job.scheduledFor
                                )
                            }
                        },
                        onNotNow: {
                            notificationPermissions.deferServiceNotifications()
                            store.shouldOfferNotificationPrePrompt = false
                            var next = store.settings
                            next.pushNotificationsEnabled = false
                            store.settings = next
                            store.persist()
                        }
                    )
                }
            } else {
                SignInView()
                    .onAppear {
                        store.stopCloudSync()
                        appLock.isLocked = false
                    }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.25), value: appLock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            appLock.handleScenePhase(
                phase,
                isSignedIn: auth.isSignedIn,
                faceIDEnabled: store.settings.faceIDEnabled
            )
            if phase == .active, auth.isSignedIn, store.isHydrated {
                Task {
                    await store.syncVehicleDocumentsWithAdmin(
                        customerID: auth.supabaseUserID,
                        preferredEmail: auth.displayEmail
                    )
                }
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn, store.settings.faceIDEnabled {
                appLock.lockIfEnabled(isSignedIn: true, faceIDEnabled: true)
            } else if !signedIn {
                appLock.isLocked = false
            }
        }
        .onChange(of: store.settings.faceIDEnabled) { _, enabled in
            if enabled, auth.isSignedIn {
                appLock.lockIfEnabled(isSignedIn: true, faceIDEnabled: true)
            } else if !enabled {
                appLock.isLocked = false
            }
        }
    }

    private var faceIDLockOverlay: some View {
        ZStack {
            ConciergeLuxeBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "faceid")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(ConciergeLuxe.emerald)

                Text("Chercharge is locked")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundStyle(ConciergeLuxe.charcoal)

                Text(BiometricAuthService.accountAccessReason)
                    .font(.system(.footnote))
                    .foregroundStyle(ConciergeLuxe.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                if let error = appLock.lastError {
                    Text(error)
                        .font(.system(.caption))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await appLock.unlockWithBiometrics() }
                } label: {
                    HStack {
                        if appLock.isAuthenticating {
                            ProgressView().tint(.white)
                        }
                        Text(appLock.isAuthenticating ? "Unlocking…" : "Unlock with \(BiometricAuthService.biometryDisplayName)")
                            .font(.system(.headline, design: .serif).weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)
                            .fill(ConciergeLuxe.emerald)
                    )
                }
                .buttonStyle(.plain)
                .disabled(appLock.isAuthenticating)
                .padding(.horizontal, 28)
                .padding(.top, 8)
            }
        }
        .task {
            await appLock.unlockWithBiometrics()
        }
    }
}

#Preview {
    RootView()
        .environment(BookingStore())
        .environment(AuthService())
        .environment(TeslaAuthService())
        .environment(AppLockController())
        .environment(NotificationPermissionCoordinator())
        .environment(UserLocationService())
}
