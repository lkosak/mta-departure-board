import Foundation

enum SharedDefaults {
    static let suiteName = "group.io.lou.subwayboard"
    static let feedsKey = "watchedFeeds"
    static let departuresKey = "cachedDepartures"

    static var suite: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func saveFeeds(_ feeds: [WatchedFeed]) {
        if let data = try? JSONEncoder().encode(feeds) {
            suite.set(data, forKey: feedsKey)
        }
    }

    static func loadFeeds() -> [WatchedFeed] {
        guard let data = suite.data(forKey: feedsKey),
              let feeds = try? JSONDecoder().decode([WatchedFeed].self, from: data)
        else { return [] }
        return feeds
    }

    static func saveDepartures(_ departures: [UUID: [CachedDeparture]]) {
        if let data = try? JSONEncoder().encode(departures) {
            suite.set(data, forKey: departuresKey)
        }
    }

    static func loadDepartures() -> [UUID: [CachedDeparture]] {
        guard let data = suite.data(forKey: departuresKey),
              let deps = try? JSONDecoder().decode([UUID: [CachedDeparture]].self, from: data)
        else { return [:] }
        return deps
    }
}

/// Codable version of Departure for sharing via UserDefaults
struct CachedDeparture: Codable, Hashable, Identifiable {
    let id: UUID
    let line: String
    let destination: String
    let arrivalTime: Date

    var minutes: Int {
        max(0, Int(arrivalTime.timeIntervalSinceNow / 60))
    }

    init(from departure: Departure, now: Date = Date()) {
        self.id = departure.id
        self.line = departure.line
        self.destination = departure.destination
        self.arrivalTime = now.addingTimeInterval(Double(departure.minutes) * 60)
    }
}
