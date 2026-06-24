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
            .background(DiscTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(DiscTheme.surfaceStroke, lineWidth: 1)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 12) {
                ForEach(store.filteredLibrary) { disc in
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            store.selectFromLibrary(disc)
                        }
                    } label: {
                        DiscCard(
                            disc: disc,
                            isSelected: store.selectedReference?.libraryDisc == disc
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Add to Bag") {
                            withAnimation(.smooth(duration: 0.25)) {
                                store.addLibraryToBag(disc)
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
