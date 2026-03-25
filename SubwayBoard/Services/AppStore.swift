import Foundation
import SwiftUI
import WidgetKit

@MainActor
class AppStore: ObservableObject {
    @Published var stations: [Station] = []
    @Published var watchedFeeds: [WatchedFeed] = []
    @Published var departures: [UUID: [Departure]] = [:]
    @Published var isLoadingStations = false
    @Published var isLoadingDepartures = false
    @Published var error: String?

    private var refreshTimer: Timer?

    init() {
        watchedFeeds = SharedDefaults.loadFeeds()
    }

    func loadStations() async {
        isLoadingStations = true
        defer { isLoadingStations = false }

        do {
            stations = try await GTFSStaticService.shared.loadStations()
        } catch {
            self.error = "Failed to load stations: \(error.localizedDescription)"
        }
    }

    func addFeed(_ feed: WatchedFeed) {
        watchedFeeds.append(feed)
        SharedDefaults.saveFeeds(watchedFeeds)
        Task { await refreshDepartures() }
    }

    func removeFeed(at offsets: IndexSet) {
        let ids = offsets.map { watchedFeeds[$0].id }
        watchedFeeds.remove(atOffsets: offsets)
        for id in ids { departures[id] = nil }
        SharedDefaults.saveFeeds(watchedFeeds)
    }

    func moveFeeds(from source: IndexSet, to destination: Int) {
        watchedFeeds.move(fromOffsets: source, toOffset: destination)
        SharedDefaults.saveFeeds(watchedFeeds)
    }

    func refreshDepartures() async {
        guard !watchedFeeds.isEmpty else { return }
        isLoadingDepartures = true
        defer { isLoadingDepartures = false }

        // Ensure station name map is populated (needed for destination lookups)
        if stations.isEmpty {
            try? await GTFSStaticService.shared.loadStations()
        }

        departures = await MTAFeedService.fetchDeparturesForAllFeeds(watchedFeeds)

        // Cache departures for widget
        let now = Date()
        var cached: [UUID: [CachedDeparture]] = [:]
        for (id, deps) in departures {
            cached[id] = deps.map { CachedDeparture(from: $0, now: now) }
        }
        SharedDefaults.saveDepartures(cached)
        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivityManager.shared.updateAll(departures: cached)
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshDepartures()
            }
        }
        Task { await refreshDepartures() }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
