//
//  InspectionComparisonView.swift
//  Chercharge
//

import SwiftUI

struct InspectionComparisonView: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let jobID: UUID

    @State private var showReportSheet = false
    @State private var reportSubmittedMessage: String?

    private var job: ChargeJob? {
        if let active = store.activeJob, active.id == jobID { return active }
        if let completed = store.lastCompletedJob, completed.id == jobID { return completed }
        return store.pastJobs.first { $0.id == jobID }
    }

    private var comparison: InspectionComparison? {
        job?.inspectionComparison
    }

    var body: some View {
        Group {
            if let job, let comparison {
                content(job: job, comparison: comparison)
            } else {
                ContentUnavailableView(
                    "Comparison unavailable",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Both pickup and return inspections are required.")
                )
            }
        }
        .brandBackground()
        .navigationTitle("Pickup vs return")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReportSheet) {
            if let job, let comparison {
                ReportInspectionIssueSheet(
                    jobID: job.id,
                    suggestedDamage: comparison.newDamageItems,
                    tiresWorsened: comparison.tiresWorsened,
                    tireSummary: comparison.tiresWorsened
                        ? "\(comparison.pickup.tireCondition.title) → \(comparison.returnInspection.tireCondition.title)"
                        : nil
                ) { message in
                    reportSubmittedMessage = message
                }
            }
        }
    }

    private func content(job: ChargeJob, comparison: InspectionComparison) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(job: job, comparison: comparison)

                if comparison.hasNewDamage {
                    newDamageBanner(comparison)
                } else {
                    clearBanner
                }

                columnLegend

                ForEach(comparison.photoPairs) { pair in
                    photoPairRow(pair)
                }

                metricsCard(comparison)

                damageSideBySide(comparison)

                if !job.issueReports.isEmpty {
                    priorReports(job.issueReports)
                }

                if let reportSubmittedMessage {
                    Text(reportSubmittedMessage)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Brand.greenDeep)
                }

                Button {
                    dismiss()
                } label: {
                    Text("COMPLETED")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    showReportSheet = true
                } label: {
                    Label("Report an issue", systemImage: "exclamationmark.bubble.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(24)
        }
    }

    private func header(job: ChargeJob, comparison: InspectionComparison) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(job.vehicle.displayName)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.ink)
            Text("Side-by-side review of pickup and return inspections for this booking.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Brand.muted)
            Text("Driver \(comparison.returnInspection.driverName)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Brand.greenDeep)
        }
    }

    private func newDamageBanner(_ comparison: InspectionComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("New damage detected", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.08))

            Text(comparison.highlightSummary)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Brand.ink)

            FlowChips(items: comparison.newDamageItems + (comparison.tiresWorsened ? ["Tires worsened"] : []))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 1.0, green: 0.93, blue: 0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.85, green: 0.45, blue: 0.2), lineWidth: 1.5)
        )
    }

    private var clearBanner: some View {
        Label("No new damage flagged", systemImage: "checkmark.shield.fill")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Brand.greenDeep)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.green.opacity(0.12))
            )
    }

    private var columnLegend: some View {
        HStack {
            legendPill("Pickup", color: Brand.muted)
            Spacer()
            legendPill("Return", color: Brand.greenDeep)
        }
    }

    private func legendPill(_ title: String, color: Color) -> some View {
        Text(title.uppercased())
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func photoPairRow(_ pair: InspectionPhotoPair) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pair.label)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Brand.ink)

            HStack(alignment: .top, spacing: 12) {
                mediaThumb(data: pair.pickupData, isVideo: pair.isVideo, caption: "Pickup")
                mediaThumb(data: pair.returnData, isVideo: pair.isVideo, caption: "Return")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.95))
        )
    }

    private func mediaThumb(data: Data, isVideo: Bool, caption: String) -> some View {
        VStack(spacing: 6) {
            if isVideo {
                VStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .font(.title2)
                    Text("\(max(data.count / 1024, 1)) KB")
                        .font(.system(.caption2, design: .rounded))
                }
                .foregroundStyle(Brand.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .background(RoundedRectangle(cornerRadius: 12).fill(Brand.mist))
            } else if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Color.gray.opacity(0.15)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text(caption)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricsCard(_ comparison: InspectionComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip metrics")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Brand.ink)

            metricRow(
                "Battery",
                pickup: "\(comparison.pickup.batteryPercent)%",
                returned: "\(comparison.returnInspection.batteryPercent)%",
                note: comparison.batteryDelta == 0
                    ? nil
                    : String(format: "%+d%%", comparison.batteryDelta)
            )
            metricRow(
                "Tires",
                pickup: comparison.pickup.tireCondition.title,
                returned: comparison.returnInspection.tireCondition.title,
                highlight: comparison.tiresWorsened
            )
            metricRow(
                "Captured",
                pickup: comparison.pickup.capturedAt.formatted(date: .omitted, time: .shortened),
                returned: comparison.returnInspection.capturedAt.formatted(date: .omitted, time: .shortened)
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.95)))
    }

    private func metricRow(
        _ title: String,
        pickup: String,
        returned: String,
        note: String? = nil,
        highlight: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Brand.muted)

            HStack {
                Text(pickup)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                Text(returned)
                    .fontWeight(highlight ? .bold : .regular)
                    .foregroundStyle(highlight ? Color(red: 0.55, green: 0.22, blue: 0.08) : Brand.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Brand.ink)

            if let note {
                Text(note)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Brand.greenDeep)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlight ? Color(red: 1.0, green: 0.93, blue: 0.88) : Color.clear)
        )
    }

    private func damageSideBySide(_ comparison: InspectionComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Damage checklist")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Brand.ink)

            HStack(alignment: .top, spacing: 12) {
                damageColumn(title: "Pickup", checklist: comparison.pickup.damageChecklist, newItems: [])
                damageColumn(
                    title: "Return",
                    checklist: comparison.returnInspection.damageChecklist,
                    newItems: comparison.newDamageItems
                )
            }

            if let notes = comparison.newDamageNotes {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RETURN NOTES")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Brand.muted)
                    Text(notes)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Brand.ink)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.93, blue: 0.88))
                )
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.95)))
    }

    private func damageColumn(title: String, checklist: DamageChecklist, newItems: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.muted)

            if checklist.flaggedLabels.isEmpty {
                Text("None noted")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Brand.muted)
            } else {
                ForEach(checklist.flaggedLabels, id: \.self) { item in
                    let isNew = newItems.contains(item)
                    HStack(spacing: 6) {
                        Image(systemName: isNew ? "exclamationmark.circle.fill" : "circle.fill")
                            .font(.system(size: isNew ? 12 : 6))
                            .foregroundStyle(isNew ? Color(red: 0.85, green: 0.35, blue: 0.12) : Brand.muted)
                        Text(item)
                            .font(.system(.footnote, design: .rounded).weight(isNew ? .bold : .regular))
                            .foregroundStyle(isNew ? Color(red: 0.55, green: 0.22, blue: 0.08) : Brand.ink)
                        if isNew {
                            Text("NEW")
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(red: 0.85, green: 0.35, blue: 0.12)))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func priorReports(_ reports: [InspectionIssueReport]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reported issues")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Brand.ink)

            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.category)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Brand.ink)
                    Text(report.details)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Brand.muted)
                    Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Brand.muted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Brand.mist))
            }
        }
    }
}

// MARK: - Report sheet

private struct ReportInspectionIssueSheet: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let jobID: UUID
    let suggestedDamage: [String]
    let tiresWorsened: Bool
    let tireSummary: String?
    var onSubmitted: (String) -> Void

    @State private var category: InspectionIssueCategory = .newDamage
    @State private var details = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Describe what looks wrong between pickup and return. Support will review this with the booking record.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Brand.muted)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(InspectionIssueCategory.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if !suggestedDamage.isEmpty || tiresWorsened {
                    Section("Auto-detected") {
                        ForEach(suggestedDamage, id: \.self) { item in
                            Label(item, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.08))
                        }
                        if let tireSummary {
                            Label("Tires: \(tireSummary)", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.08))
                        }
                    }
                }

                Section("Details") {
                    TextField("What happened?", text: $details, axis: .vertical)
                        .lineLimit(4...8)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report an issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submit()
                    }
                    .disabled(isSubmitting || details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if details.isEmpty {
                    var seed: [String] = suggestedDamage
                    if let tireSummary { seed.append("Tire condition: \(tireSummary)") }
                    if !seed.isEmpty {
                        details = "New findings vs pickup: \(seed.joined(separator: ", "))."
                    }
                }
                if !suggestedDamage.isEmpty || tiresWorsened {
                    category = .newDamage
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        var highlighted = suggestedDamage
        if tiresWorsened { highlighted.append("Tire condition worsened") }

        do {
            try store.reportInspectionIssue(
                jobID: jobID,
                category: category.rawValue,
                details: details,
                highlightedDamage: highlighted
            )
            onSubmitted("Issue reported — support will follow up.")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlexibleChipWrap(items: items)
    }
}

/// Simple wrapping chip row without a third-party layout.
private struct FlexibleChipWrap: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunked(items, size: 2), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color(red: 0.55, green: 0.22, blue: 0.08))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color(red: 0.85, green: 0.35, blue: 0.12).opacity(0.15))
                            )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ values: [String], size: Int) -> [[String]] {
        stride(from: 0, to: values.count, by: size).map {
            Array(values[$0..<min($0 + size, values.count)])
        }
    }
}

#Preview {
    NavigationStack {
        InspectionComparisonView(jobID: UUID())
    }
    .environment(BookingStore())
}
