import Foundation
import SwiftProtobuf

struct MTAFeedService {
    private static let feedURLs: [String: String] = [
        "1": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
        "2": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
        "3": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
        "4": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
        "5": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
        "6": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
        "A": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
        "C": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
        "E": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace",
        "B": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
        "D": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
        "F": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
        "M": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm",
        "G": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g",
        "J": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz",
        "Z": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz",
        "L": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l",
        "N": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
        "Q": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
        "R": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
        "W": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw",
        "7": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-7",
        "S": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs",
    ]

    /// Route IDs we can draw a bullet for, in the order riders expect them.
    private static let displayLines = ["1","2","3","4","5","6","7","A","C","E","B","D","F","M","G","J","Z","L","N","Q","R","W","S"]
    /// GTFS gives the shuttles their own route IDs; riders just see an S.
    private static let shuttleRouteIds: Set<String> = ["GS", "FS", "H", "SS"]

    static func feedURL(forLine line: String) -> URL? {
        feedURLs[line].flatMap { URL(string: $0) }
    }

    static func fetchDepartures(for feed: WatchedFeed) async throws -> [Departure] {
        guard let url = feedURL(forLine: feed.line) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let message = try TransitRealtime_FeedMessage(serializedBytes: [UInt8](data))
        return departures(from: message, for: feed)
    }

    /// Pull every upcoming train for one feed out of a parsed realtime message,
    /// carrying along the rest of each trip so we can answer "when does this
    /// train reach station X?".
    private static func departures(from message: TransitRealtime_FeedMessage,
                                   for feed: WatchedFeed,
                                   now: TimeInterval = Date().timeIntervalSince1970) -> [Departure] {
        var departures: [Departure] = []

        for entity in message.entity {
            guard entity.hasTripUpdate else { continue }
            let trip = entity.tripUpdate
            guard trip.trip.routeID.hasPrefix(feed.line) else { continue }

            for (index, stopTime) in trip.stopTimeUpdate.enumerated() {
                guard stopTime.stopID == feed.directionStopId else { continue }
                guard let arrivalTime = stopTime.scheduledTime else { continue }

                let seconds = Double(arrivalTime) - now
                guard seconds >= 0 else { continue }

                departures.append(Departure(
                    line: feed.line,
                    destination: lastStopName(for: trip, line: feed.line),
                    minutes: Int(seconds / 60.0),
                    arrivalDate: Date(timeIntervalSince1970: Double(arrivalTime)),
                    tripId: trip.trip.tripID,
                    remainingStops: remainingStops(of: trip, after: index, line: feed.line)
                ))
            }
        }

        return departures.sorted { $0.minutes < $1.minutes }
    }

    /// The stops this train serves after the one you'd board at, in order.
    private static func remainingStops(of tripUpdate: TransitRealtime_TripUpdate,
                                       after index: Int,
                                       line: String) -> [TripStop] {
        tripUpdate.stopTimeUpdate.dropFirst(index + 1).compactMap { stopTime in
            guard let arrivalTime = stopTime.scheduledTime else { return nil }
            let stopId = stopTime.stopID
            let prefix = (stopId.hasSuffix("N") || stopId.hasSuffix("S")) ? String(stopId.dropLast()) : stopId
            return TripStop(
                stopId: stopId,
                stationName: GTFSStaticService.stationName(forStopPrefix: prefix) ?? stopId,
                transferLines: transfers(from: GTFSStaticService.lines(forStopPrefix: prefix), excluding: line),
                arrivalDate: Date(timeIntervalSince1970: Double(arrivalTime))
            )
        }
    }

    /// Lines a rider could change to at a stop: the train's own line dropped,
    /// shuttles folded into S, anything we can't render (SIR, bus routes) skipped.
    private static func transfers(from routes: [String], excluding line: String) -> [String] {
        var result: Set<String> = []
        for route in routes {
            let normalized = shuttleRouteIds.contains(route) ? "S" : route
            guard normalized != line, displayLines.contains(normalized) else { continue }
            result.insert(normalized)
        }
        return displayLines.filter { result.contains($0) }
    }

    private static func lastStopName(for tripUpdate: TransitRealtime_TripUpdate, line: String) -> String {
        guard let lastStop = tripUpdate.stopTimeUpdate.last else { return line }
        let stopId = lastStop.stopID

        // Try exact stop ID first, then stripped prefix
        if let name = GTFSStaticService.stationName(forStopPrefix: stopId) {
            return name
        }
        if stopId.hasSuffix("N") || stopId.hasSuffix("S") {
            if let name = GTFSStaticService.stationName(forStopPrefix: String(stopId.dropLast())) {
                return name
            }
        }

        // Fallback: try to extract destination from trip_id
        // MTA trip IDs often end with "..._<destination_stop_id>"
        // or encode the terminal in the last 3 chars
        let tripId = tripUpdate.trip.tripID
        let parts = tripId.components(separatedBy: "_")
        if let lastPart = parts.last, lastPart.count >= 3 {
            let possibleStop = String(lastPart.suffix(3))
            if let name = GTFSStaticService.stationName(forStopPrefix: possibleStop) {
                return name
            }
        }

        return line
    }

    static func fetchDeparturesForAllFeeds(_ feeds: [WatchedFeed]) async -> [UUID: [Departure]] {
        var results: [UUID: [Departure]] = [:]

        let lineGroups = Dictionary(grouping: feeds) { feedURL(forLine: $0.line)?.absoluteString ?? "" }

        for (_, groupFeeds) in lineGroups {
            guard let firstFeed = groupFeeds.first, let url = feedURL(forLine: firstFeed.line) else { continue }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let message = try TransitRealtime_FeedMessage(serializedBytes: [UInt8](data))
                let now = Date().timeIntervalSince1970

                for feed in groupFeeds {
                    results[feed.id] = departures(from: message, for: feed, now: now)
                }
            } catch {
                for feed in groupFeeds {
                    results[feed.id] = []
                }
            }
        }

        return results
    }
}

private extension TransitRealtime_TripUpdate.StopTimeUpdate {
    /// Arrival if the feed gives one, otherwise departure.
    var scheduledTime: Int64? {
        if hasArrival { return arrival.time }
        if hasDeparture { return departure.time }
        return nil
    }
}
