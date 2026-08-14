//
//  SupabaseClientProvider.swift
//  Chercharge
//

import Foundation
import Supabase

enum SupabaseClientProvider {
    static let shared: SupabaseClient = {
        do {
            try SupabaseConfig.validate()
            return SupabaseClient(
                supabaseURL: try SupabaseConfig.url,
                supabaseKey: try SupabaseConfig.publishableKey
            )
        } catch {
            // Placeholder client so the app can still launch and show setup/auth errors.
            return SupabaseClient(
                supabaseURL: URL(string: "https://placeholder.supabase.co")!,
                supabaseKey: "placeholder"
            )
        }
    }()
}
