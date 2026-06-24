import SwiftUI

struct BagView: View {
    @Environment(DiscStore.self) private var store

    var body: some View {
        DiscSelectScreen(
            title: "Bag",
            subtitle: "Your saved discs for quick reuse"
        ) {
            if store.bag.isEmpty {
                ContentUnavailableView {
                    Label("Empty Bag", systemImage: "bag")
                } description: {
                    Text("Add discs from Search or Upload to build your bag.")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 12) {
                    ForEach(store.bag) { disc in
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                store.selectFromBag(disc)
                            }
                        } label: {
                            bagCard(for: disc)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Bag", role: .destructive) {
                                withAnimation(.smooth(duration: 0.25)) {
                                    store.removeFromBag(disc)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bagCard(for disc: DiscReference) -> some View {
        if let libraryDisc = disc.libraryDisc {
            DiscCard(
                disc: libraryDisc,
                isSelected: store.selectedReference?.id == disc.id
            )
        } else {
            VStack(spacing: 10) {
                ZStack {
                    if let uiImage = store.image(for: disc) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(DiscTheme.accentGradient.opacity(0.25))
                            .frame(width: 72, height: 72)
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(DiscTheme.orange)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            store.selectedReference?.id == disc.id ? DiscTheme.orange : .clear,
                            lineWidth: 3
                        )
                        .frame(width: 76, height: 76)
                }

                Text(disc.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    BagView()
        .environment(DiscStore())
}
