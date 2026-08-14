//
//  SignUpView.swift
//  Chercharge
//

import SwiftUI

struct SignUpView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Create account")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.ink)

                Text("Create your Chercharge account to save vehicles, addresses, and booking history.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Brand.muted)

                field("Full name", text: $fullName)
                    .textContentType(.name)

                field("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password (min 6 characters)", text: $password)
                    .textContentType(.newPassword)
                    .padding(14)
                    .background(fieldBackground)

                if let errorMessage = auth.errorMessage {
                    Text(errorMessage)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        isBusy = true
                        await auth.signUp(
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password,
                            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        isBusy = false
                        if auth.isSignedIn {
                            dismiss()
                        }
                    }
                } label: {
                    if isBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign up")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isBusy || fullName.isEmpty || email.isEmpty || password.count < 6)
            }
            .padding(24)
        }
        .brandBackground()
        .navigationTitle("Sign up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .padding(14)
            .background(fieldBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.95))
    }
}

#Preview {
    NavigationStack {
        SignUpView()
    }
    .environment(AuthService())
}
