import SwiftUI

@main
struct ZAssistApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .tint(.blue)
        }
    }
}
