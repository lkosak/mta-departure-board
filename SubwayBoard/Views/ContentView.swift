import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.watchedFeeds.isEmpty {
            StationPickerView()
        } else {
            DepartureBoardView()
        }
    }
}
