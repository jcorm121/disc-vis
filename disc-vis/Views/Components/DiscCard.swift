import SwiftUI

struct DiscCard: View {
    let name: String
    let imageName: String
    var isSelected = false

    init(disc: LibraryDisc, isSelected: Bool = false) {
        name = disc.name
        imageName = disc.id
        self.isSelected = isSelected
    }

    init(name: String, imageName: String, isSelected: Bool = false) {
        self.name = name
        self.imageName = imageName
        self.isSelected = isSelected
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(DiscTheme.cardRing, lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? DiscTheme.orange : .clear, lineWidth: 3)
                }
                .shadow(color: DiscTheme.shadow.opacity(isSelected ? 1.6 : 1), radius: isSelected ? 10 : 4, y: 3)
                .scaleEffect(isSelected ? 1.05 : 1)

            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary.opacity(0.85))
        }
        .padding(.vertical, 8)
        .animation(.smooth(duration: 0.25), value: isSelected)
    }
}
