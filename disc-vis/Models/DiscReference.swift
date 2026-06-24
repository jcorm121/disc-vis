import Foundation

struct LibraryDisc: Identifiable, Hashable {
    let id: String
    let name: String
}

struct DiscReference: Identifiable, Hashable {
    let id: UUID
    var name: String
    var source: Source

    enum Source: Hashable {
        case library(String)
        case custom
    }

    var libraryDisc: LibraryDisc? {
        guard case .library(let libraryId) = source else { return nil }
        return DiscStore.library.first { $0.id == libraryId }
    }

    var isCustom: Bool {
        if case .custom = source { return true }
        return false
    }
}
