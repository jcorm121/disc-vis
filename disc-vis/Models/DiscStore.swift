import SwiftUI

@Observable
@MainActor
final class DiscStore {
    var bag: [DiscReference] = []
    var selectedReference: DiscReference?
    var searchQuery = ""
    var uploadedImageData: Data?

    static let library: [LibraryDisc] = [
        LibraryDisc(id: "firebird", name: "Firebird"),
        LibraryDisc(id: "roc", name: "Roc"),
        LibraryDisc(id: "buzzz", name: "Buzzz"),
        LibraryDisc(id: "destroyer", name: "Destroyer"),
        LibraryDisc(id: "aviar", name: "Aviar"),
        LibraryDisc(id: "zone", name: "Zone"),
    ]

    var filteredLibrary: [LibraryDisc] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Self.library }
        return Self.library.filter { $0.name.lowercased().contains(query) }
    }

    func selectFromLibrary(_ disc: LibraryDisc) {
        selectedReference = DiscReference(id: UUID(), name: disc.name, source: .library(disc))
    }

    func selectFromBag(_ disc: DiscReference) {
        selectedReference = disc
    }

    func selectUploaded(name: String) {
        selectedReference = DiscReference(id: UUID(), name: name, source: .uploaded)
    }

    func addToBag(_ disc: DiscReference) {
        guard !bag.contains(where: { $0.name == disc.name && $0.source == disc.source }) else { return }
        bag.append(disc)
    }

    func removeFromBag(_ disc: DiscReference) {
        bag.removeAll { $0.id == disc.id }
        if selectedReference?.id == disc.id {
            selectedReference = nil
        }
    }
}
