//
//  AppRoute.swift
//  Chercharge
//

import Foundation

enum AppRoute: Hashable {
    case book
    case preOrder
    case tracking(jobID: UUID)
    /// Customer review of driver-submitted media (not the capture flow).
    case reviewInspection(jobID: UUID, phase: InspectionPhase)
    case compareInspections(jobID: UUID)
    case complete(jobID: UUID)
    /// Admin home — document approval queue.
    case adminHome
}
