import SwiftUI

@main
struct SubwayBoardApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var liveActivityManager = LiveActivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(liveActivityManager)
                .preferredColorScheme(.dark)
        }
    }
}
