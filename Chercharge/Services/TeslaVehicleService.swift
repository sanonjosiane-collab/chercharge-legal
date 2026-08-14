//
//  TeslaVehicleService.swift
//  Chercharge
//
//  Tesla Fleet API vehicle list for live OAuth tokens.
//

import Foundation

enum TeslaVehicleServiceError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case decode

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Tesla Fleet API is not configured."
        case .http(let code, let body):
            return "Tesla Fleet API error (\(code)): \(body)"
        case .decode:
            return "Could not read vehicles from Tesla Fleet API."
        }
    }
}

enum TeslaVehicleService {
    /// Live Fleet API when `accessToken` is a real OAuth token.
    static func fetchLinkedVehicles(accessToken: String, audience: String) async throws -> [Vehicle] {
        if accessToken.hasPrefix("demo_") {
            throw TeslaVehicleServiceError.notConfigured
        }
        return try await fetchFromFleetAPI(accessToken: accessToken, audience: audience)
    }

    private static func fetchFromFleetAPI(accessToken: String, audience: String) async throws -> [Vehicle] {
        guard let base = URL(string: audience) else {
            throw TeslaVehicleServiceError.notConfigured
        }
        let listURL = base
            .appendingPathComponent("api")
            .appendingPathComponent("1")
            .appendingPathComponent("vehicles")

        var request = URLRequest(url: listURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TeslaVehicleServiceError.http(-1, "Invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TeslaVehicleServiceError.http(http.statusCode, body.prefix(200).description)
        }

        let decoded = try JSONDecoder().decode(TeslaVehiclesResponse.self, from: data)
        var vehicles: [Vehicle] = []
        for (index, item) in decoded.response.enumerated() {
            let detail = try? await fetchVehicleData(
                accessToken: accessToken,
                audience: audience,
                vehicleID: item.id
            )
            vehicles.append(mapVehicle(item, detail: detail, index: index))
        }
        return vehicles
    }

    private static func fetchVehicleData(
        accessToken: String,
        audience: String,
        vehicleID: Int64
    ) async throws -> TeslaVehicleDataResponse.Response? {
        guard let base = URL(string: audience) else { return nil }
        let url = base
            .appendingPathComponent("api")
            .appendingPathComponent("1")
            .appendingPathComponent("vehicles")
            .appendingPathComponent(String(vehicleID))
            .appendingPathComponent("vehicle_data")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder().decode(TeslaVehicleDataResponse.self, from: data).response
    }

    private static func mapVehicle(
        _ item: TeslaVehicleListItem,
        detail: TeslaVehicleDataResponse.Response?,
        index: Int
    ) -> Vehicle {
        let model = inferModel(from: item.vin ?? item.displayName ?? "")
        let year = inferYear(from: item.vin) ?? Calendar.current.component(.year, from: Date())
        let charge = detail?.chargeState?.batteryLevel ?? 50
        let range = Int(detail?.chargeState?.batteryRange ?? Double(max(80, charge * 2)))
        let name = item.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Tesla \(index + 1)"

        // Stable UUID from VIN or Tesla id so re-import replaces the same rows.
        let idSeed = item.vin ?? String(item.id)
        let id = uuidFromStableString(idSeed)

        return Vehicle(
            id: id,
            name: name,
            make: "Tesla",
            model: model,
            year: year,
            licensePlate: "TESLA",
            licensePlateState: "CA",
            insurancePolicy: "TESLA-FLEET",
            currentChargePercent: min(100, max(0, charge)),
            estimatedRangeMiles: max(0, range),
            registrationPhotoData: nil,
            teslaVIN: item.vin,
            isTeslaLinked: true,
            paintColor: .pearlWhite
        )
    }

    private static func inferModel(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("model y") || lower.contains("my") { return "Model Y" }
        if lower.contains("model x") || lower.contains("mx") { return "Model X" }
        if lower.contains("model s") || lower.contains("ms") { return "Model S" }
        if lower.contains("cybertruck") { return "Cybertruck" }
        // VIN position 4 often encodes model for Teslas; fall back to Model 3.
        if let vin = Optional(text), vin.count >= 4 {
            switch vin.uppercased()[vin.index(vin.startIndex, offsetBy: 3)] {
            case "Y": return "Model Y"
            case "X": return "Model X"
            case "S": return "Model S"
            default: break
            }
        }
        return "Model 3"
    }

    private static func inferYear(from vin: String?) -> Int? {
        guard let vin, vin.count >= 10 else { return nil }
        // Rough model-year from VIN position 10 — best-effort only.
        let code = vin.uppercased()[vin.index(vin.startIndex, offsetBy: 9)]
        let map: [Character: Int] = [
            "L": 2020, "M": 2021, "N": 2022, "P": 2023, "R": 2024, "S": 2025, "T": 2026,
        ]
        return map[code]
    }

    private static func uuidFromStableString(_ value: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(value)
        let hash = hasher.finalize()
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: hash) { buffer in
            for i in 0..<min(8, buffer.count) {
                bytes[i] = buffer[i]
            }
        }
        // Mix in a second pass for more bits.
        var hasher2 = Hasher()
        hasher2.combine(value)
        hasher2.combine("chercharge.tesla")
        let hash2 = hasher2.finalize()
        withUnsafeBytes(of: hash2) { buffer in
            for i in 0..<min(8, buffer.count) {
                bytes[8 + i] = buffer[i]
            }
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// MARK: - Fleet API DTOs

private struct TeslaVehiclesResponse: Decodable {
    let response: [TeslaVehicleListItem]
    let count: Int?
}

private struct TeslaVehicleListItem: Decodable {
    let id: Int64
    let vehicleID: Int64?
    let vin: String?
    let displayName: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case id
        case vehicleID = "vehicle_id"
        case vin
        case displayName = "display_name"
        case state
    }
}

private struct TeslaVehicleDataResponse: Decodable {
    struct Response: Decodable {
        let chargeState: ChargeState?

        enum CodingKeys: String, CodingKey {
            case chargeState = "charge_state"
        }
    }

    struct ChargeState: Decodable {
        let batteryLevel: Int?
        let batteryRange: Double?

        enum CodingKeys: String, CodingKey {
            case batteryLevel = "battery_level"
            case batteryRange = "battery_range"
        }
    }

    let response: Response?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
