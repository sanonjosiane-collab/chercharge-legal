//
//  ConnectTeslaView.swift
//  Chercharge
//

import SwiftUI

struct ConnectTeslaView: View {
    @Environment(BookingStore.self) private var store
    @Environment(TeslaAuthService.self) private var teslaAuth
    @Environment(\.dismiss) private var dismiss

    @State private var localError: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            Image(systemName: "bolt.car.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(Brand.greenDeep)

            Text("Connect Tesla")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.ink)

            Text("Securely link your Tesla account to import vehicles into your Chercharge garage.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if let errorMessage = localError ?? teslaAuth.errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            if teslaAuth.isConnectAvailable {
                Button {
                    Task { await connect() }
                } label: {
                    if teslaAuth.isConnecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign in with Tesla")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(teslaAuth.isConnecting)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            } else {
                Text("Tesla linking isn’t configured for this build. Add vehicles manually from your garage.")
                    .font(.system(.footnote))
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .brandBackground()
        .navigationTitle("Tesla")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func connect() async {
        localError = nil
        await teslaAuth.connect()
        guard teslaAuth.isConnected, let token = teslaAuth.accessToken else { return }

        do {
            let vehicles = try await TeslaVehicleService.fetchLinkedVehicles(
                accessToken: token,
                audience: teslaAuth.fleetAudience
            )
            guard !vehicles.isEmpty else {
                localError = "No vehicles found on this Tesla account."
                return
            }
            store.importTeslaVehicles(vehicles)
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ConnectTeslaView()
    }
    .environment(BookingStore())
    .environment(TeslaAuthService())
}
