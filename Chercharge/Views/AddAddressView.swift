//
//  AddAddressView.swift
//  Chercharge
//
//  Add / edit pickup address — map, label chips, access details, default toggle.
//

import CoreLocation
import MapKit
import SwiftUI

struct AddAddressView: View {
    @Environment(BookingStore.self) private var store
    @Environment(UserLocationService.self) private var userLocation
    @Environment(\.dismiss) private var dismiss

    /// Pass an existing address to edit; omit to add a new one.
    var existing: LocationPin? = nil

    @State private var selectedLabel: AddressLabelPreset = .home
    @State private var customLabel = ""
    @State private var addressQuery = ""
    @State private var resolvedAddress = ""
    @State private var coordinate = CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )
    @State private var gateCode = ""
    @State private var apartmentUnit = ""
    @State private var parkingSpot = ""
    @State private var pickupInstructions = ""
    @State private var vehicleNotes = ""
    @State private var isDefault = false
    @State private var errorMessage: String?
    @State private var didLoadExisting = false
    @State private var isResolvingLocation = false
    @State private var showSuggestions = false

    @State private var search = AddressSearchModel()

    private let notesLimit = 120

    private var isEditing: Bool { existing != nil }

    private var labelName: String {
        selectedLabel == .custom
            ? customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedLabel.rawValue
    }

    private var displayAddress: String {
        let resolved = resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty { return resolved }
        return addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !labelName.isEmpty && !displayAddress.isEmpty
    }

    private var serviceAvailable: Bool {
        !displayAddress.isEmpty
    }

    var body: some View {
        ZStack {
            ConciergeLuxeBackground()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        mapCard
                        availabilityCard
                        labelCard
                        addressCard
                        accessGrid
                        vehicleNotesCard
                        defaultToggleCard

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 0.75, green: 0.25, blue: 0.15))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        saveButton
                        secureFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { loadExistingIfNeeded() }
        .onChange(of: addressQuery) { _, newValue in
            search.updateQuery(newValue)
            showSuggestions = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && resolvedAddress != newValue
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(ConciergeLuxe.card)
                            .shadow(color: ConciergeLuxe.charcoal.opacity(0.08), radius: 8, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            Text(isEditing ? "Edit Pickup Address" : "Add Pickup Address")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(ConciergeLuxe.emerald)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            Image("CherchargeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .accessibilityLabel("Chercharge")
        }
    }

    // MARK: - Map

    private var mapCard: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                Annotation("", coordinate: coordinate) {
                    ZStack {
                        Circle()
                            .fill(ConciergeLuxe.emerald.opacity(0.18))
                            .frame(width: 72, height: 72)
                        Circle()
                            .fill(ConciergeLuxe.emerald.opacity(0.28))
                            .frame(width: 36, height: 36)
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(ConciergeLuxe.emerald)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .disabled(true)

            Button {
                useCurrentLocation()
            } label: {
                HStack(spacing: 8) {
                    if isResolvingLocation {
                        ProgressView()
                            .tint(ConciergeLuxe.emerald)
                    } else {
                        Image(systemName: "location.viewfinder")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Use Current Location")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(ConciergeLuxe.emerald)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(ConciergeLuxe.card)
                        .shadow(color: ConciergeLuxe.charcoal.opacity(0.12), radius: 10, y: 3)
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
            .disabled(isResolvingLocation)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ConciergeLuxe.gold.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Availability

    private var availabilityCard: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: serviceAvailable ? "checkmark.circle.fill" : "mappin.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(serviceAvailable ? ConciergeLuxe.emerald : ConciergeLuxe.muted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(serviceAvailable ? "CherCharge Available" : "Set a pickup address")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ConciergeLuxe.emerald)
                    Text(serviceAvailable ? "We service this area" : "Search or use current location")
                        .font(.system(size: 12))
                        .foregroundStyle(ConciergeLuxe.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(ConciergeLuxe.emerald.opacity(0.15))
                .frame(width: 1, height: 36)
                .padding(.horizontal, 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Est. Arrival")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConciergeLuxe.muted)
                Text(serviceAvailable ? "12 – 18 min" : "—")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.emerald)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.90, green: 0.95, blue: 0.92))
        )
    }

    // MARK: - Label chips

    private var labelCard: some View {
        formCard(icon: "house.fill", title: "Label") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AddressLabelPreset.allCases) { preset in
                        labelChip(preset)
                    }
                }
            }

            if selectedLabel == .custom {
                TextField("Custom label", text: $customLabel)
                    .textInputAutocapitalization(.words)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ConciergeLuxe.ivoryDeep.opacity(0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(ConciergeLuxe.gold.opacity(0.25), lineWidth: 1)
                            )
                    )
            }
        }
    }

    private func labelChip(_ preset: AddressLabelPreset) -> some View {
        let selected = selectedLabel == preset
        return Button {
            selectedLabel = preset
            if preset != .custom {
                customLabel = ""
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(preset.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? ConciergeLuxe.card : ConciergeLuxe.emerald)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(selected ? ConciergeLuxe.emerald : ConciergeLuxe.card)
                    .overlay(
                        Capsule()
                            .stroke(
                                selected ? ConciergeLuxe.emerald : ConciergeLuxe.emerald.opacity(0.25),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Address search

    private var addressCard: some View {
        formCard(icon: "mappin.and.ellipse", title: "Address") {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ConciergeLuxe.muted)

                TextField("Search for an address", text: $addressQuery)
                    .textInputAutocapitalization(.words)
                    .font(.system(size: 15))
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await resolveQueryAsAddress() }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ConciergeLuxe.ivoryDeep.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ConciergeLuxe.gold.opacity(0.25), lineWidth: 1)
                    )
            )

            if showSuggestions, !search.completions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(search.completions.prefix(5), id: \.self) { item in
                        Button {
                            Task { await selectCompletion(item) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(ConciergeLuxe.emerald)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(ConciergeLuxe.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if item != search.completions.prefix(5).last {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ConciergeLuxe.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ConciergeLuxe.gold.opacity(0.2), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Access details

    private var accessGrid: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                compactField(
                    icon: "lock.fill",
                    title: "Gate Code (Optional)",
                    placeholder: "e.g. #4732",
                    text: $gateCode
                )
                compactField(
                    icon: "building.2.fill",
                    title: "Apartment / Unit (Optional)",
                    placeholder: "e.g. Unit 5A",
                    text: $apartmentUnit
                )
            }

            HStack(alignment: .top, spacing: 12) {
                compactField(
                    icon: "car.fill",
                    title: "Parking Spot (Optional)",
                    placeholder: "e.g. B17",
                    text: $parkingSpot
                )
                limitedNotesField(
                    icon: "doc.text.fill",
                    title: "Pickup Instructions",
                    placeholder: "Add any details for our driver...",
                    text: $pickupInstructions
                )
            }
        }
    }

    private var vehicleNotesCard: some View {
        formCard(icon: "car.side.fill", title: "Vehicle Notes (Optional)") {
            limitedTextEditor(
                placeholder: "e.g. White Tesla in front row",
                text: $vehicleNotes
            )
        }
    }

    private var defaultToggleCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ConciergeLuxe.gold)
                .frame(width: 34, height: 34)
                .background(Circle().fill(ConciergeLuxe.gold.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Set as default pickup address")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                Text("We’ll use this address for future bookings.")
                    .font(.system(size: 12))
                    .foregroundStyle(ConciergeLuxe.muted)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isDefault)
                .labelsHidden()
                .tint(ConciergeLuxe.emerald)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ConciergeLuxe.gold)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(ConciergeLuxe.gold.opacity(0.2)))

                Text(isEditing ? "Save Changes" : "Save Address")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.gold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule()
                    .fill(ConciergeLuxe.emeraldGradient)
                    .overlay(
                        Capsule()
                            .stroke(ConciergeLuxe.gold.opacity(canSave ? 0.55 : 0.2), lineWidth: 1.2)
                    )
                    .shadow(color: ConciergeLuxe.emerald.opacity(canSave ? 0.25 : 0), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.55)
    }

    private var secureFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Your information is secure and encrypted")
                .font(.system(size: 12))
        }
        .foregroundStyle(ConciergeLuxe.muted.opacity(0.85))
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Building blocks

    private func formCard<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(ConciergeLuxe.emerald.opacity(0.12)))

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(ConciergeLuxe.emerald)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func compactField(
        icon: String,
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ConciergeLuxe.ivoryDeep.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(ConciergeLuxe.gold.opacity(0.22), lineWidth: 1)
                        )
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func limitedNotesField(
        icon: String,
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConciergeLuxe.emerald)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            limitedTextEditor(placeholder: placeholder, text: text)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func limitedTextEditor(placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(ConciergeLuxe.muted.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }

                TextField("", text: text, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(3...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        if newValue.count > notesLimit {
                            text.wrappedValue = String(newValue.prefix(notesLimit))
                        }
                    }
            }
            .frame(minHeight: 88, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ConciergeLuxe.ivoryDeep.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ConciergeLuxe.gold.opacity(0.22), lineWidth: 1)
                    )
            )

            Text("\(text.wrappedValue.count)/\(notesLimit)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConciergeLuxe.muted)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(ConciergeLuxe.card)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ConciergeLuxe.gold.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: ConciergeLuxe.charcoal.opacity(0.05), radius: 8, y: 3)
    }

    // MARK: - Actions

    private func loadExistingIfNeeded() {
        guard !didLoadExisting else { return }
        didLoadExisting = true

        if let existing {
            selectedLabel = AddressLabelPreset.matching(name: existing.name)
            if selectedLabel == .custom {
                customLabel = existing.name
            }
            addressQuery = existing.address
            resolvedAddress = existing.address
            coordinate = existing.coordinate
            moveCamera(to: existing.coordinate)
            gateCode = existing.gateCode ?? ""
            apartmentUnit = existing.apartmentUnit ?? ""
            parkingSpot = existing.parkingSpot ?? ""
            pickupInstructions = existing.pickupInstructions ?? ""
            vehicleNotes = existing.vehicleNotes ?? ""
            isDefault = existing.isDefault
        } else {
            isDefault = store.savedAddresses.isEmpty
        }
    }

    private func moveCamera(to coordinate: CLLocationCoordinate2D) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            )
        )
    }

    private func useCurrentLocation() {
        isResolvingLocation = true
        errorMessage = nil
        userLocation.refresh(preferenceEnabled: true)

        Task {
            // Wait briefly for a GPS fix after permission / request.
            for _ in 0..<20 {
                if let coord = userLocation.coordinate {
                    await applyCoordinate(coord, preferredAddress: nil)
                    isResolvingLocation = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            isResolvingLocation = false
            errorMessage = userLocation.lastError
                ?? "Couldn’t get your current location. Check Location permission in Settings."
        }
    }

    private func selectCompletion(_ item: MKLocalSearchCompletion) async {
        showSuggestions = false
        addressQuery = [item.title, item.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        let request = MKLocalSearch.Request(completion: item)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else { return }
            let coord = mapItem.placemark.coordinate
            let line = formattedAddress(from: mapItem) ?? addressQuery
            await applyCoordinate(coord, preferredAddress: line)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveQueryAsAddress() async {
        let query = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else {
                errorMessage = "No matching address found."
                return
            }
            let coord = mapItem.placemark.coordinate
            let line = formattedAddress(from: mapItem) ?? query
            await applyCoordinate(coord, preferredAddress: line)
            showSuggestions = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyCoordinate(
        _ coord: CLLocationCoordinate2D,
        preferredAddress: String?
    ) async {
        coordinate = coord
        moveCamera(to: coord)

        if let preferredAddress, !preferredAddress.isEmpty {
            resolvedAddress = preferredAddress
            addressQuery = preferredAddress
            return
        }

        let geocoder = CLGeocoder()
        do {
            let marks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            )
            if let mark = marks.first {
                let line = [
                    mark.name,
                    mark.locality,
                    mark.administrativeArea,
                ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
                if !line.isEmpty {
                    resolvedAddress = line
                    addressQuery = line
                }
            }
        } catch {
            // Keep whatever query the user typed.
        }
    }

    private func formattedAddress(from mapItem: MKMapItem) -> String? {
        if let address = mapItem.address?.fullAddress, !address.isEmpty {
            return address
        }
        let mark = mapItem.placemark
        let parts = [
            mark.subThoroughfare,
            mark.thoroughfare,
            mark.locality,
            mark.administrativeArea,
            mark.postalCode,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        return parts.isEmpty ? mapItem.name : parts.joined(separator: ", ")
    }

    private func save() {
        errorMessage = nil
        let name = labelName
        let address = displayAddress
        do {
            if let existing {
                _ = try store.updateAddress(
                    id: existing.id,
                    name: name,
                    address: address,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    gateCode: gateCode,
                    apartmentUnit: apartmentUnit,
                    parkingSpot: parkingSpot,
                    pickupInstructions: pickupInstructions,
                    vehicleNotes: vehicleNotes,
                    isDefault: isDefault
                )
            } else {
                _ = try store.addAddress(
                    name: name,
                    address: address,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    gateCode: gateCode,
                    apartmentUnit: apartmentUnit,
                    parkingSpot: parkingSpot,
                    pickupInstructions: pickupInstructions,
                    vehicleNotes: vehicleNotes,
                    isDefault: isDefault
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Address search

@MainActor
@Observable
final class AddressSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completions = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.completions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
        }
    }
}

#Preview {
    NavigationStack {
        AddAddressView()
    }
    .environment(BookingStore())
    .environment(UserLocationService())
}
