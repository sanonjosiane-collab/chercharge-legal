//
//  CustomerNotificationInbox.swift
//  Chercharge
//
//  Home bell inbox for customer-facing notices (admin document decisions).
//

import Foundation
import Observation

@Observable
@MainActor
final class CustomerNotificationInbox {
    private static let fileName = "chercharge-customer-notifications.json"
    private static let maxItems = 50

    private(set) var items: [CustomerAppNotification] = []

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    var hasUnread: Bool { unreadCount > 0 }

    init() {
        load()
    }

    func post(_ notification: CustomerAppNotification) {
        // Avoid duplicate decision spam for the same vehicle + kind within a short window.
        if let existing = items.first(where: {
            $0.vehicleID == notification.vehicleID
                && $0.kind == notification.kind
                && abs($0.createdAt.timeIntervalSince(notification.createdAt)) < 5
        }) {
            _ = existing
            return
        }
        items.insert(notification, at: 0)
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        persist()
    }

    func markRead(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isRead else { return }
        items[index].isRead = true
        persist()
    }

    func markAllRead() {
        guard items.contains(where: { !$0.isRead }) else { return }
        for index in items.indices {
            items[index].isRead = true
        }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            items = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([CustomerAppNotification].self, from: data)) ?? []
    }

    private func persist() {
        let snapshot = items
        let url = Self.fileURL
        Self.ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static let ioQueue = DispatchQueue(
        label: "com.chercharge.customer-notifications",
        qos: .utility
    )

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
}
