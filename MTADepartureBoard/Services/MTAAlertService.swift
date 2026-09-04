import Foundation
import SwiftProtobuf

/// Fetches the MTA subway service-alerts feed (one feed covers every line) and
/// matches alerts to watched feeds by route, station and direction.
actor MTAAlertService {
    static let shared = MTAAlertService()

    private static let feedURL = URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts")!
    private static let cacheTTL: TimeInterval = 180

    private struct Selector {
        let routeId: String
        let stopId: String?
        /// GTFS direction_id: 0 = north/uptown, 1 = south/downtown. Nil applies to both.
        let directionId: UInt32?
    }

    private struct ParsedAlert {
        let id: String
        let header: String
        let details: String?
        let postedAt: Date?
        let alertType: String?
        let selectors: [Selector]
        let activePeriods: [(start: Date?, end: Date?)]

        func isActive(at date: Date) -> Bool {
            guard !activePeriods.isEmpty else { return true }
            return activePeriods.contains { period in
                let startedOK = period.start.map { $0 <= date } ?? true
                let endedOK = period.end.map { $0 >= date } ?? true
                return startedOK && endedOK
            }
        }
    }

    private var cached: [ParsedAlert] = []
    private var lastFetch: Date?

    /// Returns the currently-active alerts for each feed, keyed by feed id.
    /// Feeds with no alerts are omitted.
    func alerts(for feeds: [WatchedFeed]) async -> [UUID: [ServiceAlert]] {
        let alerts = await loadAlerts()
        guard !alerts.isEmpty else { return [:] }

        let now = Date()
        let active = alerts.filter { $0.isActive(at: now) }

        var result: [UUID: [ServiceAlert]] = [:]
        for feed in feeds {
            let feedAlerts = active.filter { self.matches($0, feed: feed) }
            guard !feedAlerts.isEmpty else { continue }
            result[feed.id] = feedAlerts.map {
                ServiceAlert(id: $0.id, header: $0.header, details: $0.details, postedAt: $0.postedAt,
                             alertType: $0.alertType)
            }
        }
        return result
    }

    private func loadAlerts() async -> [ParsedAlert] {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < Self.cacheTTL {
            return cached
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: Self.feedURL)
            let message = try TransitRealtime_FeedMessage(serializedBytes: [UInt8](data))
            cached = message.entity.compactMap(Self.parse)
            lastFetch = Date()
        } catch {
            // Keep whatever we had; alerts are supplementary to departures.
        }
        return cached
    }

    private nonisolated static func parse(_ entity: TransitRealtime_FeedEntity) -> ParsedAlert? {
        guard entity.hasAlert else { return nil }
        let alert = entity.alert

        guard let header = englishText(alert.hasHeaderText ? alert.headerText : nil),
              !header.isEmpty else { return nil }

        let mercury = varintScan(alert.unknownFields.data, forField: Self.mercuryAlertField)?.bytes

        let selectors: [Selector] = alert.informedEntity.compactMap { selector in
            guard selector.hasRouteID, !selector.routeID.isEmpty else { return nil }
            return Selector(
                routeId: selector.routeID,
                stopId: selector.hasStopID && !selector.stopID.isEmpty ? selector.stopID : nil,
                directionId: selector.hasDirectionID ? selector.directionID : nil
            )
        }
        guard !selectors.isEmpty else { return nil }

        let periods = alert.activePeriod.map { range in
            (start: range.hasStart ? Date(timeIntervalSince1970: Double(range.start)) : nil,
             end: range.hasEnd ? Date(timeIntervalSince1970: Double(range.end)) : nil)
        }

        return ParsedAlert(
            id: entity.id,
            header: header,
            details: englishText(alert.hasDescriptionText ? alert.descriptionText : nil),
            postedAt: mercury.flatMap { varintScan($0, forField: 1)?.varint }
                .map { Date(timeIntervalSince1970: Double($0)) },
            alertType: mercury.flatMap { varintScan($0, forField: 3)?.bytes }
                .flatMap { String(data: $0, encoding: .utf8) },
            selectors: selectors,
            activePeriods: periods
        )
    }

    /// The MTA's Mercury extension carries what the standard GTFS-realtime Alert message
    /// lacks: subfield 1 is created_at, subfield 3 the alert type ("Delays"). MTA leaves
    /// the standard effect/cause fields unset, so this is the only source for the type.
    /// Read from unknown fields rather than pulling in the camsys proto for two values.
    private nonisolated static let mercuryAlertField = 1001

    /// Minimal protobuf wire-format scan for a single top-level field.
    private nonisolated static func varintScan(_ data: Data, forField field: Int) -> (varint: UInt64, bytes: Data)? {
        var index = data.startIndex

        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < data.endIndex {
                let byte = data[index]
                index = data.index(after: index)
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }

        while index < data.endIndex {
            guard let key = readVarint() else { return nil }
            let fieldNumber = Int(key >> 3)
            let wireType = key & 0x7

            switch wireType {
            case 0:
                guard let value = readVarint() else { return nil }
                if fieldNumber == field { return (value, Data()) }
            case 1, 5:
                let width = wireType == 1 ? 8 : 4
                guard data.distance(from: index, to: data.endIndex) >= width else { return nil }
                index = data.index(index, offsetBy: width)
            case 2:
                guard let length = readVarint(),
                      data.distance(from: index, to: data.endIndex) >= Int(length) else { return nil }
                let end = data.index(index, offsetBy: Int(length))
                if fieldNumber == field { return (0, Data(data[index..<end])) }
                index = end
            default:
                return nil  // Groups — not used by this feed.
            }
        }
        return nil
    }

    /// Picks the plain-text English translation, ignoring the "en-html" variant.
    private nonisolated static func englishText(_ translated: TransitRealtime_TranslatedString?) -> String? {
        guard let translated else { return nil }
        let translations = translated.translation
        let english = translations.first { $0.hasLanguage && $0.language == "en" }
            ?? translations.first { !$0.hasLanguage || !$0.language.contains("html") }
            ?? translations.first
        let text = english?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }

    /// Alert route ids are exact ("L", "6"), with express variants ("6X", "7X")
    /// and named shuttles ("GS", "FS", "H") as separate routes.
    private nonisolated static func route(_ routeId: String, matches line: String) -> Bool {
        if routeId == line || routeId == line + "X" { return true }
        if line == "S" { return ["GS", "FS", "H"].contains(routeId) }
        return false
    }

    private nonisolated func matches(_ alert: ParsedAlert, feed: WatchedFeed) -> Bool {
        // Alerts reference the parent stop id ("L06"), feeds the directional one ("L06N").
        let stopPrefix = String(feed.directionStopId.dropLast())
        let feedDirectionId: UInt32 = feed.direction == .uptown ? 0 : 1

        return alert.selectors.contains { selector in
            guard Self.route(selector.routeId, matches: feed.line) else { return false }
            if let stopId = selector.stopId, stopId != stopPrefix { return false }
            if let directionId = selector.directionId, directionId != feedDirectionId { return false }
            return true
        }
    }
}
