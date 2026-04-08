import Combine
import CoreLocation
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

    // Nearest station
    let locationService = LocationService()
    @Published var nearestStation: Station?
    @Published var nearestStationDistance: Double?
    @Published var nearestStationFeeds: [WatchedFeed] = []
    @Published var nearestStationDepartures: [UUID: [Departure]] = [:]

    private var refreshTimer: Timer?
    private var locationCancellable: AnyCancellable?

    private static let lineOrder = ["1","2","3","4","5","6","7","A","C","E","B","D","F","M","G","J","Z","L","N","Q","R","W","S"]

    init() {
        watchedFeeds = SharedDefaults.loadFeeds()
        locationCancellable = locationService.$location
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.updateNearestStation(for: location)
            }
    }

    func loadStations() async {
        isLoadingStations = true
        defer { isLoadingStations = false }

        do {
            stations = try await GTFSStaticService.shared.loadStations()
            // If we already have a location, find nearest now that stations are loaded
            if let location = locationService.location {
                updateNearestStation(for: location)
            }
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
        guard !watchedFeeds.isEmpty || !nearestStationFeeds.isEmpty else { return }
        isLoadingDepartures = true
        defer { isLoadingDepartures = false }

        // Ensure station name map is populated (needed for destination lookups)
        if stations.isEmpty {
            try? await GTFSStaticService.shared.loadStations()
        }

        async let userFeedResults = watchedFeeds.isEmpty
            ? [UUID: [Departure]]()
            : MTAFeedService.fetchDeparturesForAllFeeds(watchedFeeds)
        async let nearestResults = nearestStationFeeds.isEmpty
            ? [UUID: [Departure]]()
            : MTAFeedService.fetchDeparturesForAllFeeds(nearestStationFeeds)

        let (userDeps, nearestDeps) = await (userFeedResults, nearestResults)

        departures = userDeps
        nearestStationDepartures = nearestDeps

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

    // MARK: - Nearest Station

    private func updateNearestStation(for location: CLLocation) {
        guard !stations.isEmpty else { return }

        let nearest = stations
            .filter { $0.latitude != nil && $0.longitude != nil }
            .min {
                let a = CLLocation(latitude: $0.latitude!, longitude: $0.longitude!)
                let b = CLLocation(latitude: $1.latitude!, longitude: $1.longitude!)
                return location.distance(from: a) < location.distance(from: b)
            }

        guard let nearest else { return }
        let stationLocation = CLLocation(latitude: nearest.latitude!, longitude: nearest.longitude!)
        nearestStationDistance = location.distance(from: stationLocation)

        if nearest.id != nearestStation?.id {
            nearestStation = nearest
            nearestStationFeeds = buildFeeds(for: nearest)
            nearestStationDepartures = [:]
            Task { await refreshNearestStationDepartures() }
        }
    }

    private func buildFeeds(for station: Station) -> [WatchedFeed] {
        var feeds: [WatchedFeed] = []
        let orderedLines = Self.lineOrder.filter { station.lines.contains($0) }
        for line in orderedLines {
            guard let prefix = station.lineToStopPrefix[line] else { continue }
            let northId = prefix + "N"
            let southId = prefix + "S"
            if station.stopIds.contains(northId) {
                feeds.append(WatchedFeed(id: UUID(), stationId: station.id, stationName: station.name,
                                         line: line, directionStopId: northId, direction: .uptown))
            }
            if station.stopIds.contains(southId) {
                feeds.append(WatchedFeed(id: UUID(), stationId: station.id, stationName: station.name,
                                         line: line, directionStopId: southId, direction: .downtown))
            }
        }
        return feeds
    }

    private func refreshNearestStationDepartures() async {
        guard !nearestStationFeeds.isEmpty else { return }
        nearestStationDepartures = await MTAFeedService.fetchDeparturesForAllFeeds(nearestStationFeeds)
    }
}
