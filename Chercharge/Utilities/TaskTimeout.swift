//
//  TaskTimeout.swift
//  Chercharge
//

import Foundation

enum TaskTimeoutError: Error {
    case timedOut
}

enum TaskTimeout {
    /// Runs `operation`, or throws `TaskTimeoutError.timedOut` if it exceeds `seconds`.
    static func run<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TaskTimeoutError.timedOut
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }
}
