import Foundation

/// A stop a train will make later in its trip, as reported by the realtime feed.
struct TripStop: Identifiable, Hashable {
    let stopId: String
    let stationName: String
    /// Lines serving this station, for transfer hints. Excludes the train's own line.
    let transferLines: [String]
    let arrivalDate: Date

    var id: String { stopId }

    var minutesFromNow: Int {
        max(0, Int(arrivalDate.timeIntervalSinceNow / 60))
    }
}

struct Departure: Identifiable {
    let id = UUID()
    let line: String
    let destination: String
    let minutes: Int
    let arrivalDate: Date
    /// GTFS trip ID — identifies this specific train across refreshes.
    var tripId: String = ""
    /// Every stop after the one you'd board at, in order.
    var remainingStops: [TripStop] = []
}
