//
//  VehicleCatalog.swift
//  Chercharge
//
//  Make → model options for Register Your Vehicle dropdowns.
//

import Foundation

enum VehicleCatalog {
    /// Sentinel for custom / not-listed entries.
    static let other = "Other"

    /// Popular makes first (EVs + common brands), alphabetical after.
    static let makes: [String] = [
        "Tesla",
        "Rivian",
        "Lucid",
        "BMW",
        "Mercedes-Benz",
        "Audi",
        "Porsche",
        "Ford",
        "Chevrolet",
        "Hyundai",
        "Kia",
        "Volkswagen",
        "Nissan",
        "Toyota",
        "Volvo",
        "Polestar",
        "Genesis",
        "Cadillac",
        "Jaguar",
        "Subaru",
        "Honda",
        "Lexus",
        other
    ]

    private static let modelsByMake: [String: [String]] = [
        "Tesla": ["Model 3", "Model Y", "Model S", "Model X", "Cybertruck"],
        "Rivian": ["R1T", "R1S", "R2", "R3"],
        "Lucid": ["Air", "Gravity"],
        "BMW": ["i4", "i5", "i7", "iX", "iX1", "iX3", "330e", "X5 xDrive50e"],
        "Mercedes-Benz": ["EQB", "EQE", "EQE SUV", "EQS", "EQS SUV", "GLC 350e"],
        "Audi": ["Q4 e-tron", "Q6 e-tron", "Q8 e-tron", "e-tron GT", "A6 e-tron"],
        "Porsche": ["Taycan", "Macan Electric"],
        "Ford": ["Mustang Mach-E", "F-150 Lightning", "E-Transit"],
        "Chevrolet": ["Equinox EV", "Blazer EV", "Silverado EV", "Bolt EUV"],
        "Hyundai": ["Ioniq 5", "Ioniq 6", "Ioniq 9", "Kona Electric"],
        "Kia": ["EV6", "EV9", "Niro EV"],
        "Volkswagen": ["ID.4", "ID.Buzz"],
        "Nissan": ["Leaf", "Ariya"],
        "Toyota": ["bZ4X", "Prius Prime", "RAV4 Prime"],
        "Volvo": ["EX30", "EX40", "EC40", "EX90", "XC40 Recharge"],
        "Polestar": ["Polestar 2", "Polestar 3", "Polestar 4"],
        "Genesis": ["Electrified G80", "Electrified GV70", "GV60"],
        "Cadillac": ["Lyriq", "Optiq", "Vistiq", "Escalade IQ"],
        "Jaguar": ["I-PACE"],
        "Subaru": ["Solterra"],
        "Honda": ["Prologue"],
        "Lexus": ["RZ", "UX 300e", "NX Plug-in Hybrid"]
    ]

    static func models(forMake make: String) -> [String] {
        let trimmed = make.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != other else { return [other] }
        var list = modelsByMake[trimmed] ?? []
        if !list.contains(other) {
            list.append(other)
        }
        return list
    }

    /// Map a free-form saved make into a catalog selection (+ optional custom).
    static func resolveMakeSelection(_ raw: String) -> (selection: String, custom: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", "") }
        if makes.contains(trimmed) { return (trimmed, "") }
        // Case-insensitive match
        if let match = makes.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return (match, "")
        }
        return (other, trimmed)
    }

    /// Map a free-form saved model into a catalog selection for a make (+ optional custom).
    static func resolveModelSelection(make: String, model raw: String) -> (selection: String, custom: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", "") }
        let options = models(forMake: make).filter { $0 != other }
        if options.contains(trimmed) { return (trimmed, "") }
        if let match = options.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return (match, "")
        }
        return (other, trimmed)
    }
}
