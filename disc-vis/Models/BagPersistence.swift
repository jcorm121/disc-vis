import Foundation
import UIKit

struct PersistedBagEntry: Codable, Identifiable {
    enum Kind: String, Codable {
        case library
        case custom
    }

    let id: UUID
    let name: String
    let kind: Kind
    let libraryId: String?
}

struct PersistedBagState: Codable {
    var entries: [PersistedBagEntry]
    var selectedReferenceID: UUID?
}

enum BagPersistence {
    private static let stateKey = "discvis.bag.state"

    static func loadState() -> PersistedBagState {
        guard
            let data = UserDefaults.standard.data(forKey: stateKey),
            let state = try? JSONDecoder().decode(PersistedBagState.self, from: data)
        else {
            return PersistedBagState(entries: [], selectedReferenceID: nil)
        }
        return state
    }

    static func saveState(_ state: PersistedBagState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}

enum DiscImageStore {
    static let cropSize = 675

    private static var imagesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiscVis/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func imageURL(for id: UUID) -> URL {
        imagesDirectory.appendingPathComponent("\(id.uuidString).png")
    }

    @discardableResult
    static func saveCroppedDiscImage(_ image: UIImage, id: UUID) throws -> Data {
        let cropped = DiscImageProcessor.cropToDiscSquare(image)
        guard let data = cropped.pngData() else {
            throw DiscImageStoreError.encodingFailed
        }
        try data.write(to: imageURL(for: id), options: .atomic)
        return data
    }

    static func loadImage(for id: UUID) -> UIImage? {
        let url = imageURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func deleteImage(for id: UUID) {
        try? FileManager.default.removeItem(at: imageURL(for: id))
    }
}

enum DiscImageStoreError: Error {
    case encodingFailed
}
