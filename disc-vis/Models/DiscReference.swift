import SwiftUI

struct LibraryDisc: Identifiable, Hashable {
    let id: String
    let name: String
    let primaryColor: Color
    let secondaryColor: Color

    static func == (lhs: LibraryDisc, rhs: LibraryDisc) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DiscReference: Identifiable, Hashable {
    let id: UUID
    var name: String
    var source: Source

    enum Source: Hashable {
        case library(LibraryDisc)
        case uploaded
    }

    var libraryDisc: LibraryDisc? {
        if case .library(let disc) = source { return disc }
        return nil
    }
}
