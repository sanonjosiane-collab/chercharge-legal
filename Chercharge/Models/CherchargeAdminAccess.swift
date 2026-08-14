//
//  CherchargeAdminAccess.swift
//  Chercharge
//
//  Who can open the in-app admin document review queue.
//

import Foundation

enum CherchargeAdminAccess {
    /// DEBUG builds always include the admin console. Release requires an admin email.
    static func canReviewDocuments(email: String?) -> Bool {
        #if DEBUG
        return true
        #else
        let normalized = email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if normalized == "admin@chercharge.com" { return true }
        if normalized.hasPrefix("admin+") && normalized.hasSuffix("@chercharge.com") { return true }
        return false
        #endif
    }
}
