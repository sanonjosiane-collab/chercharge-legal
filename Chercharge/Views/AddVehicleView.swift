//
//  AddVehicleView.swift
//  Chercharge
//
//  Register Your Vehicle — matches the luxury mock: quilted emerald header,
//  cream botanical body, gold field cards, crown CTA.
//

import PhotosUI
import SwiftUI

private enum RegisterVehiclePalette {
    static let cream = Color(red: 0.975, green: 0.958, blue: 0.930)
    static let creamCard = Color(red: 0.992, green: 0.984, blue: 0.968)
    static let emerald = Color(red: 0.05, green: 0.28, blue: 0.17)
    static let emeraldDeep = Color(red: 0.03, green: 0.18, blue: 0.11)
    static let emeraldHeader = Color(red: 0.04, green: 0.22, blue: 0.14)
    static let gold = Color(red: 0.83, green: 0.68, blue: 0.30)
    static let goldBright = Color(red: 0.92, green: 0.78, blue: 0.38)
    static let goldDark = Color(red: 0.70, green: 0.54, blue: 0.22)
    static let muted = Color(red: 0.42, green: 0.44, blue: 0.40)
    static let leafWash = Color(red: 0.78, green: 0.74, blue: 0.62)
}

struct AddVehicleView: View {
    @Environment(BookingStore.self) private var store
    @Environment(DocumentReviewInbox.self) private var documentInbox
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    /// Pass an existing vehicle to edit; omit to add a new one.
    var existing: Vehicle? = nil

    @State private var make = ""
    @State private var model = ""
    @State private var makeSelection = ""
    @State private var modelSelection = ""
    @State private var customMake = ""
    @State private var customModel = ""
    @State private var yearText = ""
    @State private var licensePlate = ""
    @State private var licensePlateState: USLicensePlateState = .CA
    @State private var registrationExpiration = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var insuranceCompanyName = ""
    @State private var insurancePolicy = ""
    @State private var insurancePolicyExpiration = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var registrationPickerItem: PhotosPickerItem?
    @State private var insurancePickerItem: PhotosPickerItem?
    @State private var registrationPhotoData: Data?
    @State private var registrationPreview: Image?
    @State private var insuranceCardPhotoData: Data?
    @State private var insuranceCardPreview: Image?
    @State private var isLoadingRegistrationPhoto = false
    @State private var isLoadingInsurancePhoto = false
    @State private var paintColor: TeslaPaint = .pearlWhite
    @State private var smokingInVehicle = false
    @State private var errorMessage: String?
    @State private var didLoadExisting = false
    @State private var showStatePicker = false
    @State private var isSubmittingToAdmin = false

    private var isEditing: Bool { existing != nil }

    private var year: Int? {
        Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var availableModels: [String] {
        guard !makeSelection.isEmpty else { return [] }
        return VehicleCatalog.models(forMake: makeSelection == VehicleCatalog.other ? VehicleCatalog.other : makeSelection)
    }

    private func applyMakeSelection(_ selected: String) {
        makeSelection = selected
        if selected == VehicleCatalog.other {
            make = customMake.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            customMake = ""
            make = selected
        }
        // Reset model when make changes — previous model rarely applies.
        modelSelection = ""
        model = ""
        customModel = ""
        if selected == VehicleCatalog.other {
            modelSelection = VehicleCatalog.other
        }
    }

    private func applyModelSelection(_ selected: String) {
        modelSelection = selected
        if selected == VehicleCatalog.other {
            model = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            customModel = ""
            model = selected
        }
    }

    private var canSave: Bool {
        let basicsOK = !make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (year.map { (1990...2030).contains($0) } ?? false)
            && !licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !insuranceCompanyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !insurancePolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && registrationPhotoData != nil
            && !isLoadingRegistrationPhoto
            && !isLoadingInsurancePhoto
            && !isSubmittingToAdmin

        if isEditing {
            return basicsOK
        }
        return store.canAddVehicle && basicsOK
    }

    var body: some View {
        ZStack {
            RegisterVehiclePalette.cream
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    formBody
                        .padding(.top, 22)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 36)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { loadExistingIfNeeded() }
        .onChange(of: registrationPickerItem) { _, newItem in
            Task { await loadRegistrationPhoto(from: newItem) }
        }
        .onChange(of: insurancePickerItem) { _, newItem in
            Task { await loadInsuranceCardPhoto(from: newItem) }
        }
        .sheet(isPresented: $showStatePicker) {
            NavigationStack {
                List(USLicensePlateState.allCases) { state in
                    Button {
                        licensePlateState = state
                        showStatePicker = false
                    } label: {
                        HStack {
                            Text(state.menuLabel)
                                .foregroundStyle(RegisterVehiclePalette.emerald)
                            Spacer()
                            if state == licensePlateState {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(RegisterVehiclePalette.gold)
                            }
                        }
                    }
                }
                .navigationTitle("Plate state")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showStatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header (quilted emerald)

    private var header: some View {
        ZStack(alignment: .top) {
            RegisterVehiclePalette.emeraldHeader
                .overlay { DiamondQuiltOverlay() }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            .clear,
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundStyle(RegisterVehiclePalette.goldBright)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .stroke(RegisterVehiclePalette.gold.opacity(0.85), lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Image("CherchargeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .shadow(color: RegisterVehiclePalette.gold.opacity(0.35), radius: 8, y: 2)
                    .padding(.top, 6)

                Text(isEditing ? "Edit Your Vehicle" : "Register Your Vehicle")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 24)

                Text("Your chariot awaits.")
                    .font(.system(size: 16, weight: .regular, design: .serif).italic())
                    .foregroundStyle(RegisterVehiclePalette.goldBright)
                    .padding(.top, 6)

                RegisterHeaderOrnament()
                    .padding(.top, 18)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Form body

    private var formBody: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 22) {
                section(title: "The Vehicle", systemImage: "car.fill") {
                    RegisterFieldCard {
                        registerDropdownRow(
                            icon: "car.fill",
                            placeholder: "Make",
                            selection: makeSelection.isEmpty ? nil : makeSelection,
                            options: VehicleCatalog.makes,
                            disabled: existing?.isTeslaLinked == true
                        ) { selected in
                            applyMakeSelection(selected)
                        }
                        if makeSelection == VehicleCatalog.other {
                            RegisterRowDivider()
                            registerTextRow(
                                icon: "pencil",
                                placeholder: "Enter make",
                                text: $customMake,
                                disabled: existing?.isTeslaLinked == true
                            )
                            .onChange(of: customMake) { _, value in
                                make = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                // Custom make → model must be custom too.
                                if modelSelection != VehicleCatalog.other {
                                    modelSelection = VehicleCatalog.other
                                    model = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                        }
                        RegisterRowDivider()
                        registerDropdownRow(
                            icon: "car.side.fill",
                            placeholder: makeSelection.isEmpty ? "Select make first" : "Model",
                            selection: modelSelection.isEmpty ? nil : modelSelection,
                            options: availableModels,
                            disabled: existing?.isTeslaLinked == true || makeSelection.isEmpty
                        ) { selected in
                            applyModelSelection(selected)
                        }
                        if modelSelection == VehicleCatalog.other {
                            RegisterRowDivider()
                            registerTextRow(
                                icon: "pencil",
                                placeholder: "Enter model",
                                text: $customModel,
                                disabled: existing?.isTeslaLinked == true
                            )
                            .onChange(of: customModel) { _, value in
                                model = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        RegisterRowDivider()
                        registerTextRow(
                            icon: "calendar",
                            placeholder: "Year",
                            text: $yearText,
                            keyboard: .numberPad,
                            disabled: existing?.isTeslaLinked == true
                        )
                    }
                }

                section(title: "Registration", systemImage: "doc.text.fill") {
                    RegisterFieldCard {
                        registerTextRow(
                            icon: "rectangle.fill.on.rectangle.fill",
                            placeholder: "License plate",
                            text: $licensePlate,
                            autocap: .characters
                        )
                        RegisterRowDivider()
                        Button { showStatePicker = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(RegisterVehiclePalette.gold)
                                    .frame(width: 22)
                                Text("State")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(RegisterVehiclePalette.muted)
                                Spacer(minLength: 8)
                                Text(licensePlateState.menuLabel)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(RegisterVehiclePalette.emerald)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(RegisterVehiclePalette.gold.opacity(0.75))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        RegisterRowDivider()
                        registerDateRow(
                            icon: "calendar",
                            label: "Registration expiration",
                            date: $registrationExpiration
                        )
                    }
                }

                section(title: "Exterior Finish", systemImage: "paintpalette.fill") {
                    RegisterFieldCard {
                        Menu {
                            ForEach(TeslaPaint.allCases) { paint in
                                Button(paint.label) { paintColor = paint }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(RegisterVehiclePalette.gold)
                                    .frame(width: 22)
                                Text("Color")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(RegisterVehiclePalette.muted)
                                Spacer(minLength: 8)
                                Text(paintColor.label)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(RegisterVehiclePalette.emerald)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(RegisterVehiclePalette.gold.opacity(0.75))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        }
                    }
                }

                section(title: "Smoking in Vehicle", systemImage: "smoke.fill") {
                    Text("Does anyone smoke or vape inside this vehicle?")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RegisterVehiclePalette.muted)
                        .padding(.bottom, 4)

                    RegisterFieldCard {
                        smokingOptionRow(title: "No", isSelected: smokingInVehicle == false) {
                            smokingInVehicle = false
                        }
                        RegisterRowDivider()
                        smokingOptionRow(title: "Yes", isSelected: smokingInVehicle == true) {
                            smokingInVehicle = true
                        }
                    }
                }

                section(title: "Protection & Insurance", systemImage: "checkmark.shield.fill") {
                    RegisterFieldCard {
                        registerTextRow(
                            icon: "building.2.fill",
                            placeholder: "Insurance company",
                            text: $insuranceCompanyName
                        )
                        RegisterRowDivider()
                        registerTextRow(
                            icon: "shield.fill",
                            placeholder: "Policy number (admin review)",
                            text: $insurancePolicy,
                            autocap: .characters
                        )
                        RegisterRowDivider()
                        registerDateRow(
                            icon: "calendar.badge.clock",
                            label: "Policy expiration",
                            date: $insurancePolicyExpiration
                        )
                    }
                }

                if let existing {
                    documentApprovalBanner(for: existing)
                }

                section(title: "Official Documents", systemImage: "doc.viewfinder") {
                    RegisterFieldCard {
                        documentPhotoRow(
                            pickerItem: $registrationPickerItem,
                            preview: registrationPreview,
                            isLoading: isLoadingRegistrationPhoto,
                            emptyTitle: "Add registration photo",
                            filledTitle: "Change registration photo",
                            footnote: "High priority · Required"
                        )
                    }

                    Text("Registration photo and policy number are reviewed by an admin before you can book.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RegisterVehiclePalette.emerald.opacity(0.7))
                        .padding(.top, 2)

                    RegisterFieldCard {
                        documentPhotoRow(
                            pickerItem: $insurancePickerItem,
                            preview: insuranceCardPreview,
                            isLoading: isLoadingInsurancePhoto,
                            emptyTitle: "Add insurance card photo",
                            filledTitle: "Change insurance card photo",
                            footnote: "Optional"
                        )
                    }
                    .padding(.top, 10)

                    Text("Insurance card photo is optional.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RegisterVehiclePalette.muted)
                        .padding(.top, 2)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.72, green: 0.18, blue: 0.16))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !store.canAddVehicle, !isEditing {
                    Text("Vehicle limit reached (\(Pricing.maxSavedVehicles)). Remove a car before adding another.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RegisterVehiclePalette.muted)
                }

                Button {
                    save()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(
                            isSubmittingToAdmin
                                ? "Sending to admin…"
                                : (isEditing ? "Save Changes" : "Add to My Garage")
                        )
                            .font(.system(size: 18, weight: .bold, design: .serif))
                    }
                    .foregroundStyle(RegisterVehiclePalette.goldBright)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        RegisterVehiclePalette.emerald,
                                        RegisterVehiclePalette.emeraldDeep
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(RegisterVehiclePalette.gold.opacity(0.9), lineWidth: 1.4)
                    )
                    .shadow(color: RegisterVehiclePalette.emeraldDeep.opacity(0.35), radius: 12, y: 6)
                    .opacity(canSave ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .padding(.top, 8)

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Documents are securely protected")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(RegisterVehiclePalette.goldDark)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Section chrome

    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(RegisterVehiclePalette.gold)
                    .frame(width: 18, height: 2)

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RegisterVehiclePalette.gold)

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(RegisterVehiclePalette.emerald)
            }

            content()
        }
    }

    @ViewBuilder
    private func documentApprovalBanner(for vehicle: Vehicle) -> some View {
        let status = vehicle.documentApprovalStatus
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(status.customerLabel)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
            }
            .foregroundStyle(documentStatusColor(status))

            Text(documentStatusDetail(for: vehicle))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RegisterVehiclePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(RegisterVehiclePalette.creamCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(RegisterVehiclePalette.gold.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func documentStatusColor(_ status: VehicleDocumentApprovalStatus) -> Color {
        switch status {
        case .approved: return RegisterVehiclePalette.emerald
        case .pendingReview: return RegisterVehiclePalette.goldDark
        case .rejected: return Color(red: 0.72, green: 0.18, blue: 0.16)
        case .incomplete: return RegisterVehiclePalette.muted
        }
    }

    private func documentStatusDetail(for vehicle: Vehicle) -> String {
        switch vehicle.documentApprovalStatus {
        case .pendingReview:
            return "An admin will prioritize your registration photo and policy number. Booking unlocks after approval."
        case .approved:
            return "Documents approved. You’re cleared to book concierge charging."
        case .rejected:
            return vehicle.documentRejectionReason
                ?? "Please update your registration photo or policy details and save again."
        case .incomplete:
            return "Submit a registration photo and policy number for admin review."
        }
    }

    private func registerDropdownRow(
        icon: String,
        placeholder: String,
        selection: String?,
        options: [String],
        disabled: Bool = false,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { onSelect(option) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RegisterVehiclePalette.gold)
                    .frame(width: 22)

                if let selection, !selection.isEmpty {
                    Text(selection)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(RegisterVehiclePalette.emerald)
                } else {
                    Text(placeholder)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(RegisterVehiclePalette.muted)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RegisterVehiclePalette.gold.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .opacity(disabled ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .disabled(disabled || options.isEmpty)
        .buttonStyle(.plain)
    }

    private func smokingOptionRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected
                                ? RegisterVehiclePalette.gold
                                : RegisterVehiclePalette.gold.opacity(0.45),
                            lineWidth: 1.4
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(RegisterVehiclePalette.emerald)
                            .frame(width: 12, height: 12)
                    }
                }
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(RegisterVehiclePalette.emerald)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func registerTextRow(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        autocap: TextInputAutocapitalization = .words,
        disabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RegisterVehiclePalette.gold)
                .frame(width: 22)

            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(RegisterVehiclePalette.emerald)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
                .disabled(disabled)
                .opacity(disabled ? 0.55 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func registerDateRow(
        icon: String,
        label: String,
        date: Binding<Date>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RegisterVehiclePalette.gold)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(RegisterVehiclePalette.muted)

            Spacer(minLength: 8)

            DatePicker(
                "",
                selection: date,
                displayedComponents: .date
            )
            .labelsHidden()
            .tint(RegisterVehiclePalette.emerald)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func documentPhotoRow(
        pickerItem: Binding<PhotosPickerItem?>,
        preview: Image?,
        isLoading: Bool,
        emptyTitle: String,
        filledTitle: String,
        footnote: String
    ) -> some View {
        PhotosPicker(selection: pickerItem, matching: .images) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            RegisterVehiclePalette.gold.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])
                        )
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(RegisterVehiclePalette.cream.opacity(0.6))
                        )

                    if isLoading {
                        ProgressView()
                            .tint(RegisterVehiclePalette.gold)
                    } else if let preview {
                        preview
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "doc.text.image")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(RegisterVehiclePalette.gold)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 14))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(RegisterVehiclePalette.emerald, RegisterVehiclePalette.goldBright)
                                    .offset(x: 4, y: 4)
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(preview == nil ? emptyTitle : filledTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(RegisterVehiclePalette.emerald)

                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(footnote) · Securely protected")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(RegisterVehiclePalette.goldDark)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func loadExistingIfNeeded() {
        guard !didLoadExisting, let existing else { return }
        didLoadExisting = true
        let resolvedMake = VehicleCatalog.resolveMakeSelection(existing.make)
        makeSelection = resolvedMake.selection
        customMake = resolvedMake.custom
        make = existing.make

        let resolvedModel = VehicleCatalog.resolveModelSelection(
            make: resolvedMake.selection == VehicleCatalog.other ? VehicleCatalog.other : resolvedMake.selection,
            model: existing.model
        )
        modelSelection = resolvedModel.selection
        customModel = resolvedModel.custom
        model = existing.model
        yearText = String(existing.year)
        licensePlate = existing.licensePlate == "PENDING" ? "" : existing.licensePlate
        if let state = USLicensePlateState(rawValue: existing.licensePlateState.uppercased()) {
            licensePlateState = state
        }
        if let regExp = existing.registrationExpirationDate {
            registrationExpiration = regExp
        }
        insuranceCompanyName = existing.insuranceCompanyName
        insurancePolicy = existing.insurancePolicy
        if let polExp = existing.insurancePolicyExpirationDate {
            insurancePolicyExpiration = polExp
        }
        paintColor = existing.paintColor
        smokingInVehicle = existing.smokingInVehicle
        registrationPhotoData = existing.registrationPhotoData
        if let data = existing.registrationPhotoData, let uiImage = UIImage(data: data) {
            registrationPreview = Image(uiImage: uiImage)
        }
        insuranceCardPhotoData = existing.insuranceCardPhotoData
        if let data = existing.insuranceCardPhotoData, let uiImage = UIImage(data: data) {
            insuranceCardPreview = Image(uiImage: uiImage)
        }
    }

    private func save() {
        guard let year, let registrationPhotoData else { return }
        let plate = licensePlate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plate.isEmpty,
              !insuranceCompanyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = BookingStore.StoreError.vehicleIncomplete.localizedDescription
            return
        }

        errorMessage = nil
        do {
            store.bindDocumentInbox(documentInbox)
            let saved: Vehicle
            if let existing {
                saved = try store.updateVehicle(
                    id: existing.id,
                    make: make,
                    model: model,
                    year: year,
                    insurancePolicy: insurancePolicy,
                    insuranceCompanyName: insuranceCompanyName,
                    registrationExpirationDate: registrationExpiration,
                    insurancePolicyExpirationDate: insurancePolicyExpiration,
                    registrationPhotoData: registrationPhotoData,
                    insuranceCardPhotoData: insuranceCardPhotoData,
                    paintColor: paintColor,
                    smokingInVehicle: smokingInVehicle,
                    licensePlate: plate,
                    licensePlateState: licensePlateState.rawValue
                )
            } else {
                saved = try store.addVehicle(
                    make: make,
                    model: model,
                    year: year,
                    insurancePolicy: insurancePolicy,
                    insuranceCompanyName: insuranceCompanyName,
                    registrationExpirationDate: registrationExpiration,
                    insurancePolicyExpirationDate: insurancePolicyExpiration,
                    registrationPhotoData: registrationPhotoData,
                    insuranceCardPhotoData: insuranceCardPhotoData,
                    paintColor: paintColor,
                    smokingInVehicle: smokingInVehicle,
                    licensePlate: plate,
                    licensePlateState: licensePlateState.rawValue
                )
            }
            // Local device inbox (DEBUG / offline fallback).
            documentInbox.enqueueSubmission(
                for: saved,
                customerName: store.profileName,
                customerEmail: store.profileEmail
            )

            let email = store.profileEmail.isEmpty
                ? (auth.displayEmail ?? "")
                : store.profileEmail
            let name = store.profileName.isEmpty
                ? (auth.displayName ?? "Customer")
                : store.profileName

            isSubmittingToAdmin = true
            Task {
                defer { isSubmittingToAdmin = false }
                do {
                    _ = try await CustomerVehicleDocumentService.shared.submitForAdminReview(
                        vehicle: saved,
                        customerID: auth.supabaseUserID,
                        customerName: name,
                        customerEmail: email
                    )
                    await store.syncVehicleDocumentsWithAdmin(
                        customerID: auth.supabaseUserID,
                        preferredEmail: email
                    )
                    dismiss()
                } catch {
                    // Keep the vehicle saved, but tell the customer why admin didn't get it.
                    errorMessage =
                        "Vehicle saved, but admin review upload failed: \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRegistrationPhoto(from item: PhotosPickerItem?) async {
        registrationPreview = nil
        registrationPhotoData = nil
        guard let item else { return }

        isLoadingRegistrationPhoto = true
        defer { isLoadingRegistrationPhoto = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        registrationPhotoData = data
        if let uiImage = UIImage(data: data) {
            registrationPreview = Image(uiImage: uiImage)
        }
    }

    private func loadInsuranceCardPhoto(from item: PhotosPickerItem?) async {
        insuranceCardPreview = nil
        insuranceCardPhotoData = nil
        guard let item else { return }

        isLoadingInsurancePhoto = true
        defer { isLoadingInsurancePhoto = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        insuranceCardPhotoData = data
        if let uiImage = UIImage(data: data) {
            insuranceCardPreview = Image(uiImage: uiImage)
        }
    }
}

// MARK: - Supporting chrome

private struct RegisterFieldCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RegisterVehiclePalette.creamCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RegisterVehiclePalette.gold.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }
}

private struct RegisterRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(RegisterVehiclePalette.gold.opacity(0.18))
            .frame(height: 0.5)
            .padding(.leading, 48)
    }
}

private struct RegisterHeaderOrnament: View {
    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            RegisterVehiclePalette.gold.opacity(0),
                            RegisterVehiclePalette.gold.opacity(0.85)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 72, height: 1)

            Image(systemName: "diamond.fill")
                .font(.system(size: 7))
                .foregroundStyle(RegisterVehiclePalette.goldBright)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            RegisterVehiclePalette.gold.opacity(0.85),
                            RegisterVehiclePalette.gold.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 72, height: 1)
        }
        .overlay {
            // Soft side flourishes
            HStack {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(RegisterVehiclePalette.gold.opacity(0.55))
                    .rotationEffect(.degrees(-40))
                    .offset(x: -4)
                Spacer()
                Image(systemName: "leaf.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(RegisterVehiclePalette.gold.opacity(0.55))
                    .rotationEffect(.degrees(140))
                    .offset(x: 4)
            }
            .frame(width: 190)
            .allowsHitTesting(false)
        }
    }
}

/// Subtle diamond / channel-quilt stitch over the emerald header.
private struct DiamondQuiltOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 28
            var path = Path()
            var y: CGFloat = -step
            while y < size.height + step {
                var x: CGFloat = -step
                while x < size.width + step {
                    let midX = x + step / 2
                    let midY = y + step / 2
                    path.move(to: CGPoint(x: midX, y: y))
                    path.addLine(to: CGPoint(x: x + step, y: midY))
                    path.addLine(to: CGPoint(x: midX, y: y + step))
                    path.addLine(to: CGPoint(x: x, y: midY))
                    path.closeSubpath()
                    x += step
                }
                y += step
            }
            context.stroke(
                path,
                with: .color(Color.black.opacity(0.14)),
                lineWidth: 0.6
            )
            context.stroke(
                path,
                with: .color(Color.white.opacity(0.04)),
                lineWidth: 0.4
            )
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    NavigationStack {
        AddVehicleView()
    }
    .environment(BookingStore())
    .environment(DocumentReviewInbox())
    .environment(AuthService())
}
