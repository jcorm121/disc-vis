import Foundation

enum HeatmapPalette: Int, CaseIterable, Identifiable {
    case whiteHot = 0
    case blackHot = 1
    case redHot = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .whiteHot: "White"
        case .blackHot: "Black"
        case .redHot: "Red"
        }
    }
}
