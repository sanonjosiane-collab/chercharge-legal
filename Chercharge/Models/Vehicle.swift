//
//  Vehicle.swift
//  Chercharge
//

import Foundation

/// Exterior paint options that map to Tesla's compositor color codes.
enum TeslaPaint: String, CaseIterable, Identifiable, Codable, Hashable {
    case pearlWhite
    case solidBlack
    case deepBlue
    case midnightSilver
    case red
    case silver

    var id: String { rawValue }

    /// Tesla compositor option code (used in the `options` query parameter).
    var compositorCode: String {
        switch self {
        case .pearlWhite: return "$PPSW"
        case .solidBlack: return "$PBSB"
        case .deepBlue: return "$PPSB"
        case .midnightSilver: return "$PMNG"
        case .red: return "$PPMR"
        case .silver: return "$PMSS"
        }
    }

    var label: String {
        switch self {
        case .pearlWhite: return "Pearl White"
        case .solidBlack: return "Solid Black"
        case .deepBlue: return "Deep Blue"
        case .midnightSilver: return "Midnight Silver"
        case .red: return "Red"
        case .silver: return "Silver"
        }
    }
}

/// US states / DC for license plate registration.
enum USLicensePlateState: String, CaseIterable, Identifiable, Codable, Hashable {
    case AL, AK, AZ, AR, CA, CO, CT, DE, FL, GA
    case HI, ID, IL, IN, IA, KS, KY, LA, ME, MD
    case MA, MI, MN, MS, MO, MT, NE, NV, NH, NJ
    case NM, NY, NC, ND, OH, OK, OR, PA, RI, SC
    case SD, TN, TX, UT, VT, VA, WA, WV, WI, WY, DC

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .AL: return "Alabama"
        case .AK: return "Alaska"
        case .AZ: return "Arizona"
        case .AR: return "Arkansas"
        case .CA: return "California"
        case .CO: return "Colorado"
        case .CT: return "Connecticut"
        case .DE: return "Delaware"
        case .FL: return "Florida"
        case .GA: return "Georgia"
        case .HI: return "Hawaii"
        case .ID: return "Idaho"
        case .IL: return "Illinois"
        case .IN: return "Indiana"
        case .IA: return "Iowa"
        case .KS: return "Kansas"
        case .KY: return "Kentucky"
        case .LA: return "Louisiana"
        case .ME: return "Maine"
        case .MD: return "Maryland"
        case .MA: return "Massachusetts"
        case .MI: return "Michigan"
        case .MN: return "Minnesota"
        case .MS: return "Mississippi"
        case .MO: return "Missouri"
        case .MT: return "Montana"
        case .NE: return "Nebraska"
        case .NV: return "Nevada"
        case .NH: return "New Hampshire"
        case .NJ: return "New Jersey"
        case .NM: return "New Mexico"
        case .NY: return "New York"
        case .NC: return "North Carolina"
        case .ND: return "North Dakota"
        case .OH: return "Ohio"
        case .OK: return "Oklahoma"
        case .OR: return "Oregon"
        case .PA: return "Pennsylvania"
        case .RI: return "Rhode Island"
        case .SC: return "South Carolina"
        case .SD: return "South Dakota"
        case .TN: return "Tennessee"
        case .TX: return "Texas"
        case .UT: return "Utah"
        case .VT: return "Vermont"
        case .VA: return "Virginia"
        case .WA: return "Washington"
        case .WV: return "West Virginia"
        case .WI: return "Wisconsin"
        case .WY: return "Wyoming"
        case .DC: return "District of Columbia"
        }
    }

    var menuLabel: String { "\(rawValue) — \(displayName)" }
}

/// Admin review state for registration photo, policy number, and related docs.
enum VehicleDocumentApprovalStatus: String, Codable, Hashable, CaseIterable {
    /// Required documents not yet submitted.
    case incomplete
    /// Submitted — waiting on admin (registration photo + policy are high priority).
    case pendingReview
    case approved
    case rejected

    var customerLabel: String {
        switch self {
        case .incomplete: return "Documents incomplete"
        case .pendingReview: return "Pending admin approval"
        case .approved: return "Documents approved"
        case .rejected: return "Documents need revision"
        }
    }

    var systemImage: String {
        switch self {
        case .incomplete: return "doc.badge.ellipsis"
        case .pendingReview: return "hourglass"
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "exclamationmark.triangle.fill"
        }
    }
}

struct Vehicle: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let make: String
    let model: String
    let year: Int
    let licensePlate: String
    /// Two-letter US state / DC code for the plate (e.g. "CA").
    let licensePlateState: String
    /// Registration card / sticker expiration.
    var registrationExpirationDate: Date?
    let insurancePolicy: String
    /// Carrier name (e.g. GEICO, State Farm).
    var insuranceCompanyName: String
    /// Policy expiration date.
    var insurancePolicyExpirationDate: Date?
    let currentChargePercent: Int
    let estimatedRangeMiles: Int
    let registrationPhotoData: Data?
    /// Optional photo of the insurance card.
    var insuranceCardPhotoData: Data?
    let teslaVIN: String?
    let isTeslaLinked: Bool
    var paintColor: TeslaPaint = .pearlWhite
    /// True when anyone smokes or vapes inside this vehicle (shown to drivers on requests).
    var smokingInVehicle: Bool
    /// Admin approval for registration / insurance documents.
    var documentApprovalStatus: VehicleDocumentApprovalStatus
    var documentsSubmittedAt: Date?
    var documentsReviewedAt: Date?
    var documentRejectionReason: String?

    var displayName: String {
        "\(year) \(make) \(model)"
    }

    var hasRegistrationPhoto: Bool {
        !(registrationPhotoData?.isEmpty ?? true)
    }

    var hasPolicyNumber: Bool {
        !insurancePolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// High-priority items the admin must verify first.
    var highPriorityDocumentItems: [String] {
        var items: [String] = []
        if hasRegistrationPhoto { items.append("Registration photo") }
        if hasPolicyNumber { items.append("Policy number") }
        return items
    }

    /// Higher score = earlier in the admin queue. Registration photo + policy weigh heaviest.
    var adminReviewPriorityScore: Int {
        guard documentApprovalStatus == .pendingReview else { return 0 }
        var score = 100
        if hasRegistrationPhoto { score += 50 }
        if hasPolicyNumber { score += 50 }
        if !(insuranceCardPhotoData?.isEmpty ?? true) { score += 10 }
        if !insuranceCompanyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 5 }
        return score
    }

    var isDocumentsApprovedForBooking: Bool {
        documentApprovalStatus == .approved
    }

    /// Plate with state, e.g. "CA · 7XYZ123".
    var licensePlateDisplay: String {
        let plate = licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let state = licensePlateState.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if state.isEmpty { return plate.isEmpty ? "PENDING" : plate }
        if plate.isEmpty { return state }
        return "\(state) · \(plate)"
    }

    /// Title for home card — prefer Make + Model (e.g. "Tesla Model 3").
    var homeCardTitle: String {
        if let pretty = prettyTeslaTitle { return pretty }
        let makePart = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelPart = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !makePart.isEmpty, !modelPart.isEmpty {
            return "\(makePart) \(modelPart)"
        }
        return displayName
    }

    var isTesla: Bool {
        make.lowercased() == "tesla" || teslaModelCode != nil
    }

    private var prettyTeslaTitle: String? {
        guard let code = teslaModelCode else { return nil }
        switch code {
        case "m3": return "Tesla Model 3"
        case "my": return "Tesla Model Y"
        case "ms": return "Tesla Model S"
        case "mx": return "Tesla Model X"
        default: return nil
        }
    }

    var hasInsuranceCardPhoto: Bool {
        !(insuranceCardPhotoData?.isEmpty ?? true)
    }

    var meetsMinimumRange: Bool {
        estimatedRangeMiles >= Pricing.minimumRangeMiles
    }

    /// Tesla compositor model code for photoreal renders.
    var teslaModelCode: String? {
        let blob = "\(make) \(model) \(name)".lowercased()
        if blob.contains("model 3") || blob.contains("model3") { return "m3" }
        if blob.contains("model y") || blob.contains("modely") { return "my" }
        if blob.contains("model s") || blob.contains("models") { return "ms" }
        if blob.contains("model x") || blob.contains("modelx") { return "mx" }
        // Bare "3" / "Y" when make is Tesla.
        if make.lowercased() == "tesla" {
            switch model.lowercased().trimmingCharacters(in: .whitespaces) {
            case "3", "m3": return "m3"
            case "y", "my": return "my"
            case "s", "ms": return "ms"
            case "x", "mx": return "mx"
            default: break
            }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, name, make, model, year
        case licensePlate, licensePlateState
        case registrationExpirationDate
        case insurancePolicy, insuranceCompanyName, insurancePolicyExpirationDate
        case currentChargePercent, estimatedRangeMiles
        case registrationPhotoData, insuranceCardPhotoData
        case teslaVIN, isTeslaLinked, paintColor, smokingInVehicle
        case documentApprovalStatus, documentsSubmittedAt, documentsReviewedAt, documentRejectionReason
    }

    init(
        id: UUID,
        name: String,
        make: String,
        model: String,
        year: Int,
        licensePlate: String,
        licensePlateState: String = "",
        registrationExpirationDate: Date? = nil,
        insurancePolicy: String,
        insuranceCompanyName: String = "",
        insurancePolicyExpirationDate: Date? = nil,
        currentChargePercent: Int,
        estimatedRangeMiles: Int,
        registrationPhotoData: Data?,
        insuranceCardPhotoData: Data? = nil,
        teslaVIN: String?,
        isTeslaLinked: Bool,
        paintColor: TeslaPaint = .pearlWhite,
        smokingInVehicle: Bool = false,
        documentApprovalStatus: VehicleDocumentApprovalStatus = .incomplete,
        documentsSubmittedAt: Date? = nil,
        documentsReviewedAt: Date? = nil,
        documentRejectionReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.make = make
        self.model = model
        self.year = year
        self.licensePlate = licensePlate
        self.licensePlateState = licensePlateState
        self.registrationExpirationDate = registrationExpirationDate
        self.insurancePolicy = insurancePolicy
        self.insuranceCompanyName = insuranceCompanyName
        self.insurancePolicyExpirationDate = insurancePolicyExpirationDate
        self.currentChargePercent = currentChargePercent
        self.estimatedRangeMiles = estimatedRangeMiles
        self.registrationPhotoData = registrationPhotoData
        self.insuranceCardPhotoData = insuranceCardPhotoData
        self.teslaVIN = teslaVIN
        self.isTeslaLinked = isTeslaLinked
        self.paintColor = paintColor
        self.smokingInVehicle = smokingInVehicle
        self.documentApprovalStatus = documentApprovalStatus
        self.documentsSubmittedAt = documentsSubmittedAt
        self.documentsReviewedAt = documentsReviewedAt
        self.documentRejectionReason = documentRejectionReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        make = try c.decode(String.self, forKey: .make)
        model = try c.decode(String.self, forKey: .model)
        year = try c.decode(Int.self, forKey: .year)
        licensePlate = try c.decode(String.self, forKey: .licensePlate)
        licensePlateState = try c.decodeIfPresent(String.self, forKey: .licensePlateState) ?? ""
        registrationExpirationDate = try c.decodeIfPresent(Date.self, forKey: .registrationExpirationDate)
        insurancePolicy = try c.decode(String.self, forKey: .insurancePolicy)
        insuranceCompanyName = try c.decodeIfPresent(String.self, forKey: .insuranceCompanyName) ?? ""
        insurancePolicyExpirationDate = try c.decodeIfPresent(Date.self, forKey: .insurancePolicyExpirationDate)
        currentChargePercent = try c.decode(Int.self, forKey: .currentChargePercent)
        estimatedRangeMiles = try c.decode(Int.self, forKey: .estimatedRangeMiles)
        registrationPhotoData = try c.decodeIfPresent(Data.self, forKey: .registrationPhotoData)
        insuranceCardPhotoData = try c.decodeIfPresent(Data.self, forKey: .insuranceCardPhotoData)
        teslaVIN = try c.decodeIfPresent(String.self, forKey: .teslaVIN)
        isTeslaLinked = try c.decode(Bool.self, forKey: .isTeslaLinked)
        paintColor = try c.decodeIfPresent(TeslaPaint.self, forKey: .paintColor) ?? .pearlWhite
        smokingInVehicle = try c.decodeIfPresent(Bool.self, forKey: .smokingInVehicle) ?? false
        let hasPhoto = !(registrationPhotoData?.isEmpty ?? true)
        let hasPolicy = !insurancePolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        documentApprovalStatus = try c.decodeIfPresent(
            VehicleDocumentApprovalStatus.self,
            forKey: .documentApprovalStatus
        ) ?? (hasPhoto && hasPolicy ? .pendingReview : .incomplete)
        documentsSubmittedAt = try c.decodeIfPresent(Date.self, forKey: .documentsSubmittedAt)
            ?? (documentApprovalStatus == .pendingReview || documentApprovalStatus == .approved ? Date() : nil)
        documentsReviewedAt = try c.decodeIfPresent(Date.self, forKey: .documentsReviewedAt)
        documentRejectionReason = try c.decodeIfPresent(String.self, forKey: .documentRejectionReason)
    }
}

enum SampleVehicles {
    static let all: [Vehicle] = [
        Vehicle(
            id: UUID(uuidString: "A1111111-1111-1111-1111-111111111111")!,
            name: "Daily Driver",
            make: "Tesla",
            model: "Model 3",
            year: 2022,
            licensePlate: "7XYZ123",
            licensePlateState: "CA",
            registrationExpirationDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
            insurancePolicy: "GEICO-884421",
            insuranceCompanyName: "GEICO",
            insurancePolicyExpirationDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
            currentChargePercent: 28,
            estimatedRangeMiles: 72,
            registrationPhotoData: nil,
            insuranceCardPhotoData: nil,
            teslaVIN: nil,
            isTeslaLinked: false,
            paintColor: .pearlWhite
        ),
        Vehicle(
            id: UUID(uuidString: "A2222222-2222-2222-2222-222222222222")!,
            name: "Family SUV",
            make: "Tesla",
            model: "Model Y",
            year: 2024,
            licensePlate: "8ABC456",
            licensePlateState: "CA",
            registrationExpirationDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
            insurancePolicy: "STATEFARM-22910",
            insuranceCompanyName: "State Farm",
            insurancePolicyExpirationDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
            currentChargePercent: 4,
            estimatedRangeMiles: 8,
            registrationPhotoData: nil,
            insuranceCardPhotoData: nil,
            teslaVIN: nil,
            isTeslaLinked: false,
            paintColor: .deepBlue
        )
    ]
}
