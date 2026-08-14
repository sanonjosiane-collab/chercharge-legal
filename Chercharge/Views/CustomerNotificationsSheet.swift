//
//  CustomerNotificationsSheet.swift
//  Chercharge
//
//  Home bell inbox — admin document approve/reject notices for customers.
//

import SwiftUI

struct CustomerNotificationsSheet: View {
    @Environment(CustomerNotificationInbox.self) private var inbox
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if inbox.items.isEmpty {
                    ContentUnavailableView {
                        Label("No notifications yet", systemImage: "bell")
                    } description: {
                        Text("When an admin approves or rejects your vehicle documents, it will appear here.")
                    }
                } else {
                    List {
                        ForEach(inbox.items) { item in
                            Button {
                                inbox.markRead(id: item.id)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(iconBackground(for: item.kind))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: iconName(for: item.kind))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(iconForeground(for: item.kind))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(item.title)
                                                .font(.system(.subheadline, design: .serif).weight(.semibold))
                                                .foregroundStyle(ConciergeLuxe.emerald)
                                            Spacer(minLength: 8)
                                            if !item.isRead {
                                                Circle()
                                                    .fill(ConciergeLuxe.gold)
                                                    .frame(width: 8, height: 8)
                                            }
                                        }
                                        Text(item.body)
                                            .font(.system(.footnote))
                                            .foregroundStyle(ConciergeLuxe.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(item.createdAt.formatted(.relative(presentation: .named)))
                                            .font(.system(.caption2))
                                            .foregroundStyle(ConciergeLuxe.muted.opacity(0.85))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                item.isRead
                                    ? ConciergeLuxe.card
                                    : ConciergeLuxe.gold.opacity(0.08)
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if inbox.hasUnread {
                        Button("Mark all read") {
                            inbox.markAllRead()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func iconName(for kind: CustomerAppNotificationKind) -> String {
        switch kind {
        case .documentsApproved: return "checkmark.seal.fill"
        case .documentsRejected: return "exclamationmark.triangle.fill"
        }
    }

    private func iconBackground(for kind: CustomerAppNotificationKind) -> Color {
        switch kind {
        case .documentsApproved: return ConciergeLuxe.emerald.opacity(0.12)
        case .documentsRejected: return Color.red.opacity(0.12)
        }
    }

    private func iconForeground(for kind: CustomerAppNotificationKind) -> Color {
        switch kind {
        case .documentsApproved: return ConciergeLuxe.emerald
        case .documentsRejected: return Color.red.opacity(0.85)
        }
    }
}
