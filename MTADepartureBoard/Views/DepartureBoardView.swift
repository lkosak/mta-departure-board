import SwiftUI

struct DepartureBoardView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingStationPicker = false

    var body: some View {
        NavigationStack {
            List {
                // Manually pinned feeds
                ForEach(store.watchedFeeds) { feed in
                    FeedCardView(
                        feed: feed,
                        departures: store.departures[feed.id] ?? []
                    )
                    .listRowBackground(Color.black)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                }
                .onDelete { offsets in
                    store.removeFeed(at: offsets)
                }
                .onMove { from, to in
                    store.moveFeeds(from: from, to: to)
                }

                // Nearby stations section — shown when location is available
                if !store.nearbyStations.isEmpty {
                    NearbyStationsView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.black)
                        .listRowSeparator(.hidden)
                }
            }
            .refreshable {
                await store.refreshDepartures()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Departures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingStationPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingStationPicker) {
                StationPickerView()
            }
        }
        .onAppear {
            store.startAutoRefresh()
            store.locationService.requestPermissionAndStart()
        }
        .onDisappear {
            store.stopAutoRefresh()
        }
    }
}
