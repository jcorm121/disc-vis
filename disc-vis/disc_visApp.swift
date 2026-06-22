import SwiftUI

@main
struct disc_visApp: App {
    @State private var store = DiscStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(DiscTheme.orange)
        }
    }
}
