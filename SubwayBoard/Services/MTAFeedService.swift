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

    static func feedURL(forLine line: String) -> URL? {
        feedURLs[line].flatMap { URL(string: $0) }
    }

    static func fetchDepartures(for feed: WatchedFeed) async throws -> [Departure] {
        guard let url = feedURL(forLine: feed.line) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let message = try TransitRealtime_FeedMessage(serializedBytes: [UInt8](data))

        let now = Date().timeIntervalSince1970

        var departures: [Departure] = []

        for entity in message.entity {
            guard entity.hasTripUpdate else { continue }
            let trip = entity.tripUpdate
            guard trip.trip.routeID == feed.line else { continue }

            for stopTime in trip.stopTimeUpdate {
                guard stopTime.stopID == feed.directionStopId else { continue }

                let arrivalTime: Int64
                if stopTime.hasArrival {
                    arrivalTime = stopTime.arrival.time
                } else if stopTime.hasDeparture {
                    arrivalTime = stopTime.departure.time
                } else {
                    continue
                }

                let minutes = Int((Double(arrivalTime) - now) / 60.0)
                guard minutes >= 0 else { continue }

                let destination = lastStopName(for: trip, line: feed.line)
                departures.append(Departure(line: feed.line, destination: destination, minutes: minutes))
            }
        }

        return departures.sorted { $0.minutes < $1.minutes }
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
                    var departures: [Departure] = []

                    for entity in message.entity {
                        guard entity.hasTripUpdate else { continue }
                        let trip = entity.tripUpdate
                        guard trip.trip.routeID == feed.line else { continue }

                        for stopTime in trip.stopTimeUpdate {
                            guard stopTime.stopID == feed.directionStopId else { continue }

                            let arrivalTime: Int64
                            if stopTime.hasArrival {
                                arrivalTime = stopTime.arrival.time
                            } else if stopTime.hasDeparture {
                                arrivalTime = stopTime.departure.time
                            } else {
                                continue
                            }

                            let minutes = Int((Double(arrivalTime) - now) / 60.0)
                            guard minutes >= 0 else { continue }

                            let destination = lastStopName(for: trip, line: feed.line)
                            departures.append(Departure(line: feed.line, destination: destination, minutes: minutes))
                        }
                    }

                    results[feed.id] = departures.sorted { $0.minutes < $1.minutes }
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
