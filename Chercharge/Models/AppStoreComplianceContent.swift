//
//  AppStoreComplianceContent.swift
//  Chercharge
//
//  In-app App Store metadata, privacy, permissions, and review specification.
//

import Foundation

enum AppStoreComplianceContent {
    static let title = "App Store Compliance Spec"
    static let documentTitle =
        "CHERCHARGE APP STORE METADATA, PRIVACY, PERMISSIONS, ACCOUNT DELETION, AND APP REVIEW SUBMISSION SPECIFICATION"
    static let effectiveDate = "July 14, 2026"
    static let lastUpdated = "July 14, 2026"

    struct Section: Identifiable, Hashable {
        let id: String
        let heading: String?
        let blocks: [FoundingAgreementContent.Block]
    }

    static let sections: [Section] = [
        Section(
            id: "purpose",
            heading: "1. PURPOSE OF THIS DOCUMENT",
            blocks: [
                .paragraph("This document establishes the intended App Store metadata, privacy disclosures, permission descriptions, account deletion requirements, export compliance review, screenshot plan, App Review instructions, and related submission information for the Chercharge mobile application."),
                .paragraph("For purposes of this document, \"Chercharge\" refers to the Chercharge electric vehicle concierge application, service, platform, and business brand."),
                .emphasis("Chercharge is currently in a pre-launch phase."),
                .paragraph("The legal entity presently operating and administering Chercharge must be identified using its current approved legal business name wherever Apple, a payment processor, customer agreement, tax document, or applicable law requires the legal contracting entity."),
                .paragraph("Legal Entity: Chercharge, INC. Business or Service Brand: Chercharge."),
                .paragraph("The App Store app name may be presented as \"Chercharge\" subject to Apple's app naming requirements and the developer's rights to use the name."),
            ]
        ),
        Section(
            id: "app-name",
            heading: "2. APP NAME",
            blocks: [
                .emphasis("Recommended App Name: Chercharge"),
                .paragraph("The app name should not be Chercharge LLC, Chercharge Inc., Chercharge Official, Chercharge Tesla, Tesla Chercharge, Tesla Concierge, Apple Chercharge, Stripe Chercharge, or any name implying affiliation, sponsorship, or endorsement by another company without authorization."),
                .paragraph("Chercharge is an independent service and should not use another vehicle manufacturer's trademark in a manner that falsely suggests the manufacturer owns, sponsors, operates, or officially endorses Chercharge."),
            ]
        ),
        Section(
            id: "subtitle",
            heading: "3. APP SUBTITLE",
            blocks: [
                .emphasis("Recommended Subtitle: EV Charging Concierge"),
                .paragraph("Alternative: EV Pickup & Charging Concierge"),
                .paragraph("Do not use: Unlimited EV Charging; Charge Any EV for $10; Guaranteed 100% Charge; Official Tesla Charging Concierge; or wording that materially misrepresents pre-launch promotional rates or Chercharge's relationship with a vehicle manufacturer."),
            ]
        ),
        Section(
            id: "category",
            heading: "4. PRIMARY APP CATEGORY",
            blocks: [
                .emphasis("Recommended Primary Category: Travel"),
                .paragraph("Potential Secondary Category: Lifestyle"),
                .paragraph("Chercharge provides a location-dependent vehicle concierge service involving vehicle pickup, transportation, charging coordination, and vehicle return."),
                .paragraph("Do not select Finance merely because Stripe processes payments. Do not select a category solely because it appears commercially advantageous."),
            ]
        ),
        Section(
            id: "promo",
            heading: "5. APP STORE PROMOTIONAL TEXT",
            blocks: [
                .paragraph("If still in pre-launch when submitted, use: Chercharge is preparing to bring EV pickup, charging, and return concierge service to eligible customers. Join our pre-launch and explore limited Founding Customer offers before public service begins. Promotional, vehicle, geographic, and service restrictions apply."),
                .paragraph("Do not say: Available everywhere; We charge every EV; Never charge your car again; Guaranteed same-day charging; Unlimited charging; or \"$10 charging for life\" without immediately making material one-customer, one-vehicle, per-eligible-service, five-customer, and vehicle-lifetime restrictions clear."),
            ]
        ),
        Section(
            id: "description",
            heading: "6. APP STORE DESCRIPTION",
            blocks: [
                .emphasis("Your time is too valuable for charging stations."),
                .paragraph("Chercharge is an electric vehicle charging concierge service designed to make EV charging more convenient."),
                .paragraph("Through the Chercharge app, eligible customers can manage their Chercharge account, add eligible vehicles, review available services, request or schedule eligible Chercharge services, receive service updates, manage qualifying promotional benefits, and review applicable booking information."),
                .paragraph("When Chercharge service is available for an eligible booking, the Chercharge concierge experience may include coordinating the pickup of an eligible electric vehicle, transportation of the vehicle for charging, charging coordination, and return of the vehicle to an approved location."),
                .emphasis("CHERCHARGE FEATURES"),
                .bullet("Create and manage your Chercharge account."),
                .bullet("Add and manage eligible electric vehicles."),
                .bullet("Review available Chercharge services."),
                .bullet("Request or schedule eligible service."),
                .bullet("Select eligible pickup and return information."),
                .bullet("Review service pricing before purchase."),
                .bullet("Receive booking and service status updates."),
                .bullet("Manage qualifying Founding Customer promotional benefits."),
                .bullet("Upload or capture vehicle documentation when required for vehicle condition or service support."),
                .bullet("Review applicable service history and account information."),
                .emphasis("FOUNDING CUSTOMER OFFERS"),
                .paragraph("The limited $10 Founding Vehicle Rate is available to a maximum of five accepted qualifying customers and applies only to one specifically enrolled eligible vehicle per accepted customer."),
                .paragraph("The $10 Founding Vehicle Rate is a per-eligible-service promotional base rate. The Founding Access payment is a reservation fee that locks that rate; it is not a deposit or credit toward a future booking, and it is not unlimited service for a single $10 payment."),
                .paragraph("Example: a Founding Customer who pays $10 to reserve the lifetime rate later pays another $10 for each eligible Chercharge booking at that locked rate."),
                .paragraph("The rate does not transfer to a replacement, substitute, additional, rental, loaner, family, business, or newly purchased vehicle."),
                .paragraph("When the original enrolled Founding Vehicle is permanently no longer in service, the applicable $10 Founding Vehicle Rate ends."),
                .paragraph("Eligible customers may also have access to a $39.99 per-eligible-service promotional rate for the applicable one-year promotional period. Paying $39.99 as a Founding Access reservation fee locks that rate; it is not applied as credit to a future booking, and each later eligible booking is charged $39.99 separately."),
                .emphasis("PRE-LAUNCH NOTICE"),
                .paragraph("Purchasing or reserving an eligible pre-launch promotional benefit does not guarantee immediate service, a specific public launch date, a specific appointment time, or service in every geographic area."),
                .emphasis("SERVICE AVAILABILITY"),
                .paragraph("Chercharge service is subject to eligible service areas, driver availability, vehicle eligibility, safety requirements, charging availability, operating capacity, and applicable booking terms. Chercharge does not guarantee that every service request will be accepted."),
                .paragraph("Chercharge is not an emergency response service, towing company, electric utility, vehicle manufacturer, or automobile repair provider unless a specific service is expressly identified otherwise."),
                .emphasis("CHARGING RESULTS"),
                .paragraph("Unless expressly guaranteed in writing for a specific service, Chercharge does not guarantee that every vehicle will be returned at exactly 100% battery."),
                .emphasis("IMPORTANT"),
                .paragraph("Chercharge is an independent EV concierge service. References to third-party vehicle manufacturers, charging providers, payment providers, or other third parties are for compatibility, payment, or service identification purposes and do not imply sponsorship or endorsement unless expressly stated."),
            ]
        ),
        Section(
            id: "keywords",
            heading: "7. KEYWORDS",
            blocks: [
                .paragraph("Recommended draft: EV,electric vehicle,charging,concierge,car,pickup,charge"),
                .paragraph("Do not unnecessarily repeat the exact app name. Do not insert unrelated competitor names. Do not use Tesla unless legally appropriate and Apple metadata rules permit."),
            ]
        ),
        Section(
            id: "support",
            heading: "8. SUPPORT URL",
            blocks: [
                .paragraph("Support URL: https://sanonjosiane-collab.github.io/chercharge-legal/support/ — must be a live HTTPS webpage."),
                .paragraph("Include Chercharge name, support email, booking/billing/vehicle/damage/refund/account deletion/privacy/safety instructions, Terms, Privacy, Founding Agreement links while applicable, and response expectations."),
                .emphasis("Do not submit localhost, Cursor development URLs, private dashboards, Stripe Dashboard, Instagram-only, 404 pages, login-walled support, or \"coming soon\" placeholders with no support information."),
            ]
        ),
        Section(
            id: "privacy-url",
            heading: "9–10. PRIVACY POLICY AND PRIVACY CHOICES URLS",
            blocks: [
                .paragraph("Privacy Policy: https://sanonjosiane-collab.github.io/chercharge-legal/privacy/ — publicly accessible without account, payment, VIN, or app download."),
                .paragraph("Privacy Choices / Support: https://sanonjosiane-collab.github.io/chercharge-legal/support/ — account deletion, privacy requests, and support topics."),
                .paragraph("Terms of Service: https://sanonjosiane-collab.github.io/chercharge-legal/terms/"),
                .paragraph("The policy must identify Chercharge, INC and accurately reflect production data practices including Stripe/payment processor involvement."),
            ]
        ),
        Section(
            id: "app-privacy",
            heading: "11–13. APP PRIVACY, DATA CATEGORIES, AND TRACKING",
            blocks: [
                .emphasis("App Privacy answers must be based on the production application and every integrated third-party SDK—not this document alone."),
                .paragraph("Investigate Contact Info, Location, User Content, Identifiers, Purchases, Financial Info, Usage Data, and Diagnostics as applicable."),
                .paragraph("Contacts, Health & Fitness, Sensitive Info, Search History, and Browsing History are expected Not Collected unless a real feature collects them."),
                .paragraph("Do not declare precise location merely because an address is manually typed. Determine whether the app or SDK accesses device-derived precise location."),
                .paragraph("Tracking answers must match Apple's definition. Do not answer Yes merely because Stripe is used. Do not answer No merely because Chercharge does not sell customer data."),
            ]
        ),
        Section(
            id: "camera",
            heading: "14. CAMERA PERMISSION",
            blocks: [
                .emphasis("Chercharge uses your camera to take vehicle photos for vehicle setup, condition documentation, service verification, and support or damage reports."),
                .paragraph("Request camera access when the customer reaches a feature that requires it—not immediately at first launch without reason."),
                .paragraph("If denied: avoid crashing; explain the feature needs camera; allow return; offer Open Settings where appropriate; provide alternate upload if supported."),
            ]
        ),
        Section(
            id: "photos",
            heading: "15. PHOTO LIBRARY PERMISSION",
            blocks: [
                .emphasis("Chercharge accesses photos you select so you can upload vehicle images for vehicle setup, condition documentation, service verification, and support or damage reports."),
                .paragraph("Prefer Apple's system photo picker when it meets the need. Do not request write access if the app never saves media to the library."),
            ]
        ),
        Section(
            id: "location",
            heading: "16. LOCATION PERMISSION",
            blocks: [
                .emphasis("If device location is used: Chercharge uses your location while you use the app to help identify pickup and return locations, check service availability, and coordinate eligible Chercharge services."),
                .paragraph("Do not request Always location unless production requires background location with clear justification. Provide manual address entry if location is denied."),
            ]
        ),
        Section(
            id: "notifications",
            heading: "17. NOTIFICATION PERMISSION",
            blocks: [
                .paragraph("Pre-prompt: Stay updated on your Chercharge service. Enable notifications for booking, pickup, charging, return, and important account updates."),
                .paragraph("Buttons: Enable Notifications / Not Now. Marketing notifications are optional and separate from transactional service updates."),
            ]
        ),
        Section(
            id: "other-perms",
            heading: "18–21. MICROPHONE, CONTACTS, BLUETOOTH, FACE ID",
            blocks: [
                .paragraph("Do not request microphone, contacts, or Bluetooth unless a real production feature requires them."),
                .emphasis("Face ID (when used): Chercharge uses Face ID to help securely access your account and protect sensitive account actions."),
            ]
        ),
        Section(
            id: "account",
            heading: "22–31. ACCOUNT CREATION AND DELETION",
            blocks: [
                .paragraph("Accounts may be required for vehicle association, booking history, promotional administration, payments, service history, communication, documentation, refunds, fraud prevention, and security."),
                .emphasis("In-app deletion: Profile → Settings → Privacy & Account → Delete Account"),
                .paragraph("Deletion is not logout, uninstall, vehicle removal, or membership cancellation."),
                .paragraph("Warn Founding Customers that deletion may terminate nontransferable promotional benefits including the $10 Founding Vehicle Rate."),
                .paragraph("Require typing DELETE and an acknowledgment checkbox before final deletion. Reauthenticate reasonably without making deletion substantially harder than account creation."),
                .paragraph("Backend should record deletion requests and delete or de-identify eligible data while retaining lawful payment, tax, fraud, insurance, claim, and dispute records as required."),
                .paragraph("Do not automatically assign a deleted customer's $10 Founding Vehicle Rate to a newly created account based on the same email, phone, name, payment method, or vehicle."),
            ]
        ),
        Section(
            id: "in-app-legal",
            heading: "32–34. IN-APP LEGAL ACCESS",
            blocks: [
                .bullet("Privacy Policy: Profile → Settings → Legal & Privacy → Privacy Policy"),
                .bullet("Terms of Service: Profile → Settings → Legal & Privacy → Terms of Service"),
                .bullet("Founding Customer Agreement: Profile → Settings → Legal & Privacy → Founding Customer Agreement"),
                .paragraph("The Founding Customer Agreement must also be accessible from promotional checkout without losing progress."),
            ]
        ),
        Section(
            id: "checkboxes",
            heading: "35. REQUIRED PRE-LAUNCH PURCHASE CHECKBOXES",
            blocks: [
                .paragraph("Before purchasing the $10 Founding Vehicle Rate, require separate affirmative acknowledgments for pre-launch status, per-eligible-service pricing, one-vehicle nontransferability, end when the vehicle is out of service, refund rights, and agreement to Founding Customer Agreement, Terms, and Privacy Policy."),
                .emphasis("Do not pre-check boxes. Keep purchase disabled until all required acknowledgments are selected."),
            ]
        ),
        Section(
            id: "age",
            heading: "36. AGE RATING",
            blocks: [
                .paragraph("Complete Apple's age rating questionnaire based on actual app content. Contractual service eligibility remains 18+ even if Apple's content rating is lower."),
                .paragraph("Account gate: You must be at least 18 years old and legally capable of entering into a binding agreement to create a Chercharge service account."),
            ]
        ),
        Section(
            id: "export",
            heading: "37. EXPORT COMPLIANCE AND ENCRYPTION",
            blocks: [
                .paragraph("Audit actual encryption including HTTPS/TLS, authentication, Stripe, secure storage, and Keychain. Do not answer based solely on \"I did not personally write encryption code.\""),
                .emphasis("Final App Store Connect export compliance answer: TO BE CONFIRMED AFTER PRODUCTION CODE AUDIT."),
                .paragraph("Do not change ITSAppUsesNonExemptEncryption until a written encryption audit is complete."),
            ]
        ),
        Section(
            id: "stripe",
            heading: "38. STRIPE AND PAYMENT REVIEW",
            blocks: [
                .paragraph("Verify PaymentSheet, PaymentIntents, stored Stripe Customer/PaymentIntent IDs, payment status, card brand/last4, billing info, webhooks, and that no Stripe secret key is in the iOS app."),
                .paragraph("Privacy Policy and App Privacy answers must match the actual payment architecture."),
            ]
        ),
        Section(
            id: "screenshots",
            heading: "39–40. APP STORE SCREENSHOTS",
            blocks: [
                .paragraph("Prepare 5–8 accurate screenshots with fictional demo data. When showing the $10 offer, include Limited to 5 accepted customers, One enrolled vehicle, and Per eligible service."),
                .paragraph("Do not show secrets, real customer data, debug tools, Cursor, localhost, or unavailable features as fully live. Update or remove filled Founding spots before submission."),
            ]
        ),
        Section(
            id: "review",
            heading: "41–43. APP REVIEW",
            blocks: [
                .paragraph("Provide a working demo account and notes covering pre-launch status, Founding restrictions, physical service nature, account deletion path, photo permissions, Privacy/Support URLs, and demo credentials."),
                .emphasis("DEMO ACCOUNT (paste into App Store Connect → App Review Information)"),
                .paragraph("Email: \(AppleReviewDemoAccount.email)"),
                .paragraph("Password: \(AppleReviewDemoAccount.password)"),
                .paragraph("This is a normal customer login for App Review. Sign in with email/password. Founding Access Accept & Pay must present Stripe PaymentSheet. Book a Charge, Reservations, and Live Status are available. See APP_STORE_REVIEW_NOTES.md."),
                .paragraph("Review contact: Josiane Sanon — use an actively monitored phone and email during App Review."),
            ]
        ),
        Section(
            id: "copyright",
            heading: "44–45. COPYRIGHT AND CONTENT RIGHTS",
            blocks: [
                .emphasis("© 2026 Chercharge, INC. All rights reserved. Chercharge is a business and service brand of Chercharge, INC."),
                .paragraph("Confirm rights to logos, crown artwork, vehicle photos, fonts, icons, music, animations, stock images, and marketing graphics. Do not imply manufacturer affiliation without authorization."),
            ]
        ),
        Section(
            id: "audit",
            heading: "46–47. PRE-LAUNCH REVIEW AND COMPLIANCE AUDIT",
            blocks: [
                .paragraph("Before submission, verify account flows, Founding limits, agreement checkboxes, payments, permissions, account deletion backend behavior, HTTPS production endpoints, and that metadata matches the submitted build."),
                .emphasis("Do not claim the app is App Store ready merely because it builds successfully. A full production privacy and compliance audit is required first."),
            ]
        ),
    ]
}
