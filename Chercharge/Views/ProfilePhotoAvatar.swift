//
//  ProfilePhotoAvatar.swift
//  Chercharge
//

import PhotosUI
import SwiftUI
import UIKit

/// Circular profile avatar that lets the customer take a photo, choose one
/// from the library, or remove the current picture.
struct ProfilePhotoAvatar: View {
    @Environment(BookingStore.self) private var store

    var size: CGFloat = 72
    var showsCameraBadge: Bool = true

    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?

    var body: some View {
        Button {
            showSourceDialog = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                avatarContent
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Brand.gold.opacity(0.55), lineWidth: 2))
                    .shadow(color: Brand.ink.opacity(0.08), radius: 6, y: 2)

                if showsCameraBadge {
                    Image(systemName: "camera.fill")
                        .font(.system(size: max(10, size * 0.16), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(max(5, size * 0.08))
                        .background(Circle().fill(Brand.greenDeep))
                        .overlay(Circle().stroke(Brand.gold.opacity(0.7), lineWidth: 1))
                        .offset(x: 2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.profilePhotoData == nil ? "Add profile photo" : "Change profile photo")
        .confirmationDialog("Profile photo", isPresented: $showSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take photo") { showCamera = true }
            }
            Button("Choose from library") { showLibrary = true }
            if store.profilePhotoData != nil {
                Button("Remove photo", role: .destructive) {
                    store.clearProfilePhoto()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(source: .camera) { data in
                store.setProfilePhoto(data)
                showCamera = false
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, newItem in
            Task { await loadLibraryPhoto(newItem) }
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if store.profilePhotoData != nil {
            CachedDataImage(data: store.profilePhotoData, maxPixelSide: max(144, size * 2), contentMode: .fill)
        } else {
            Circle()
                .fill(Brand.green.opacity(0.2))
                .overlay {
                    Text(String(store.profileName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.greenDeep)
                }
        }
    }

    private func loadLibraryPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Normalize to JPEG for consistent storage.
        if let uiImage = UIImage(data: data), let jpeg = uiImage.jpegData(compressionQuality: 0.85) {
            store.setProfilePhoto(jpeg)
        } else {
            store.setProfilePhoto(data)
        }
        libraryItem = nil
    }
}
