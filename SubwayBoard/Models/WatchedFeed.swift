import Foundation

struct WatchedFeed: Identifiable, Codable, Hashable {
    let id: UUID
    let stationId: String
    let stationName: String
    let line: String
    let directionStopId: String
    let direction: Direction

    enum Direction: String, Codable, Hashable {
        case uptown = "Uptown"
        case downtown = "Downtown"

        var label: String { rawValue }
    }
}
