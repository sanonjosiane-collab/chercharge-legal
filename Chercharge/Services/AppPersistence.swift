//
//  AppPersistence.swift
//  Chercharge
//

import Foundation

/// Codable snapshot of all customer-facing app state that should survive relaunch.
struct PersistedAppState: Codable {
    var profileName: String
    var profileEmail: String
    var profilePhone: String
    var vehicles: [Vehicle]
    var savedAddresses: [LocationPin]
    var activeJob: ChargeJob?
    var lastCompletedJob: ChargeJob?
    var pastJobs: [ChargeJob]
    var upcomingJobs: [ChargeJob]
    var paymentMethods: [SavedPaymentMethod]
    var membership: MembershipState
    var preorder: PreorderState?
    var settings: AppSettings
    var supportTickets: [SupportTicket]
    var teslaConnected: Bool
    var teslaEmail: String?
    var hasCompletedOnboarding: Bool
}

enum AppPersistence {
    private static let fileName = "chercharge-app-state.json"
    /// Serial queue so encode+write never blocks the main thread (photos make this heavy).
    private static let ioQueue = DispatchQueue(label: "com.chercharge.app-persistence", qos: .utility)

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// Cheap existence check — never decode JSON just to see if a file is present.
    static var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func load() -> PersistedAppState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return decode(data)
    }

    /// Background decode so launch / account restore does not block the main thread.
    static func loadAsync() async -> PersistedAppState? {
        let url = fileURL
        return await withCheckedContinuation { continuation in
            ioQueue.async {
                guard let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: decode(data))
            }
        }
    }

    private static func decode(_ data: Data) -> PersistedAppState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedAppState.self, from: data)
    }

    static func save(_ state: PersistedAppState) {
        let url = fileURL
        ioQueue.async {
            let encoder = JSONEncoder()
            // Compact JSON — prettyPrinted + sortedKeys with embedded photos freezes the UI.
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(state) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    static func clear() {
        // Never sync onto the encode queue from the main thread — a large in-flight
        // save would freeze the UI until encode finished.
        let url = fileURL
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func makeDefault() -> PersistedAppState {
        PersistedAppState(
            profileName: "",
            profileEmail: "",
            profilePhone: "",
            vehicles: [],
            savedAddresses: [],
            activeJob: nil,
            lastCompletedJob: nil,
            pastJobs: [],
            upcomingJobs: [],
            paymentMethods: [],
            membership: .standard,
            preorder: PreorderState(),
            settings: .default,
            supportTickets: [],
            teslaConnected: false,
            teslaEmail: nil,
            hasCompletedOnboarding: false
        )
    }
}

// MARK: - Cloud sync (strip heavy media — Firestore ~1MB doc / ~10MB request limits)

extension PersistedAppState {
    /// Photos/videos stay on-device (and Supabase Storage). Cloud sync keeps metadata + Storage URLs only.
    func strippingBinaryMediaForCloudSync() -> PersistedAppState {
        var copy = self
        copy.vehicles = vehicles.map { $0.strippingRegistrationPhoto() }
        copy.activeJob = activeJob?.strippingBinaryMedia()
        copy.lastCompletedJob = lastCompletedJob?.strippingBinaryMedia()
        copy.pastJobs = pastJobs.map { $0.strippingBinaryMedia() }
        copy.upcomingJobs = upcomingJobs.map { $0.strippingBinaryMedia() }
        return copy
    }

    /// After a cloud pull, restore any local binary media that the stripped payload omitted.
    func rehydratingBinaryMedia(from local: PersistedAppState) -> PersistedAppState {
        var copy = self
        let localVehicles = Dictionary(uniqueKeysWithValues: local.vehicles.map { ($0.id, $0) })
        copy.vehicles = vehicles.map { remote in
            guard let localVehicle = localVehicles[remote.id] else { return remote }
            var merged = remote
            if let photo = localVehicle.registrationPhotoData, !photo.isEmpty,
               remote.registrationPhotoData == nil || remote.registrationPhotoData?.isEmpty == true {
                merged = merged.replacingDocumentPhotos(
                    registrationPhotoData: photo,
                    insuranceCardPhotoData: merged.insuranceCardPhotoData
                )
            }
            if let card = localVehicle.insuranceCardPhotoData, !card.isEmpty,
               remote.insuranceCardPhotoData == nil || remote.insuranceCardPhotoData?.isEmpty == true {
                merged = merged.replacingDocumentPhotos(
                    registrationPhotoData: merged.registrationPhotoData,
                    insuranceCardPhotoData: card
                )
            }
            return merged
        }
        copy.activeJob = activeJob?.rehydratingBinaryMedia(from: local.activeJob)
            ?? activeJob
        copy.lastCompletedJob = lastCompletedJob?.rehydratingBinaryMedia(from: local.lastCompletedJob)
            ?? lastCompletedJob
        let localPast = Dictionary(uniqueKeysWithValues: local.pastJobs.map { ($0.id, $0) })
        copy.pastJobs = pastJobs.map { $0.rehydratingBinaryMedia(from: localPast[$0.id]) }
        let localUpcoming = Dictionary(uniqueKeysWithValues: local.upcomingJobs.map { ($0.id, $0) })
        copy.upcomingJobs = upcomingJobs.map { $0.rehydratingBinaryMedia(from: localUpcoming[$0.id]) }
        return copy
    }
}

extension Vehicle {
    func strippingRegistrationPhoto() -> Vehicle {
        replacingDocumentPhotos(registrationPhotoData: nil, insuranceCardPhotoData: nil)
    }

    func replacingRegistrationPhoto(_ data: Data?) -> Vehicle {
        replacingDocumentPhotos(
            registrationPhotoData: data,
            insuranceCardPhotoData: insuranceCardPhotoData
        )
    }

    func replacingDocumentPhotos(
        registrationPhotoData: Data?,
        insuranceCardPhotoData: Data?
    ) -> Vehicle {
        Vehicle(
            id: id,
            name: name,
            make: make,
            model: model,
            year: year,
            licensePlate: licensePlate,
            licensePlateState: licensePlateState,
            registrationExpirationDate: registrationExpirationDate,
            insurancePolicy: insurancePolicy,
            insuranceCompanyName: insuranceCompanyName,
            insurancePolicyExpirationDate: insurancePolicyExpirationDate,
            currentChargePercent: currentChargePercent,
            estimatedRangeMiles: estimatedRangeMiles,
            registrationPhotoData: registrationPhotoData,
            insuranceCardPhotoData: insuranceCardPhotoData,
            teslaVIN: teslaVIN,
            isTeslaLinked: isTeslaLinked,
            paintColor: paintColor,
            smokingInVehicle: smokingInVehicle,
            documentApprovalStatus: documentApprovalStatus,
            documentsSubmittedAt: documentsSubmittedAt,
            documentsReviewedAt: documentsReviewedAt,
            documentRejectionReason: documentRejectionReason
        )
    }
}

extension VehicleInspection {
    func strippingBinaryMedia() -> VehicleInspection {
        var copy = self
        copy.frontPhotoData = Data()
        copy.rearPhotoData = Data()
        copy.leftSidePhotoData = Data()
        copy.roofPhotoData = Data()
        copy.interiorVideoData = Data()
        copy.odometerPhotoData = Data()
        return copy
    }

    func rehydratingBinaryMedia(from local: VehicleInspection?) -> VehicleInspection {
        guard let local, local.id == id else { return self }
        var copy = self
        if copy.frontPhotoData.isEmpty { copy.frontPhotoData = local.frontPhotoData }
        if copy.rearPhotoData.isEmpty { copy.rearPhotoData = local.rearPhotoData }
        if copy.leftSidePhotoData.isEmpty { copy.leftSidePhotoData = local.leftSidePhotoData }
        if copy.roofPhotoData.isEmpty { copy.roofPhotoData = local.roofPhotoData }
        if copy.interiorVideoData.isEmpty { copy.interiorVideoData = local.interiorVideoData }
        if copy.odometerPhotoData.isEmpty { copy.odometerPhotoData = local.odometerPhotoData }
        return copy
    }
}

extension ChargeJob {
    func strippingBinaryMedia() -> ChargeJob {
        ChargeJob(
            id: id,
            vehicle: vehicle.strippingRegistrationPhoto(),
            pickup: pickup,
            station: station,
            dropoff: dropoff,
            targetChargePercent: targetChargePercent,
            startingChargePercent: startingChargePercent,
            status: status,
            estimatedPrice: estimatedPrice,
            estimatedMinutes: estimatedMinutes,
            createdAt: createdAt,
            preTripInspection: preTripInspection?.strippingBinaryMedia(),
            postTripInspection: postTripInspection?.strippingBinaryMedia(),
            customerApprovedPickupAt: customerApprovedPickupAt,
            customerApprovedReturnAt: customerApprovedReturnAt,
            inspectionApprovalDeadline: inspectionApprovalDeadline,
            returnApprovalDeadline: returnApprovalDeadline,
            issueReports: issueReports,
            paymentIntentID: paymentIntentID,
            paymentMethodLabel: paymentMethodLabel,
            receiptNumber: receiptNumber,
            completedAt: completedAt,
            scheduledFor: scheduledFor,
            tipAmount: tipAmount,
            driverRating: driverRating,
            feedbackSubmittedAt: feedbackSubmittedAt,
            isCloudDispatched: isCloudDispatched
        )
    }

    func rehydratingBinaryMedia(from local: ChargeJob?) -> ChargeJob {
        guard let local, local.id == id else { return self }
        return ChargeJob(
            id: id,
            vehicle: {
                var v = vehicle
                if let photo = local.vehicle.registrationPhotoData, !photo.isEmpty,
                   vehicle.registrationPhotoData == nil || vehicle.registrationPhotoData?.isEmpty == true {
                    v = v.replacingDocumentPhotos(
                        registrationPhotoData: photo,
                        insuranceCardPhotoData: v.insuranceCardPhotoData
                    )
                }
                if let card = local.vehicle.insuranceCardPhotoData, !card.isEmpty,
                   vehicle.insuranceCardPhotoData == nil || vehicle.insuranceCardPhotoData?.isEmpty == true {
                    v = v.replacingDocumentPhotos(
                        registrationPhotoData: v.registrationPhotoData,
                        insuranceCardPhotoData: card
                    )
                }
                return v
            }(),
            pickup: pickup,
            station: station,
            dropoff: dropoff,
            targetChargePercent: targetChargePercent,
            startingChargePercent: startingChargePercent,
            status: status,
            estimatedPrice: estimatedPrice,
            estimatedMinutes: estimatedMinutes,
            createdAt: createdAt,
            preTripInspection: preTripInspection?.rehydratingBinaryMedia(from: local.preTripInspection)
                ?? preTripInspection,
            postTripInspection: postTripInspection?.rehydratingBinaryMedia(from: local.postTripInspection)
                ?? postTripInspection,
            customerApprovedPickupAt: customerApprovedPickupAt,
            customerApprovedReturnAt: customerApprovedReturnAt,
            inspectionApprovalDeadline: inspectionApprovalDeadline,
            returnApprovalDeadline: returnApprovalDeadline,
            issueReports: issueReports,
            paymentIntentID: paymentIntentID,
            paymentMethodLabel: paymentMethodLabel,
            receiptNumber: receiptNumber,
            completedAt: completedAt,
            scheduledFor: scheduledFor,
            tipAmount: tipAmount,
            driverRating: driverRating,
            feedbackSubmittedAt: feedbackSubmittedAt,
            isCloudDispatched: isCloudDispatched || local.isCloudDispatched
        )
    }
}
