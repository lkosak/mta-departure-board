import Combine
import CoreLocation
import Foundation
import SwiftUI
import WidgetKit

struct NearbyStation {
    let station: Station
    let distance: Double  // meters
    let feeds: [WatchedFeed]
}

@MainActor
class AppStore: ObservableObject {
    @Published var stations: [Station] = []
    @Published var watchedFeeds: [WatchedFeed] = []
    @Published var departures: [UUID: [Departure]] = [:]
    @Published var isLoadingStations = false
    @Published var isLoadingDepartures = false
    @Published var error: String?

    // Nearby stations (within ~1/4 mile)
    let locationService = LocationService()
    @Published var nearbyStations: [NearbyStation] = []
    @Published var nearbyStationDepartures: [UUID: [Departure]] = [:]

    private static let nearbyRadiusMeters: Double = 402  // 1/4 mile
    private static let lineOrder = ["1","2","3","4","5","6","7","A","C","E","B","D","F","M","G","J","Z","L","N","Q","R","W","S"]

    private var refreshTimer: Timer?
    private var locationCancellable: AnyCancellable?

    init() {
        watchedFeeds = SharedDefaults.loadFeeds()
        locationCancellable = locationService.$location
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.updateNearbyStations(for: location)
            }
    }

    func loadStations() async {
        isLoadingStations = true
        defer { isLoadingStations = false }

        do {
            stations = try await GTFSStaticService.shared.loadStations()
            if let location = locationService.location {
                updateNearbyStations(for: location)
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
        guard !watchedFeeds.isEmpty || !nearbyStations.isEmpty else { return }
        isLoadingDepartures = true
        defer { isLoadingDepartures = false }

        if stations.isEmpty {
            await loadStations()
        }

        let nearbyFeeds = nearbyStations.flatMap(\.feeds)

        async let userFeedResults = watchedFeeds.isEmpty
            ? [UUID: [Departure]]()
            : MTAFeedService.fetchDeparturesForAllFeeds(watchedFeeds)
        async let nearbyResults = nearbyFeeds.isEmpty
            ? [UUID: [Departure]]()
            : MTAFeedService.fetchDeparturesForAllFeeds(nearbyFeeds)

        let (userDeps, nearbyDeps) = await (userFeedResults, nearbyResults)

        departures = userDeps
        nearbyStationDepartures = nearbyDeps

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

    // MARK: - Nearby Stations

    private func updateNearbyStations(for location: CLLocation) {
        guard !stations.isEmpty else { return }

        let candidates: [(station: Station, distance: Double)] = stations
            .filter { $0.latitude != nil && $0.longitude != nil }
            .compactMap { station in
                let stationLoc = CLLocation(latitude: station.latitude!, longitude: station.longitude!)
                let distance = location.distance(from: stationLoc)
                return distance <= Self.nearbyRadiusMeters ? (station, distance) : nil
            }
            .sorted { $0.distance < $1.distance }

        let newIds = Set(candidates.map { $0.station.id })
        let oldIds = Set(nearbyStations.map { $0.station.id })

        if newIds != oldIds {
            // Station set changed — rebuild feeds and refetch departures
            nearbyStations = candidates.map { pair in
                NearbyStation(station: pair.station, distance: pair.distance,
                              feeds: buildFeeds(for: pair.station))
            }
            nearbyStationDepartures = [:]
            Task { await refreshNearbyDepartures() }
        } else {
            // Same stations — just update distances, preserve existing feed UUIDs
            let feedsByStationId = Dictionary(uniqueKeysWithValues: nearbyStations.map { ($0.station.id, $0.feeds) })
            nearbyStations = candidates.map { pair in
                NearbyStation(station: pair.station, distance: pair.distance,
                              feeds: feedsByStationId[pair.station.id] ?? buildFeeds(for: pair.station))
            }
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

    private func refreshNearbyDepartures() async {
        let allFeeds = nearbyStations.flatMap(\.feeds)
        guard !allFeeds.isEmpty else { return }
        nearbyStationDepartures = await MTAFeedService.fetchDeparturesForAllFeeds(allFeeds)
    }
}
