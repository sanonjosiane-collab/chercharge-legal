//
//  InspectionStorageService.swift
//  Chercharge
//

import Foundation
import Supabase

/// Uploads inspection media to Supabase Storage when configured.
/// Always keeps local bytes on the booking record; URLs are added when upload succeeds.
@MainActor
final class InspectionStorageService {
    static let shared = InspectionStorageService()
    private let bucket = "inspections"

    func uploadMedia(for inspection: VehicleInspection) async -> InspectionMediaURLs {
        guard SupabaseConfig.isConfigured else {
            return localPlaceholderURLs(for: inspection)
        }

        do {
            try SupabaseConfig.validate()
            let client = SupabaseClientProvider.shared
            let base = "\(inspection.jobID.uuidString)/\(inspection.phase.rawValue)/\(inspection.id.uuidString)"

            async let front = upload(client, path: "\(base)/front.jpg", data: inspection.frontPhotoData, contentType: "image/jpeg")
            async let rear = upload(client, path: "\(base)/rear.jpg", data: inspection.rearPhotoData, contentType: "image/jpeg")
            async let left = upload(client, path: "\(base)/left.jpg", data: inspection.leftSidePhotoData, contentType: "image/jpeg")
            async let roof = upload(client, path: "\(base)/roof.jpg", data: inspection.roofPhotoData, contentType: "image/jpeg")
            async let video = upload(client, path: "\(base)/interior.mp4", data: inspection.interiorVideoData, contentType: "video/mp4")
            async let odo = upload(client, path: "\(base)/odometer.jpg", data: inspection.odometerPhotoData, contentType: "image/jpeg")

            return try await InspectionMediaURLs(
                frontPhotoURL: front,
                rearPhotoURL: rear,
                leftSidePhotoURL: left,
                roofPhotoURL: roof,
                interiorVideoURL: video,
                odometerPhotoURL: odo
            )
        } catch {
            return localPlaceholderURLs(for: inspection)
        }
    }

    private func upload(
        _ client: SupabaseClient,
        path: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        try await client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: contentType, upsert: true)
            )
        return try client.storage.from(bucket).getPublicURL(path: path).absoluteString
    }

    private func localPlaceholderURLs(for inspection: VehicleInspection) -> InspectionMediaURLs {
        let base = "local://inspections/\(inspection.jobID.uuidString)/\(inspection.phase.rawValue)"
        return InspectionMediaURLs(
            frontPhotoURL: "\(base)/front.jpg",
            rearPhotoURL: "\(base)/rear.jpg",
            leftSidePhotoURL: "\(base)/left.jpg",
            roofPhotoURL: "\(base)/roof.jpg",
            interiorVideoURL: "\(base)/interior.mp4",
            odometerPhotoURL: "\(base)/odometer.jpg"
        )
    }
}
