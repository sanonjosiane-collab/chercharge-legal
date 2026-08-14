//
//  AppleReviewDemoAccount.swift
//  Chercharge
//
//  App Store Review sign-in credentials.
//  Normal customer flows — Founding Access requires Stripe PaymentSheet (never auto-credited).
//  Paste credentials into App Store Connect → App Review Information.
//

import Foundation
import UIKit

enum AppleReviewDemoAccount {
    /// App Store Connect → App Review Information → Sign-in required.
    static let email = "appreview@chercharge.com"
    static let password = "ReviewChercharge1!"
    static let displayName = "App Review"
    static let phone = "(415) 555-0199"

    /// Stable local user id when signed in via the local review credentials.
    static let userID = UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!

    /// True while signed in with the App Review credentials (AuthService).
    static var isSessionActive = false

    static func matches(email: String, password: String) -> Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == self.email
            && password == self.password
    }

    static func isDemoEmail(_ email: String?) -> Bool {
        email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == self.email
    }

    /// Starting customer state for review: garage ready to book, Founding Access not purchased.
    static func freshPersistedState(now: Date = Date()) -> PersistedAppState {
        let vehicle = reviewTesla(now: now)
        let home = LocationPin(
            id: UUID(uuidString: "D4444444-4444-4444-8444-000000000005")!,
            name: "Home",
            address: "1 Apple Park Way, Cupertino, CA",
            latitude: 37.3349,
            longitude: -122.0090
        )

        return PersistedAppState(
            profileName: displayName,
            profileEmail: email,
            profilePhone: phone,
            vehicles: [vehicle],
            savedAddresses: [home],
            activeJob: nil,
            lastCompletedJob: nil,
            pastJobs: [],
            upcomingJobs: [],
            paymentMethods: [],
            membership: .standard,
            preorder: PreorderState(),
            settings: AppSettings(
                pushNotificationsEnabled: false,
                locationAccessEnabled: true,
                marketingEnabled: false,
                inspectionAlertsEnabled: true,
                faceIDEnabled: false
            ),
            supportTickets: [],
            teslaConnected: false,
            teslaEmail: nil,
            hasCompletedOnboarding: true
        )
    }

    private static func reviewTesla(now: Date) -> Vehicle {
        Vehicle(
            id: UUID(uuidString: "D3333333-3333-4333-8333-000000000004")!,
            name: "Review Model 3",
            make: "Tesla",
            model: "Model 3",
            year: 2023,
            licensePlate: "REVIEW1",
            licensePlateState: "CA",
            registrationExpirationDate: Calendar.current.date(byAdding: .year, value: 1, to: now),
            insurancePolicy: "REVIEW-POLICY-1001",
            insuranceCompanyName: "GEICO",
            insurancePolicyExpirationDate: Calendar.current.date(byAdding: .year, value: 1, to: now),
            currentChargePercent: 34,
            estimatedRangeMiles: 88,
            registrationPhotoData: placeholderDocumentJPEG(),
            insuranceCardPhotoData: placeholderDocumentJPEG(),
            teslaVIN: "5YJ3E1EA1PF000999",
            isTeslaLinked: false,
            paintColor: .pearlWhite,
            documentApprovalStatus: .approved,
            documentsSubmittedAt: now.addingTimeInterval(-60 * 60 * 48),
            documentsReviewedAt: now.addingTimeInterval(-60 * 60 * 40),
            documentRejectionReason: nil
        )
    }

    private static func placeholderDocumentJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200))
        let image = renderer.image { context in
            UIColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            UIColor(red: 0.79, green: 0.64, blue: 0.36, alpha: 1).setStroke()
            let border = UIBezierPath(
                roundedRect: CGRect(x: 12, y: 12, width: 296, height: 176),
                cornerRadius: 12
            )
            border.lineWidth = 2
            border.stroke()
            let text = "CHERCHARGE\nAPP REVIEW\nREGISTRATION"
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineSpacing = 4
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Bold", size: 16) ?? .boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor(red: 0.05, green: 0.22, blue: 0.14, alpha: 1),
                .paragraphStyle: paragraph,
            ]
            (text as NSString).draw(in: CGRect(x: 24, y: 70, width: 272, height: 80), withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }
}
