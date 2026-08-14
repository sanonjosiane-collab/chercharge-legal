//
//  SignInView.swift
//  Chercharge
//

import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var isReviewBusy = false
    @State private var showSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    CCLogo(size: 64)

                    Text("Chercharge")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundStyle(Brand.ink)

                    Text("Sign in to manage your garage and book your EV concierge.")
                        .font(.system(.subheadline))
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)

                    #if DEBUG
                    Text(auth.authBackendLabel)
                        .font(.system(.caption2).weight(.semibold))
                        .foregroundStyle(Brand.gold)
                    #endif
                }

                #if DEBUG
                if let configError = auth.configError {
                    Text("Cloud auth unavailable — using secure local accounts.\n\(configError)")
                        .font(.system(.caption2))
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                #endif

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(fieldBackground)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(14)
                        .background(fieldBackground)
                }
                .padding(.horizontal, 24)

                if let errorMessage = auth.errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task {
                        isBusy = true
                        await auth.signIn(
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password
                        )
                        isBusy = false
                    }
                } label: {
                    if isBusy {
                        ProgressView().tint(Brand.goldBright)
                    } else {
                        Text("Sign in")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isBusy || isReviewBusy || email.isEmpty || password.isEmpty)
                .padding(.horizontal, 24)

                Button("Create an account") {
                    showSignUp = true
                }
                .font(.system(.subheadline).weight(.semibold))
                .foregroundStyle(Brand.greenDeep)
                .disabled(isBusy || isReviewBusy)

                #if DEBUG
                appleReviewerEntry
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                #endif

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .brandBackground()
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
        }
    }

    /// App Store Review sign-in — same customer flows as any account (including live Stripe for Founding Access).
    private var appleReviewerEntry: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Brand.gold.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, 28)

            Text("APP STORE REVIEW")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Brand.gold)

            Button {
                isReviewBusy = true
                auth.signInAsAppleReviewer()
                isReviewBusy = false
            } label: {
                HStack(spacing: 10) {
                    if isReviewBusy {
                        ProgressView()
                            .tint(Brand.greenDeep)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text("Sign in for App Review")
                        .font(.system(.subheadline, design: .serif).weight(.semibold))
                }
                .foregroundStyle(Brand.greenDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Brand.gold.opacity(0.55), lineWidth: 1.2)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy || isReviewBusy)
            .accessibilityHint("Signs in with the App Store Review account.")

            Text("Uses the review credentials below. Founding Access requires Stripe checkout like any customer.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)

            VStack(spacing: 2) {
                Text(AppleReviewDemoAccount.email)
                Text(AppleReviewDemoAccount.password)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Brand.muted.opacity(0.85))
            .multilineTextAlignment(.center)
            .accessibilityLabel(
                "Review credentials \(AppleReviewDemoAccount.email), password \(AppleReviewDemoAccount.password)"
            )
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.92))
    }
}

#Preview {
    SignInView()
        .environment(AuthService())
}
