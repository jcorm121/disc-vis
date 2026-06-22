import SwiftUI

enum ImageSelectTab: Int, CaseIterable {
    case search
    case bag
    case upload

    var title: String {
        switch self {
        case .search: "Search"
        case .bag: "Bag"
        case .upload: "Upload"
        }
    }
}

struct MainView: View {
    @Environment(DiscStore.self) private var store
    @State private var selectedTab: ImageSelectTab = .search
    @State private var showCamera = false

    var body: some View {
        ZStack {
            if showCamera {
                CameraView {
                    withAnimation(.smooth(duration: 0.4)) {
                        showCamera = false
                    }
                }
            } else {
                imageSelectFlow
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: showCamera)
    }

    private var imageSelectFlow: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                ImageSearchView()
                    .tag(ImageSelectTab.search)

                BagView()
                    .tag(ImageSelectTab.bag)

                ImageUploadView()
                    .tag(ImageSelectTab.upload)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomBar
        }
        .background(DiscTheme.backgroundGradient.ignoresSafeArea())
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            Text(selectedTab.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DiscTheme.orange.opacity(0.8))
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: selectedTab)

            PageIndicator(count: ImageSelectTab.allCases.count, selection: selectedTab.rawValue)

            CameraFAB {
                withAnimation(.smooth(duration: 0.4)) {
                    showCamera = true
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [.clear, DiscTheme.cream.opacity(0.95), .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    MainView()
        .environment(DiscStore())
}
