import ActivityKit
import Foundation

struct SubwayDepartureAttributes: ActivityAttributes {
    struct ContentState: Codable {
        let departures: [CachedDeparture]
        let updatedAt: Date
    }

    /// The watched feed is fixed for the lifetime of the activity.
    let feed: WatchedFeed
}
