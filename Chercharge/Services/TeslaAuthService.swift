//
//  TeslaAuthService.swift
//  Chercharge
//
//  Tesla Fleet API OAuth. Client ID + secret live only in Supabase Edge secrets.
//  The app requests an authorize URL from `tesla-oauth-exchange`, then exchanges
//  the code via the same function. Never embed TESLA_CLIENT_SECRET (or Client ID)
//  in Secrets.plist.
//

import AuthenticationServices
import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class TeslaAuthService: NSObject {
    var isConnected = false
    var isConnecting = false
    var connectedEmail: String?
    var accessToken: String?
    var refreshToken: String?
    var errorMessage: String?

    private var authSession: ASWebAuthenticationSession?
    private var tokenExpiresAt: Date?
    private var cachedAudience: String?

    /// Live OAuth is available whenever Supabase is configured; credentials are server-side.
    private var isOAuthConfigured: Bool {
        SupabaseConfig.isConfigured
    }

    /// True when live Tesla Fleet OAuth can run (no demo fallback).
    var isConnectAvailable: Bool { isOAuthConfigured }

    var fleetAudience: String {
        cachedAudience
            ?? SecretsReader.string(for: "TESLA_AUDIENCE")
            ?? "https://fleet-api.prd.na.vn.cloud.tesla.com"
    }

    override init() {
        super.init()
        restoreFromKeychain()
        // Clear any leftover demo tokens from older builds.
        if let accessToken, accessToken.hasPrefix("demo_") {
            disconnect()
        }
    }

    func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        guard isOAuthConfigured else {
            errorMessage = "Tesla account linking is not available in this build. Add vehicles manually in your garage."
            return
        }

        do {
            let code = try await performOAuth()
            let tokens = try await exchangeCode(code)
            applyTokens(tokens, email: "Tesla account")
            isConnected = true
            persistTokens()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        isConnected = false
        connectedEmail = nil
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        errorMessage = nil
        KeychainStore.delete(forKey: "tesla.accessToken")
        KeychainStore.delete(forKey: "tesla.refreshToken")
        KeychainStore.delete(forKey: "tesla.email")
        KeychainStore.delete(forKey: "tesla.expiresAt")
    }

    func applyPersisted(connected: Bool, email: String?) {
        isConnected = connected
        connectedEmail = email
    }

    /// Returns a valid access token, refreshing when expired (live OAuth only).
    func validAccessToken() async throws -> String {
        guard let accessToken else {
            throw TeslaAuthError.notConnected
        }
        if accessToken.hasPrefix("demo_") {
            disconnect()
            throw TeslaAuthError.notConfigured
        }
        if accessToken.hasPrefix("tesla_oauth_") {
            return accessToken
        }
        if let tokenExpiresAt, tokenExpiresAt > Date().addingTimeInterval(60) {
            return accessToken
        }
        guard let refreshToken else {
            throw TeslaAuthError.notConnected
        }
        let tokens = try await refresh(refreshToken)
        applyTokens(tokens, email: connectedEmail ?? "Tesla account")
        persistTokens()
        guard let newToken = self.accessToken else {
            throw TeslaAuthError.tokenExchangeFailed("No access token after refresh.")
        }
        return newToken
    }

    // MARK: - OAuth

    private func performOAuth() async throws -> String {
        let state = UUID().uuidString
        let authURL = try await fetchAuthorizeURL(state: state)

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "chercharge"
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                    return
                }
                let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
                if let oauthError = items?.first(where: { $0.name == "error" })?.value {
                    let detail = items?.first(where: { $0.name == "error_description" })?.value
                    continuation.resume(
                        throwing: TeslaAuthError.oauthDenied(detail ?? oauthError)
                    )
                    return
                }
                guard let code = items?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.authSession = session
            if !session.start() {
                continuation.resume(throwing: URLError(.unknown))
            }
        }
    }

    private func fetchAuthorizeURL(state: String) async throws -> URL {
        let decoded: TeslaAuthorizeURLResponse = try await postTokenExchangeRaw(
            body: [
                "action": "authorize_url",
                "state": state,
            ]
        )
        if let audience = decoded.audience, audience.hasPrefix("https://") {
            cachedAudience = audience
        }
        guard let urlString = decoded.authorizeURL,
              let url = URL(string: urlString) else {
            throw TeslaAuthError.tokenExchangeFailed(
                decoded.error ?? "Authorize URL missing from token server."
            )
        }
        return url
    }

    private func exchangeCode(_ code: String) async throws -> TeslaTokenResponse {
        try await postTokenExchange(body: ["code": code])
    }

    private func refresh(_ refreshToken: String) async throws -> TeslaTokenResponse {
        try await postTokenExchange(body: ["refresh_token": refreshToken])
    }

    private func postTokenExchange(body: [String: String]) async throws -> TeslaTokenResponse {
        let decoded: TeslaTokenAPIResponse = try await postTokenExchangeRaw(body: body)
        guard let access = decoded.accessToken else {
            throw TeslaAuthError.tokenExchangeFailed(
                decoded.error ?? "Token exchange failed."
            )
        }
        return TeslaTokenResponse(
            accessToken: access,
            refreshToken: decoded.refreshToken,
            expiresIn: decoded.expiresIn ?? 28800
        )
    }

    private func postTokenExchangeRaw<T: Decodable>(body: [String: String]) async throws -> T {
        let supabaseURL = try SupabaseConfig.url
        let endpoint = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("tesla-oauth-exchange")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try SupabaseConfig.applyClientAPIHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TeslaAuthError.tokenExchangeFailed("Invalid response from token server.")
        }
        if http.statusCode != 200 {
            let message = (try? JSONDecoder().decode(TeslaAPIErrorBody.self, from: data))?.error
                ?? "Token server failed (\(http.statusCode))."
            throw TeslaAuthError.tokenExchangeFailed(message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func applyTokens(_ tokens: TeslaTokenResponse, email: String) {
        accessToken = tokens.accessToken
        if let refresh = tokens.refreshToken {
            refreshToken = refresh
        }
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        connectedEmail = email
        isConnected = true
    }

    private func persistTokens() {
        if let accessToken { KeychainStore.set(accessToken, forKey: "tesla.accessToken") }
        if let refreshToken { KeychainStore.set(refreshToken, forKey: "tesla.refreshToken") }
        if let connectedEmail { KeychainStore.set(connectedEmail, forKey: "tesla.email") }
        if let tokenExpiresAt {
            KeychainStore.set(
                ISO8601DateFormatter().string(from: tokenExpiresAt),
                forKey: "tesla.expiresAt"
            )
        }
    }

    private func restoreFromKeychain() {
        guard let token = KeychainStore.string(forKey: "tesla.accessToken") else { return }
        accessToken = token
        refreshToken = KeychainStore.string(forKey: "tesla.refreshToken")
        connectedEmail = KeychainStore.string(forKey: "tesla.email")
        if let expiry = KeychainStore.string(forKey: "tesla.expiresAt") {
            tokenExpiresAt = ISO8601DateFormatter().date(from: expiry)
        }
        isConnected = true
    }
}

extension TeslaAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Models / errors

enum TeslaAuthError: LocalizedError {
    case notConnected
    case notConfigured
    case oauthDenied(String)
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect your Tesla account first."
        case .notConfigured:
            return "Tesla account linking is not available in this build."
        case .oauthDenied(let message):
            return message
        case .tokenExchangeFailed(let message):
            return message
        }
    }
}

private struct TeslaTokenResponse {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
}

private struct TeslaTokenAPIResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case error
    }
}

private struct TeslaAPIErrorBody: Decodable {
    let error: String?
}

private struct TeslaAuthorizeURLResponse: Decodable {
    let authorizeURL: String?
    let redirectURI: String?
    let audience: String?
    let state: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case authorizeURL = "authorize_url"
        case redirectURI = "redirect_uri"
        case audience, state, error
    }
}
