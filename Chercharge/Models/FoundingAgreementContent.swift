//
//  FoundingAgreementContent.swift
//  Chercharge
//
//  In-app copy of the Pre-Launch Founding Customer Promotional Rate Agreement.
//

import Foundation

enum FoundingAgreementContent {
    static let title = "Founding Customer Agreement"
    static let documentTitle =
        "CHERCHARGE PRE-LAUNCH FOUNDING CUSTOMER PROMOTIONAL RATE AGREEMENT"
    static let effectiveDate = "July 14, 2026"
    static let lastUpdated = "July 14, 2026"
    /// Approved legal contracting entity.
    static let legalBusinessName = "Chercharge, INC"

    struct Section: Identifiable, Hashable {
        let id: String
        let heading: String?
        let blocks: [Block]
    }

    enum Block: Hashable {
        case paragraph(String)
        case emphasis(String)
        case bullet(String)
        case numbered(Int, String)
    }

    static let sections: [Section] = [
        Section(
            id: "important",
            heading: "IMPORTANT PRE-LAUNCH AGREEMENT",
            blocks: [
                .paragraph(
                    "PLEASE READ THIS AGREEMENT CAREFULLY AND IN ITS ENTIRETY BEFORE MAKING A PURCHASE."
                ),
                .paragraph(
                    "This Chercharge Pre-Launch Founding Customer Promotional Rate Agreement (\"Agreement\") is a legally binding agreement between the individual electronically accepting this Agreement and/or completing an applicable pre-launch promotional purchase (\"Customer,\" \"you,\" or \"your\") and \(legalBusinessName), the business entity currently offering and administering services under the Chercharge brand (\"Company,\" \"we,\" \"our,\" or \"us\")."
                ),
                .paragraph(
                    "For purposes of this Agreement, \"Chercharge\" refers to the electric vehicle concierge service, platform, application, program, trade name, business brand, and related services marketed or offered by the Company under the Chercharge name."
                ),
                .paragraph(
                    "Chercharge is the business and service brand of Chercharge, INC. References to \"Chercharge\" throughout this Agreement refer to the services and brand offered by the Company, Chercharge, INC."
                ),
                .paragraph(
                    "The Company is the legal contracting party responsible for administering the Chercharge pre-launch promotional program unless and until this Agreement is lawfully assigned, transferred, or assumed by a successor or affiliated legal entity as permitted by this Agreement and applicable law."
                ),
                .paragraph(
                    "This Agreement governs participation in the limited Chercharge pre-launch promotional program."
                ),
                .paragraph(
                    "This Agreement supplements the Chercharge Terms of Service, Privacy Policy, applicable checkout disclosures, and any other policies expressly incorporated into this Agreement."
                ),
                .paragraph(
                    "If a provision of this Agreement directly conflicts with the general Chercharge Terms of Service regarding the specific promotional rate purchased under this Agreement, this Agreement will control solely with respect to that promotional rate."
                ),
            ]
        ),
        Section(
            id: "future-entity",
            heading: "FUTURE CHERCHARGE LEGAL ENTITY OR BUSINESS NAME",
            blocks: [
                .paragraph("The Customer understands that the Company may later:"),
                .bullet("Reorganize under a successor or affiliated legal entity;"),
                .bullet("Register additional assumed business names, trade names, fictitious names, or DBAs;"),
                .bullet("Change its legal business name;"),
                .bullet("Transfer the Chercharge business operations to an affiliated entity;"),
                .bullet("Reorganize the Chercharge business;"),
                .bullet("Merge Chercharge operations into another entity;"),
                .bullet("Sell substantially all Chercharge business assets;"),
                .bullet("Assign eligible Chercharge customer agreements to a lawful successor; or"),
                .bullet("Otherwise modify the legal entity through which Chercharge operates."),
                .paragraph(
                    "To the extent permitted by applicable law, the Company may assign this Agreement to a successor, affiliate, reorganized entity, purchaser of substantially all relevant Chercharge business assets, or legal entity that assumes the operation of the Chercharge service."
                ),
                .paragraph(
                    "Any permitted assignment does not, by itself, cancel a valid Customer promotional rate."
                ),
                .paragraph(
                    "If a successor entity expressly assumes this Agreement and continues the applicable Chercharge service, the Customer's promotional rights and obligations under this Agreement will continue subject to the terms of this Agreement."
                ),
                .paragraph(
                    "The Company may notify Customers of a material change to the legal entity operating Chercharge through the Chercharge application, the Customer's registered email address, the Chercharge website, or another reasonable written electronic method."
                ),
                .paragraph(
                    "A change in the legal name of the business operating Chercharge does not, by itself, create a new $10 Founding Vehicle Rate, extend the $39.99 One-Year Founding Rate, permit a vehicle substitution, or otherwise expand the Customer's promotional rights."
                ),
                .paragraph(
                    "A Customer may not argue that a valid promotional restriction disappeared solely because the legal entity operating Chercharge changed its name, converted its business structure, reorganized, or lawfully assigned the Agreement to a successor that assumed the applicable obligations."
                ),
                .paragraph(
                    "Likewise, the Company may not use a sham legal name change, sham entity transfer, or artificial reorganization undertaken primarily for the purpose of evading valid vested promotional obligations while continuing a materially identical Chercharge service."
                ),
            ]
        ),
        Section(
            id: "acknowledgment",
            heading: "CUSTOMER ACKNOWLEDGMENT OF BUSINESS NAME STATUS",
            blocks: [
                .paragraph("BY ACCEPTING THIS AGREEMENT, THE CUSTOMER EXPRESSLY ACKNOWLEDGES:"),
                .emphasis(
                    "I UNDERSTAND THAT CHERCHARGE IS THE NAME OF THE SERVICE, PLATFORM, APPLICATION, PROGRAM, AND/OR BUSINESS BRAND DESCRIBED IN THIS AGREEMENT."
                ),
                .emphasis(
                    "I UNDERSTAND THAT MY AGREEMENT IS WITH CHERCHARGE, INC, THE LEGAL BUSINESS ENTITY IDENTIFIED AT THE BEGINNING OF THIS AGREEMENT."
                ),
                .emphasis(
                    "I UNDERSTAND THAT THE LEGAL ENTITY OPERATING CHERCHARGE MAY LATER CHANGE AS PERMITTED BY THIS AGREEMENT AND APPLICABLE LAW."
                ),
                .emphasis(
                    "I UNDERSTAND THAT A LAWFUL BUSINESS NAME CHANGE, ENTITY CONVERSION, REORGANIZATION, OR PERMITTED ASSIGNMENT DOES NOT AUTOMATICALLY CANCEL THIS AGREEMENT."
                ),
                .emphasis(
                    "I UNDERSTAND THAT MY PROMOTIONAL RIGHTS REMAIN SUBJECT TO THE SPECIFIC TERMS, VEHICLE LIMITATIONS, SERVICE LIMITATIONS, REFUND RIGHTS, AND OTHER CONDITIONS CONTAINED IN THIS AGREEMENT."
                ),
                .paragraph(
                    "BY SELECTING THE REQUIRED AGREEMENT CHECKBOX, ELECTRONICALLY ACCEPTING THIS AGREEMENT, AND SUBMITTING PAYMENT, YOU ACKNOWLEDGE AND AGREE THAT:"
                ),
                .numbered(1, "CHERCHARGE IS IN A PRE-LAUNCH PHASE;"),
                .numbered(
                    2,
                    "CHERCHARGE'S ELECTRIC VEHICLE PICKUP, CHARGING COORDINATION, AND RETURN CONCIERGE SERVICE MAY NOT YET BE COMMERCIALLY AVAILABLE;"
                ),
                .numbered(
                    3,
                    "YOU ARE PAYING A RESERVATION FEE THAT LOCKS A LIMITED PROMOTIONAL PER-CHARGE RATE FOR FUTURE ELIGIBLE CHERCHARGE SERVICES;"
                ),
                .numbered(
                    4,
                    "THAT RESERVATION FEE IS NOT A DEPOSIT OR CREDIT TOWARD A FUTURE BOOKING; EACH ELIGIBLE SERVICE IS CHARGED SEPARATELY AT YOUR LOCKED RATE;"
                ),
                .numbered(
                    5,
                    "YOU ARE NOT PURCHASING AN ELECTRIC VEHICLE, ELECTRICITY SUPPLY CONTRACT, INSURANCE POLICY, SECURITY, INVESTMENT, OWNERSHIP INTEREST, EQUITY INTEREST, OR GUARANTEED QUANTITY OF SERVICES;"
                ),
                .numbered(
                    6,
                    "YOUR PROMOTIONAL RATE IS SUBJECT TO THE ELIGIBILITY, VEHICLE, SERVICE AREA, SAFETY, AVAILABILITY, AND OPERATIONAL TERMS DESCRIBED IN THIS AGREEMENT;"
                ),
                .numbered(
                    7,
                    "CHERCHARGE DOES NOT GUARANTEE A SPECIFIC PUBLIC LAUNCH DATE EXCEPT FOR THE REFUND RIGHTS EXPRESSLY PROVIDED IN THIS AGREEMENT;"
                ),
                .numbered(
                    8,
                    "YOU UNDERSTAND THAT YOUR AGREEMENT IS WITH CHERCHARGE, INC;"
                ),
                .numbered(
                    9,
                    "YOU UNDERSTAND THAT THE LEGAL ENTITY OPERATING CHERCHARGE MAY LATER CHANGE AS PERMITTED BY THIS AGREEMENT AND APPLICABLE LAW; AND"
                ),
                .numbered(10, "YOU HAVE READ AND AGREE TO THIS AGREEMENT."),
                .emphasis(
                    "IF YOU DO NOT AGREE TO EVERY MATERIAL TERM OF THIS AGREEMENT, DO NOT COMPLETE THE PURCHASE."
                ),
            ]
        ),
    ]
}
