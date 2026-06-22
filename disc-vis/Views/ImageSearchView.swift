import SwiftUI

struct ImageSearchView: View {
    @Environment(DiscStore.self) private var store

    var body: some View {
        DiscSelectScreen(
            title: "Search",
            subtitle: "Find a reference disc in our library"
        ) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DiscTheme.orange.opacity(0.8))

                TextField("Search discs", text: Bindable(store).searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(DiscTheme.yellow.opacity(0.5), lineWidth: 1)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 12) {
                ForEach(store.filteredLibrary) { disc in
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            store.selectFromLibrary(disc)
                        }
                    } label: {
                        DiscCard(
                            name: disc.name,
                            primaryColor: disc.primaryColor,
                            secondaryColor: disc.secondaryColor,
                            isSelected: store.selectedReference?.libraryDisc == disc
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Add to Bag") {
                            if let reference = store.selectedReference, reference.libraryDisc == disc {
                                withAnimation(.smooth(duration: 0.25)) {
                                    store.addToBag(reference)
                                }
                            } else {
                                withAnimation(.smooth(duration: 0.25)) {
                                    store.addToBag(DiscReference(id: UUID(), name: disc.name, source: .library(disc)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ImageSearchView()
        .environment(DiscStore())
}
