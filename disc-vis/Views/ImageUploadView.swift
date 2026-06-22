import PhotosUI
import SwiftUI

struct ImageUploadView: View {
    @Environment(DiscStore.self) private var store
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var discName = "My Disc"

    var body: some View {
        DiscSelectScreen(
            title: "Upload",
            subtitle: "Add a photo of your disc as a reference"
        ) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                uploadArea
            }
            .buttonStyle(.plain)
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                    store.uploadedImageData = data
                    withAnimation(.smooth(duration: 0.3)) {
                        store.selectUploaded(name: discName)
                    }
                }
            }

            if store.uploadedImageData != nil {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Disc name", text: $discName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(DiscTheme.yellow.opacity(0.5), lineWidth: 1)
                        }
                        .onChange(of: discName) { _, newName in
                            if store.selectedReference?.source == .uploaded {
                                store.selectUploaded(name: newName)
                            }
                        }

                    if let reference = store.selectedReference, reference.source == .uploaded {
                        Button {
                            withAnimation(.smooth(duration: 0.25)) {
                                store.addToBag(reference)
                            }
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
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.35), value: store.uploadedImageData != nil)
    }

    private var uploadArea: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white.opacity(0.7))
                    .frame(height: 200)

                if let data = store.uploadedImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(DiscTheme.orange.opacity(0.6), lineWidth: 2)
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(DiscTheme.accentGradient)
                            .symbolEffect(.pulse)

                        Text("Tap to choose a photo")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if store.selectedReference?.source == .uploaded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DiscTheme.orange)
                    Text("Selected as reference")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    ImageUploadView()
        .environment(DiscStore())
}
