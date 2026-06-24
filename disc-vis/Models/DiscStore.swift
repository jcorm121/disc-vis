import SwiftUI

@Observable
@MainActor
final class DiscStore {
    var bag: [DiscReference] = []
    var selectedReference: DiscReference?
    var searchQuery = ""

    static let library: [LibraryDisc] = [
        LibraryDisc(id: "firebird", name: "Firebird"),
        LibraryDisc(id: "roc", name: "Roc"),
        LibraryDisc(id: "buzzz", name: "Buzzz"),
        LibraryDisc(id: "destroyer", name: "Destroyer"),
        LibraryDisc(id: "aviar", name: "Aviar"),
        LibraryDisc(id: "zone", name: "Zone"),
    ]

    init() {
        loadPersistedBag()
    }

    var filteredLibrary: [LibraryDisc] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Self.library }
        return Self.library.filter { $0.name.lowercased().contains(query) }
    }

    func selectFromLibrary(_ disc: LibraryDisc) {
        selectedReference = DiscReference(id: UUID(), name: disc.name, source: .library(disc.id))
        persistBag()
    }

    func selectFromBag(_ disc: DiscReference) {
        selectedReference = disc
        persistBag()
    }

    func selectCustom(_ reference: DiscReference) {
        selectedReference = reference
        persistBag()
    }

    func image(for reference: DiscReference) -> UIImage? {
        switch reference.source {
        case .library(let libraryId):
            return UIImage(named: libraryId)
        case .custom:
            return DiscImageStore.loadImage(for: reference.id)
        }
    }

    func addLibraryToBag(_ disc: LibraryDisc) {
        let reference = DiscReference(id: UUID(), name: disc.name, source: .library(disc.id))
        addToBag(reference)
    }

    func addToBag(_ disc: DiscReference) {
        let isDuplicate = bag.contains { existing in
            existing.name == disc.name && existing.source == disc.source
        }
        guard !isDuplicate else { return }
        bag.append(disc)
        persistBag()
    }

    @discardableResult
    func addCapturedDisc(from image: UIImage, name: String = "My Disc") throws -> DiscReference {
        let reference = DiscReference(id: UUID(), name: uniqueDiscName(name), source: .custom)
        try DiscImageStore.saveCroppedDiscImage(image, id: reference.id)
        addToBag(reference)
        selectedReference = reference
        persistBag()
        return reference
    }

    func removeFromBag(_ disc: DiscReference) {
        bag.removeAll { $0.id == disc.id }
        if disc.isCustom {
            DiscImageStore.deleteImage(for: disc.id)
        }
        if selectedReference?.id == disc.id {
            selectedReference = nil
        }
        persistBag()
    }

    private func uniqueDiscName(_ base: String) -> String {
        guard bag.contains(where: { $0.name == base }) else { return base }
        var index = 2
        while bag.contains(where: { $0.name == "\(base) \(index)" }) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func loadPersistedBag() {
        let state = BagPersistence.loadState()
        bag = state.entries.compactMap { entry in
            switch entry.kind {
            case .library:
                guard let libraryId = entry.libraryId, library(by: libraryId) != nil else { return nil }
                return DiscReference(id: entry.id, name: entry.name, source: .library(libraryId))
            case .custom:
                guard DiscImageStore.loadImage(for: entry.id) != nil else { return nil }
                return DiscReference(id: entry.id, name: entry.name, source: .custom)
            }
        }

        if let selectedID = state.selectedReferenceID,
           let selected = bag.first(where: { $0.id == selectedID }) {
            selectedReference = selected
        }
    }

    private func persistBag() {
        let entries = bag.map { reference in
            PersistedBagEntry(
                id: reference.id,
                name: reference.name,
                kind: reference.isCustom ? .custom : .library,
                libraryId: {
                    if case .library(let id) = reference.source { return id }
                    return nil
                }()
            )
        }
        let state = PersistedBagState(entries: entries, selectedReferenceID: selectedReference?.id)
        BagPersistence.saveState(state)
    }

    private func library(by id: String) -> LibraryDisc? {
        Self.library.first { $0.id == id }
    }
}
