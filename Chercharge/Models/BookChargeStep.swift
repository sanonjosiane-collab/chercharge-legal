//
//  BookChargeStep.swift
//  Chercharge
//

import Foundation

enum BookChargeStep: Int, CaseIterable, Hashable {
    case schedule = 1
    case vehicle = 2
    case pickup = 3
    case dropoff = 4
    case payment = 5
    case review = 6

    var title: String {
        switch self {
        case .schedule: return "Schedule"
        case .vehicle: return "Vehicle"
        case .pickup: return "Pickup"
        case .dropoff: return "Return"
        case .payment: return "Payment"
        case .review: return "Review"
        }
    }

    var next: BookChargeStep? {
        BookChargeStep(rawValue: rawValue + 1)
    }

    var previous: BookChargeStep? {
        BookChargeStep(rawValue: rawValue - 1)
    }
}
