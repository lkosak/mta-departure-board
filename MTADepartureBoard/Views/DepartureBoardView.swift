import SwiftUI

struct DepartureBoardView: View {
    @EnvironmentObject var store: AppStore
    @State private var showingStationPicker = false
    @State private var selectedLine: LineDetailTarget?
    @State private var selectedTrip: TripDetailTarget?

    var body: some View {
        NavigationStack {
            List {
                // Manually pinned feeds
                ForEach(store.watchedFeeds) { feed in
                    FeedCardView(
                        feed: feed,
                        departures: store.departures[feed.id] ?? [],
                        alerts: store.alerts[feed.id] ?? [],
                        onTap: {
                            selectedLine = LineDetailTarget(line: feed.line,
                                                            stationName: feed.stationName,
                                                            feeds: [feed])
                        },
                        onSelectDeparture: { departure in
                            selectedTrip = TripDetailTarget(feed: feed, departure: departure)
                        }
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
                    NearbyStationsView(onSelectLine: { selectedLine = $0 })
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
            .navigationDestination(item: $selectedLine) { target in
                LineDetailView(target: target)
            }
            .sheet(isPresented: $showingStationPicker) {
                StationPickerView()
            }
            .sheet(item: $selectedTrip) { trip in
                TripStopsView(target: trip)
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
