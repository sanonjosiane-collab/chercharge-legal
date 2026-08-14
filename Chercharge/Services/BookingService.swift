//
//  BookingService.swift
//  Chercharge
//

import Foundation
import Supabase

@MainActor
final class BookingService {
    private let client = SupabaseClientProvider.shared
    private var statusChannel: RealtimeChannelV2?

    func fetchVehicles(for userID: UUID) async throws -> [Vehicle] {
        let rows: [VehicleDTO] = try await client
            .from("vehicles")
            .select()
            .eq("owner_id", value: userID.uuidString)
            .order("created_at")
            .execute()
            .value
        return rows.map(\.asVehicle)
    }

    func fetchActiveBooking(for userID: UUID) async throws -> BookingDTO? {
        let rows: [BookingDTO] = try await client
            .from("bookings")
            .select()
            .eq("customer_id", value: userID.uuidString)
            .neq("status", value: JobStatus.delivered.rawValue)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func fetchBooking(id: UUID) async throws -> BookingDTO {
        try await client
            .from("bookings")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func createBooking(
        customerID: UUID,
        vehicle: Vehicle,
        pickup: LocationPin,
        station: LocationPin,
        targetChargePercent: Int,
        customerName: String? = nil
    ) async throws -> BookingDTO {
        // Prefer CustomerBookingDispatchService for Firebase/local users.
        // This path is for authenticated Supabase customers only.
        let row = VehicleUpsert(vehicle: vehicle, ownerID: customerID)
        try await client
            .from("vehicles")
            .upsert(row, onConflict: "id")
            .execute()

        let quote = Pricing.quote(from: vehicle.currentChargePercent, to: targetChargePercent)
        let insert = BookingInsert(
            customerId: customerID,
            vehicleId: vehicle.id,
            status: .requested,
            pickupName: pickup.name,
            pickupAddress: pickup.address,
            pickupLat: pickup.latitude,
            pickupLng: pickup.longitude,
            stationName: station.name,
            stationAddress: station.address,
            stationLat: station.latitude,
            stationLng: station.longitude,
            targetChargePercent: targetChargePercent,
            startingChargePercent: vehicle.currentChargePercent,
            estimatedPrice: quote.price,
            estimatedMinutes: quote.estimatedMinutes,
            customerName: customerName,
            vehicleName: vehicle.displayName,
            vehicleMake: vehicle.make,
            vehicleModel: vehicle.model,
            vehicleYear: vehicle.year,
            vehiclePlate: vehicle.licensePlateDisplay
        )

        // Stay in `requested` until a driver claims — do not auto-advance.
        return try await client
            .from("bookings")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value
    }

    func triggerStatusProgression(bookingID: UUID) async throws {
        try await client.functions.invoke(
            "advance-booking",
            options: FunctionInvokeOptions(
                body: ["booking_id": bookingID.uuidString]
            )
        )
    }

    /// Demo fallback when the Edge Function is not deployed yet.
    /// Advances status via RLS-allowed updates so Realtime still fires.
    func advanceStatusLocally(bookingID: UUID, to status: JobStatus) async throws {
        try await client
            .from("bookings")
            .update(["status": status.rawValue])
            .eq("id", value: bookingID.uuidString)
            .execute()
    }

    func subscribeToBooking(
        id: UUID,
        onChange: @escaping @MainActor (BookingDTO) -> Void
    ) async {
        await unsubscribe()

        let channel = client.channel("booking-\(id.uuidString)")
        statusChannel = channel

        let updates = await channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "bookings",
            filter: "id=eq.\(id.uuidString)"
        )

        await channel.subscribe()

        Task { @MainActor in
            for await _ in updates {
                if let booking = try? await fetchBooking(id: id) {
                    onChange(booking)
                }
            }
        }
    }

    func unsubscribe() async {
        if let statusChannel {
            await client.removeChannel(statusChannel)
            self.statusChannel = nil
        }
    }
}
