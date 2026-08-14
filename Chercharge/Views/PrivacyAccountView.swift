//
//  PrivacyAccountView.swift
//  Chercharge
//
//  Profile → Settings → Privacy & Account → Delete Account + Face ID
//

import SwiftUI

struct PrivacyAccountView: View {
    @Environment(BookingStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(AppLockController.self) private var appLock

    @State private var password = ""
    @State private var confirmPhrase = ""
    @State private var isDeleting = false
    @State private var showConfirm = false
    @State private var statusMessage: String?
    @State private var didDelete = false
    @State private var isEnablingFaceID = false

    private var isGuest: Bool {
        (auth.displayEmail ?? store.profileEmail).hasSuffix("@chercharge.local")
    }

    private var canSubmit: Bool {
        guard !isDeleting else { return false }
        guard confirmPhrase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE" else {
            return false
        }
        if isGuest { return true }
        return password.count >= 6
    }

    var body: some View {
        ConciergeProfilePage {
            ConciergeRoyalBanner(
                eyebrow: "Privacy",
                title: "Privacy & Account",
                subtitle: "Control your Chercharge account and data.",
                systemImage: "hand.raised.fill"
            )

            ConciergeCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR ACCOUNT")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    metaRow("Signed in as", auth.displayEmail ?? store.profileEmail)
                    metaRow("Auth", auth.authBackendLabel)
                }
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("FACE ID")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text(BiometricAuthService.accountAccessReason)
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if BiometricAuthService.isBiometricsAvailable {
                        Toggle(
                            "Require \(BiometricAuthService.biometryDisplayName)",
                            isOn: faceIDBinding
                        )
                        .tint(ConciergeLuxe.emerald)
                        .font(.system(.body, design: .serif))
                        .disabled(isEnablingFaceID)

                        if isEnablingFaceID {
                            ProgressView()
                                .tint(ConciergeLuxe.emerald)
                        }
                    } else {
                        Text("\(BiometricAuthService.biometryDisplayName) is not available or not enrolled on this device.")
                            .font(.system(.caption))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }
                }
            }

            ConciergeCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DELETE ACCOUNT")
                        .font(.system(.caption2).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ConciergeLuxe.goldDark)

                    Text("Permanently delete your Chercharge account from within the app. This removes your sign-in credentials and associated account data we store for this app.")
                        .font(.system(.footnote))
                        .foregroundStyle(ConciergeLuxe.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("This cannot be undone. Active Founding Access, bookings, and saved vehicles on this account will no longer be available after deletion.")
                        .font(.system(.footnote).weight(.medium))
                        .foregroundStyle(ConciergeLuxe.charcoal)
                        .fixedSize(horizontal: false, vertical: true)

                    if !isGuest {
                        SecureField("Account password", text: $password)
                            .textContentType(.password)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(ConciergeLuxe.ivoryDeep.opacity(0.9))
                            )
                    } else {
                        Text("Guest sessions have no remote account. Deleting clears this device’s guest profile.")
                            .font(.system(.caption))
                            .foregroundStyle(ConciergeLuxe.muted)
                    }

                    TextField("Type DELETE to confirm", text: $confirmPhrase)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ConciergeLuxe.ivoryDeep.opacity(0.9))
                        )

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(.footnote))
                            .foregroundStyle(didDelete ? ConciergeLuxe.emerald : .red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await confirmDeleteTapped() }
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView().tint(.white)
                            }
                            Text(isDeleting ? "Deleting…" : "Delete Account")
                                .font(.system(.headline, design: .serif).weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: ConciergeLuxe.cornerRadius, style: .continuous)
                                .fill(canSubmit ? Color.red.opacity(0.85) : Color.red.opacity(0.35))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
            }

            ConciergeInfoRibbon(
                text: "Apple requires an in-app way to delete accounts created in the app. Face ID protects account access when enabled."
            )
        }
        .navigationTitle("Privacy & Account")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isDeleting || didDelete)
        .confirmationDialog(
            "Delete your Chercharge account?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and associated app data will be permanently removed. This cannot be undone.")
        }
    }

    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { store.settings.faceIDEnabled },
            set: { newValue in
                Task { await setFaceIDEnabled(newValue) }
            }
        )
    }

    private func setFaceIDEnabled(_ enabled: Bool) async {
        if enabled {
            isEnablingFaceID = true
            defer { isEnablingFaceID = false }
            let result = await BiometricAuthService.authenticate()
            switch result {
            case .success:
                var next = store.settings
                next.faceIDEnabled = true
                store.updateSettings(next)
                appLock.lockIfEnabled(isSignedIn: auth.isSignedIn, faceIDEnabled: true)
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        } else {
            var next = store.settings
            next.faceIDEnabled = false
            store.updateSettings(next)
            appLock.isLocked = false
        }
    }

    private func confirmDeleteTapped() async {
        statusMessage = nil
        if store.settings.faceIDEnabled {
            let result = await BiometricAuthService.authenticate(
                reason: "Confirm it’s you before deleting your Chercharge account."
            )
            switch result {
            case .success:
                showConfirm = true
            case .failure(.cancelled):
                break
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        } else {
            showConfirm = true
        }
    }

    private func performDelete() async {
        isDeleting = true
        statusMessage = nil
        defer { isDeleting = false }

        let ok = await auth.deleteAccount(password: password)
        if ok {
            store.clearAfterAccountDeletion()
            password = ""
            confirmPhrase = ""
            didDelete = true
            appLock.isLocked = false
            statusMessage = "Your Chercharge account has been deleted. You can close the app or create a new account from sign-in."
        } else {
            statusMessage = auth.errorMessage ?? "Could not delete account. Check your password and try again."
        }
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.subheadline))
                .foregroundStyle(ConciergeLuxe.muted)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundStyle(ConciergeLuxe.charcoal)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyAccountView()
    }
    .environment(BookingStore())
    .environment(AuthService())
    .environment(AppLockController())
}
