import SwiftUI

struct StationPickerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var path = NavigationPath()

    private var isModal: Bool {
        !store.watchedFeeds.isEmpty
    }

    var filteredStations: [Station] {
        if searchText.isEmpty {
            return store.stations
        }
        return store.stations.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.isLoadingStations {
                    ProgressView("Loading stations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.stations.isEmpty {
                    ContentUnavailableView(
                        "No Stations",
                        systemImage: "tram",
                        description: Text(store.error ?? "Failed to load station data.")
                    )
                } else {
                    List(filteredStations) { station in
                        NavigationLink(value: station) {
                            Text(station.name)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search stations")
                }
            }
            .navigationTitle("Add Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .navigationDestination(for: Station.self) { station in
                LinePickerView(station: station, onAdd: { dismiss() })
            }
        }
        .task {
            if store.stations.isEmpty {
                await store.loadStations()
            }
        }
    }
}
