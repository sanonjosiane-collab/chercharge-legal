//
//  BookingDTO.swift
//  Chercharge
//

import Foundation

struct ProfileDTO: Codable, Hashable {
    let id: UUID
    let fullName: String?
    let role: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case role
    }
}

struct VehicleDTO: Codable, Hashable, Identifiable {
    let id: UUID
    let ownerId: UUID
    let name: String
    let make: String
    let model: String
    let licensePlate: String
    let currentChargePercent: Int

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case make
        case model
        case licensePlate = "license_plate"
        case currentChargePercent = "current_charge_percent"
    }

    var asVehicle: Vehicle {
        Vehicle(
            id: id,
            name: name,
            make: make,
            model: model,
            year: 2024,
            licensePlate: licensePlate,
            licensePlateState: "",
            insurancePolicy: "On file",
            currentChargePercent: currentChargePercent,
            estimatedRangeMiles: Pricing.estimatedMiles(fromChargePercent: currentChargePercent),
            registrationPhotoData: nil,
            teslaVIN: nil,
            isTeslaLinked: false
        )
    }
}

struct BookingDTO: Codable, Hashable, Identifiable {
    let id: UUID
    let customerId: UUID
    let vehicleId: UUID
    var status: JobStatus
    let pickupName: String
    let pickupAddress: String
    let pickupLat: Double
    let pickupLng: Double
    let stationName: String
    let stationAddress: String
    let stationLat: Double
    let stationLng: Double
    let targetChargePercent: Int
    let startingChargePercent: Int
    let estimatedPrice: Decimal
    let estimatedMinutes: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case vehicleId = "vehicle_id"
        case status
        case pickupName = "pickup_name"
        case pickupAddress = "pickup_address"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case stationName = "station_name"
        case stationAddress = "station_address"
        case stationLat = "station_lat"
        case stationLng = "station_lng"
        case targetChargePercent = "target_charge_percent"
        case startingChargePercent = "starting_charge_percent"
        case estimatedPrice = "estimated_price"
        case estimatedMinutes = "estimated_minutes"
        case createdAt = "created_at"
    }

    func asChargeJob(vehicle: Vehicle) -> ChargeJob {
        ChargeJob(
            id: id,
            vehicle: vehicle,
            pickup: LocationPin(
                id: UUID(),
                name: pickupName,
                address: pickupAddress,
                latitude: pickupLat,
                longitude: pickupLng
            ),
            station: LocationPin(
                id: UUID(),
                name: stationName,
                address: stationAddress,
                latitude: stationLat,
                longitude: stationLng
            ),
            targetChargePercent: targetChargePercent,
            startingChargePercent: startingChargePercent,
            status: status,
            estimatedPrice: estimatedPrice,
            estimatedMinutes: estimatedMinutes,
            createdAt: createdAt
        )
    }
}

struct VehicleUpsert: Encodable {
    let id: UUID
    let ownerId: UUID
    let name: String
    let make: String
    let model: String
    let licensePlate: String
    let currentChargePercent: Int

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case make
        case model
        case licensePlate = "license_plate"
        case currentChargePercent = "current_charge_percent"
    }

    init(vehicle: Vehicle, ownerID: UUID) {
        id = vehicle.id
        ownerId = ownerID
        name = vehicle.name
        make = vehicle.make
        model = vehicle.model
        licensePlate = vehicle.licensePlate
        currentChargePercent = vehicle.currentChargePercent
    }
}

struct BookingInsert: Encodable {
    let customerId: UUID
    let vehicleId: UUID
    let status: JobStatus
    let pickupName: String
    let pickupAddress: String
    let pickupLat: Double
    let pickupLng: Double
    let stationName: String
    let stationAddress: String
    let stationLat: Double
    let stationLng: Double
    let targetChargePercent: Int
    let startingChargePercent: Int
    let estimatedPrice: Decimal
    let estimatedMinutes: Int
    let customerName: String?
    let vehicleName: String
    let vehicleMake: String
    let vehicleModel: String
    let vehicleYear: Int
    let vehiclePlate: String

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case vehicleId = "vehicle_id"
        case status
        case pickupName = "pickup_name"
        case pickupAddress = "pickup_address"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case stationName = "station_name"
        case stationAddress = "station_address"
        case stationLat = "station_lat"
        case stationLng = "station_lng"
        case targetChargePercent = "target_charge_percent"
        case startingChargePercent = "starting_charge_percent"
        case estimatedPrice = "estimated_price"
        case estimatedMinutes = "estimated_minutes"
        case customerName = "customer_name"
        case vehicleName = "vehicle_name"
        case vehicleMake = "vehicle_make"
        case vehicleModel = "vehicle_model"
        case vehicleYear = "vehicle_year"
        case vehiclePlate = "vehicle_plate"
    }
}
