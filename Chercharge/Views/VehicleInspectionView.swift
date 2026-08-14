//
//  VehicleInspectionView.swift
//  Chercharge
//

import PhotosUI
import SwiftUI

struct VehicleInspectionView: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let job: ChargeJob
    let phase: InspectionPhase

    @State private var frontPhoto: Data?
    @State private var rearPhoto: Data?
    @State private var leftSidePhoto: Data?
    @State private var roofPhoto: Data?
    @State private var interiorVideo: Data?
    @State private var odometerPhoto: Data?
    @State private var batteryPercent = 50.0
    @State private var damage = DamageChecklist()
    @State private var tireCondition: TireCondition = .good
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var capturedAt: Date { Date() }
    private var latitude: Double { job.pickup.latitude }
    private var longitude: Double { job.pickup.longitude }

    private var canSubmit: Bool {
        frontPhoto != nil
            && rearPhoto != nil
            && leftSidePhoto != nil
            && roofPhoto != nil
            && interiorVideo != nil
            && odometerPhoto != nil
            && !isSubmitting
    }

    private var submitTitle: String {
        switch phase {
        case .preTrip: return "Upload & send for customer review"
        case .postTrip: return "Complete post-trip inspection"
        }
    }

    var body: some View {
        Form {
            Section {
                Text(phase == .preTrip
                      ? "Mandatory pre-trip inspection. Media uploads to secure storage, then the customer must approve pickup."
                      : "Mandatory end-of-service inspection. The booking cannot be marked complete until this is finished and stored.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Brand.muted)
            }

            Section("Exterior photos") {
                InspectionMediaRow(title: "Front photo", data: $frontPhoto, matching: .images)
                InspectionMediaRow(title: "Rear photo", data: $rearPhoto, matching: .images)
                InspectionMediaRow(title: "Left side photo", data: $leftSidePhoto, matching: .images)
                InspectionMediaRow(title: "Roof photo", data: $roofPhoto, matching: .images)
            }

            Section("Interior & odometer") {
                InspectionMediaRow(
                    title: "30-second interior video",
                    data: $interiorVideo,
                    matching: .videos,
                    footnote: "Record about 30 seconds of the cabin."
                )
                InspectionMediaRow(title: "Odometer photo", data: $odometerPhoto, matching: .images)
            }

            Section("Battery percentage") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Int(batteryPercent))%")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Brand.greenDeep)
                    Slider(value: $batteryPercent, in: 0...100, step: 1)
                        .tint(Brand.green)
                }
            }

            Section("Existing damage checklist") {
                Toggle("Scratches", isOn: $damage.scratches)
                Toggle("Dents", isOn: $damage.dents)
                Toggle("Cracked glass", isOn: $damage.crackedGlass)
                Toggle("Missing parts", isOn: $damage.missingParts)
                Toggle("Other damage", isOn: $damage.other)
                TextField("Damage notes", text: $damage.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .tint(Brand.green)

            Section("Tire condition") {
                Picker("Tires", selection: $tireCondition) {
                    ForEach(TireCondition.allCases) { condition in
                        Text(condition.title).tag(condition)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Driver, timestamp & GPS") {
                LabeledContent("Driver", value: store.assignedDriverName)
                LabeledContent("Captured at", value: capturedAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Latitude", value: String(format: "%.5f", latitude))
                LabeledContent("Longitude", value: String(format: "%.5f", longitude))
            }
            .font(.system(.subheadline, design: .rounded))

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.system(.footnote, design: .rounded))
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text(submitTitle)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(canSubmit ? Brand.greenDeep : Brand.muted)
                .disabled(!canSubmit)
            } footer: {
                Text("Files are uploaded to Supabase Storage when configured, and always kept with the booking record.")
            }
        }
        .scrollContentBackground(.hidden)
        .brandBackground()
        .navigationTitle(phase.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            batteryPercent = Double(job.vehicle.currentChargePercent)
        }
    }

    private func submit() async {
        guard
            let frontPhoto,
            let rearPhoto,
            let leftSidePhoto,
            let roofPhoto,
            let interiorVideo,
            let odometerPhoto
        else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let inspection = VehicleInspection(
            id: UUID(),
            jobID: job.id,
            phase: phase,
            driverName: store.assignedDriverName,
            frontPhotoData: frontPhoto,
            rearPhotoData: rearPhoto,
            leftSidePhotoData: leftSidePhoto,
            roofPhotoData: roofPhoto,
            interiorVideoData: interiorVideo,
            odometerPhotoData: odometerPhoto,
            batteryPercent: Int(batteryPercent),
            damageChecklist: damage,
            tireCondition: tireCondition,
            capturedAt: capturedAt,
            latitude: latitude,
            longitude: longitude,
            storageURLs: InspectionMediaURLs(),
            uploadedAt: nil
        )

        do {
            try await store.submitInspection(inspection)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct InspectionMediaRow: View {
    let title: String
    @Binding var data: Data?
    let matching: PHPickerFilter
    var footnote: String? = nil

    @State private var item: PhotosPickerItem?
    @State private var isLoading = false
    @State private var preview: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $item, matching: matching) {
                HStack {
                    Label(
                        data == nil ? "Add \(title.lowercased())" : "\(title) added",
                        systemImage: data == nil ? "plus.circle" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(data == nil ? Brand.greenDeep : Brand.green)
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
            }

            if let footnote {
                Text(footnote)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Brand.muted)
            }

            if let preview {
                preview
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if data != nil {
                Label("Media attached", systemImage: "paperclip")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Brand.muted)
            }
        }
        .onChange(of: item) { _, newItem in
            Task { await load(newItem) }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        preview = nil
        data = nil
        guard let item else { return }
        isLoading = true
        defer { isLoading = false }

        guard let loaded = try? await item.loadTransferable(type: Data.self) else { return }
        data = loaded
        if let uiImage = UIImage(data: loaded) {
            preview = Image(uiImage: uiImage)
        }
    }
}

#Preview {
    NavigationStack {
        VehicleInspectionView(
            job: ChargeJob(
                id: UUID(),
                vehicle: SampleVehicles.all[0],
                pickup: SampleLocations.pickups[0],
                station: SampleLocations.station,
                targetChargePercent: 80,
                startingChargePercent: 28,
                status: .driverArrived,
                estimatedPrice: 49.99,
                estimatedMinutes: 40,
                createdAt: Date(),
                preTripInspection: nil,
                postTripInspection: nil,
                customerApprovedPickupAt: nil
            ),
            phase: .preTrip
        )
    }
    .environment(BookingStore())
}
