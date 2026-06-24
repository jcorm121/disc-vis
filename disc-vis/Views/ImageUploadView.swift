import PhotosUI
import SwiftUI

struct ImageUploadView: View {
    @Environment(DiscStore.self) private var store
    @Binding var selectedTab: ImageSelectTab

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCaptureCamera = false
    @State private var discName = "My Disc"
    @State private var pendingImage: UIImage?

    var body: some View {
        DiscSelectScreen(
            title: "Upload",
            subtitle: "Add a photo of your disc as a reference"
        ) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    uploadButton(
                        title: "Photos",
                        systemImage: "photo.on.rectangle",
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showCaptureCamera = true
                } label: {
                    uploadButton(
                        title: "Camera",
                        systemImage: "camera.fill",
                        isPrimary: true
                    )
                }
                .buttonStyle(.plain)
            }

            if let pendingImage {
                VStack(alignment: .leading, spacing: 12) {
                    Image(uiImage: DiscImageProcessor.cropToDiscSquare(pendingImage))
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(DiscTheme.orange.opacity(0.6), lineWidth: 2)
                        }

                    TextField("Disc name", text: $discName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(DiscTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(DiscTheme.surfaceStroke, lineWidth: 1)
                        }

                    Button {
                        addPendingPhotoToBag(pendingImage)
                    } label: {
                        Label("Add to Bag", systemImage: "bag.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DiscTheme.accentGradient, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.35), value: pendingImage != nil)
        .onChange(of: selectedPhoto) { _, newItem in
            Task { await loadSelectedPhoto(from: newItem) }
        }
        .fullScreenCover(isPresented: $showCaptureCamera) {
            DiscCaptureCameraView {
                withAnimation(.smooth(duration: 0.35)) {
                    selectedTab = .bag
                }
            }
        }
    }

    private func uploadButton(title: String, systemImage: String, isPrimary: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .foregroundStyle(isPrimary ? .white : DiscTheme.orange)
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 16)
                    .fill(DiscTheme.accentGradient)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(DiscTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(DiscTheme.surfaceStroke, lineWidth: 1)
                    }
            }
        }
    }

    private func loadSelectedPhoto(from item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        withAnimation(.smooth(duration: 0.3)) {
            pendingImage = image
        }
    }

    private func addPendingPhotoToBag(_ image: UIImage) {
        do {
            _ = try store.addCapturedDisc(from: image, name: discName)
            pendingImage = nil
            discName = "My Disc"
            withAnimation(.smooth(duration: 0.25)) {
                selectedTab = .bag
            }
        } catch {
            return
        }
    }
}

#Preview {
    @Previewable @State var tab = ImageSelectTab.upload
    ImageUploadView(selectedTab: $tab)
        .environment(DiscStore())
}
