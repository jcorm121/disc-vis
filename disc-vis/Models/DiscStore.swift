import SwiftUI

@Observable
@MainActor
final class DiscStore {
    var bag: [DiscReference] = []
    var selectedReference: DiscReference?
    var searchQuery = ""
    var uploadedImageData: Data?

    static let library: [LibraryDisc] = [
        LibraryDisc(id: "firebird", name: "Firebird", primaryColor: Color(red: 0.85, green: 0.15, blue: 0.1), secondaryColor: .black),
        LibraryDisc(id: "roc", name: "Roc", primaryColor: Color(red: 0.2, green: 0.55, blue: 0.85), secondaryColor: .white),
        LibraryDisc(id: "buzzz", name: "Buzzz", primaryColor: Color(red: 0.95, green: 0.75, blue: 0.1), secondaryColor: Color(red: 0.15, green: 0.15, blue: 0.15)),
        LibraryDisc(id: "destroyer", name: "Destroyer", primaryColor: Color(red: 0.55, green: 0.1, blue: 0.65), secondaryColor: .white),
        LibraryDisc(id: "aviar", name: "Aviar", primaryColor: Color(red: 0.95, green: 0.95, blue: 0.9), secondaryColor: Color(red: 0.2, green: 0.6, blue: 0.3)),
        LibraryDisc(id: "zone", name: "Zone", primaryColor: Color(red: 0.1, green: 0.1, blue: 0.12), secondaryColor: DiscTheme.orange),
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
