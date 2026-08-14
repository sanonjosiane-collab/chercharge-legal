//
//  CloudInspectionPayload.swift
//  Chercharge
//
//  URL-only inspection snapshot from bookings.pre_trip_inspection / post_trip_inspection.
//  Matches the driver app payload shape (front/back/left/right/top) and maps into the
//  customer VehicleInspection model (front/rear/left/roof).
//

import Foundation

struct CloudInspectionMediaURLs: Codable, Hashable {
    var frontPhotoURL: String?
    var backPhotoURL: String?
    var leftSidePhotoURL: String?
    var rightSidePhotoURL: String?
    var topPhotoURL: String?
    var interiorVideoURL: String?

    /// Driver may also emit legacy customer-style keys.
    var rearPhotoURL: String? {
        get { backPhotoURL }
        set { backPhotoURL = newValue }
    }

    var roofPhotoURL: String? {
        get { topPhotoURL }
        set { topPhotoURL = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case frontPhotoURL, backPhotoURL, leftSidePhotoURL, rightSidePhotoURL
        case topPhotoURL, interiorVideoURL
        case rearPhotoURL, roofPhotoURL
    }

    init(
        frontPhotoURL: String? = nil,
        backPhotoURL: String? = nil,
        leftSidePhotoURL: String? = nil,
        rightSidePhotoURL: String? = nil,
        topPhotoURL: String? = nil,
        interiorVideoURL: String? = nil
    ) {
        self.frontPhotoURL = frontPhotoURL
        self.backPhotoURL = backPhotoURL
        self.leftSidePhotoURL = leftSidePhotoURL
        self.rightSidePhotoURL = rightSidePhotoURL
        self.topPhotoURL = topPhotoURL
        self.interiorVideoURL = interiorVideoURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frontPhotoURL = try c.decodeIfPresent(String.self, forKey: .frontPhotoURL)
        backPhotoURL = try c.decodeIfPresent(String.self, forKey: .backPhotoURL)
            ?? c.decodeIfPresent(String.self, forKey: .rearPhotoURL)
        leftSidePhotoURL = try c.decodeIfPresent(String.self, forKey: .leftSidePhotoURL)
        rightSidePhotoURL = try c.decodeIfPresent(String.self, forKey: .rightSidePhotoURL)
        topPhotoURL = try c.decodeIfPresent(String.self, forKey: .topPhotoURL)
            ?? c.decodeIfPresent(String.self, forKey: .roofPhotoURL)
        interiorVideoURL = try c.decodeIfPresent(String.self, forKey: .interiorVideoURL)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(frontPhotoURL, forKey: .frontPhotoURL)
        try c.encodeIfPresent(backPhotoURL, forKey: .backPhotoURL)
        try c.encodeIfPresent(leftSidePhotoURL, forKey: .leftSidePhotoURL)
        try c.encodeIfPresent(rightSidePhotoURL, forKey: .rightSidePhotoURL)
        try c.encodeIfPresent(topPhotoURL, forKey: .topPhotoURL)
        try c.encodeIfPresent(interiorVideoURL, forKey: .interiorVideoURL)
    }
}

struct CloudInspectionPayload: Codable, Hashable {
    let id: UUID
    let jobID: UUID
    let phase: InspectionPhase
    let driverName: String
    let batteryPercent: Int
    let odometerMiles: Int
    let damageChecklist: DamageChecklist
    let tireCondition: TireCondition
    let capturedAt: Date
    let latitude: Double
    let longitude: Double
    let storageURLs: CloudInspectionMediaURLs
    let uploadedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, jobID, phase, driverName
        case batteryPercent, odometerMiles, damageChecklist, tireCondition
        case capturedAt, latitude, longitude, storageURLs, uploadedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeUUID(c, forKey: .id)
        jobID = try Self.decodeUUID(c, forKey: .jobID)
        phase = try c.decode(InspectionPhase.self, forKey: .phase)
        driverName = try c.decodeIfPresent(String.self, forKey: .driverName) ?? "Concierge"
        batteryPercent = try c.decodeIfPresent(Int.self, forKey: .batteryPercent) ?? 0
        odometerMiles = try c.decodeIfPresent(Int.self, forKey: .odometerMiles) ?? 0
        damageChecklist = try c.decodeIfPresent(DamageChecklist.self, forKey: .damageChecklist)
            ?? DamageChecklist()
        tireCondition = try c.decodeIfPresent(TireCondition.self, forKey: .tireCondition) ?? .good
        capturedAt = try Self.decodeDate(c, forKey: .capturedAt) ?? Date()
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        storageURLs = try c.decodeIfPresent(CloudInspectionMediaURLs.self, forKey: .storageURLs)
            ?? CloudInspectionMediaURLs()
        uploadedAt = try Self.decodeDate(c, forKey: .uploadedAt)
    }

    private static func decodeUUID(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> UUID {
        if let id = try c.decodeIfPresent(UUID.self, forKey: key) {
            return id
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: key),
           let id = UUID(uuidString: raw) {
            return id
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: c,
            debugDescription: "Expected UUID for \(key.stringValue)"
        )
    }

    private static func decodeDate(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        // Parse strings first. Driver payloads often omit timezone (`…T02:18:13.726`);
        // asking JSONDecoder for Date.self throws via dateDecodingStrategy and aborts
        // the entire status poll — leaving the customer stuck on driverArrived.
        if let raw = try c.decodeIfPresent(String.self, forKey: key) {
            if let date = parseFlexibleDate(raw) { return date }
        }
        if let seconds = try c.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private static func parseFlexibleDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

extension VehicleInspection {
    /// Build a customer-side inspection from the driver cloud JSONB payload.
    static func fromCloudPayload(_ payload: CloudInspectionPayload) -> VehicleInspection {
        VehicleInspection(
            id: payload.id,
            jobID: payload.jobID,
            phase: payload.phase,
            driverName: payload.driverName,
            frontPhotoData: Data(),
            rearPhotoData: Data(),
            leftSidePhotoData: Data(),
            roofPhotoData: Data(),
            interiorVideoData: Data(),
            odometerPhotoData: Data(),
            batteryPercent: payload.batteryPercent,
            damageChecklist: payload.damageChecklist,
            tireCondition: payload.tireCondition,
            capturedAt: payload.capturedAt,
            latitude: payload.latitude,
            longitude: payload.longitude,
            storageURLs: InspectionMediaURLs(
                frontPhotoURL: payload.storageURLs.frontPhotoURL,
                rearPhotoURL: payload.storageURLs.backPhotoURL
                    ?? payload.storageURLs.rearPhotoURL,
                leftSidePhotoURL: payload.storageURLs.leftSidePhotoURL,
                roofPhotoURL: payload.storageURLs.topPhotoURL
                    ?? payload.storageURLs.roofPhotoURL,
                interiorVideoURL: payload.storageURLs.interiorVideoURL,
                // Driver captures odometer as miles, not a dedicated photo.
                odometerPhotoURL: nil
            ),
            uploadedAt: payload.uploadedAt
        )
    }

    var hasRemoteMedia: Bool {
        let u = storageURLs
        return (u.frontPhotoURL?.isEmpty == false)
            || (u.rearPhotoURL?.isEmpty == false)
            || (u.leftSidePhotoURL?.isEmpty == false)
            || (u.roofPhotoURL?.isEmpty == false)
            || (u.interiorVideoURL?.isEmpty == false)
            || (u.odometerPhotoURL?.isEmpty == false)
    }
}
