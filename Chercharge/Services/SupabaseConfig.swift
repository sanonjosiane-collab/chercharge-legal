//
//  SupabaseConfig.swift
//  Chercharge
//

import Foundation

enum SupabaseConfig {
    enum ConfigError: LocalizedError {
        case missingPlist
        case missingKey(String)
        case invalidURL
        case placeholderValues

        var errorDescription: String? {
            switch self {
            case .missingPlist:
                return "Add Secrets.plist (copy from Secrets.example.plist) with your Supabase URL and publishable key."
            case .missingKey(let key):
                return "Secrets.plist is missing \(key)."
            case .invalidURL:
                return "SUPABASE_URL in Secrets.plist is not a valid URL."
            case .placeholderValues:
                return "Replace the placeholder values in Secrets.plist with your Supabase project credentials."
            }
        }
    }

    static var url: URL {
        get throws {
            let raw = try stringValue(for: "SUPABASE_URL")
            guard let url = URL(string: raw) else { throw ConfigError.invalidURL }
            return url
        }
    }

    /// Client key: prefer `SUPABASE_PUBLISHABLE_KEY` (`sb_publishable_…`), fall back to legacy `SUPABASE_ANON_KEY`.
    static var publishableKey: String {
        get throws {
            if let key = try optionalStringValue(for: "SUPABASE_PUBLISHABLE_KEY"), !key.isEmpty {
                return key
            }
            if let key = try optionalStringValue(for: "SUPABASE_ANON_KEY"), !key.isEmpty {
                return key
            }
            throw ConfigError.missingKey("SUPABASE_PUBLISHABLE_KEY")
        }
    }

    /// Legacy alias — same value as `publishableKey`.
    static var anonKey: String {
        get throws { try publishableKey }
    }

    static var isConfigured: Bool {
        (try? validate()) != nil
    }

    /// True when the configured client key is the new `sb_publishable_…` format (not a JWT).
    static var usesNewPublishableKey: Bool {
        (try? publishableKey.hasPrefix("sb_publishable_")) ?? false
    }

    static func validate() throws {
        let urlString = try stringValue(for: "SUPABASE_URL")
        let key = try publishableKey
        if urlString.contains("YOUR_PROJECT_REF")
            || key.contains("YOUR_SUPABASE_PUBLISHABLE_KEY")
            || key.contains("YOUR_SUPABASE_ANON_KEY") {
            throw ConfigError.placeholderValues
        }
        guard URL(string: urlString) != nil else { throw ConfigError.invalidURL }
    }

    /// Applies headers for calling Supabase REST / Edge Functions from the iOS client.
    /// - New publishable keys go in `apikey` only (never as `Authorization: Bearer`).
    /// - Legacy anon JWTs are still sent as both `apikey` and `Bearer` for older gateways.
    /// - Pass `authorizationBearer` when you have a user session JWT (e.g. pre-order).
    static func applyClientAPIHeaders(
        to request: inout URLRequest,
        authorizationBearer: String? = nil
    ) throws {
        let key = try publishableKey
        request.setValue(key, forHTTPHeaderField: "apikey")

        if let authorizationBearer, !authorizationBearer.isEmpty {
            request.setValue("Bearer \(authorizationBearer)", forHTTPHeaderField: "Authorization")
        } else if key.hasPrefix("eyJ") {
            // Legacy anon JWT — required when Edge Function `verify_jwt` expects a JWT.
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        // `sb_publishable_…` must not be sent as Bearer (platform returns Invalid JWT).
    }

    private static func secretsDict() throws -> [String: Any] {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            throw ConfigError.missingPlist
        }
        return dict
    }

    private static func stringValue(for key: String) throws -> String {
        guard let value = try optionalStringValue(for: key), !value.isEmpty else {
            throw ConfigError.missingKey(key)
        }
        return value
    }

    private static func optionalStringValue(for key: String) throws -> String? {
        let dict = try secretsDict()
        return dict[key] as? String
    }
}
