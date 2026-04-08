import Foundation
import Compression

actor GTFSStaticService {
    static let shared = GTFSStaticService()

    private static let gtfsURL = URL(string: "http://web.mta.info/developers/data/nyct/subway/google_transit.zip")!
    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTFSData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var stations: [Station] = []
    private var stationsByPrefix: [String: Station] = [:]
    private var loaded = false

    nonisolated(unsafe) private static var _stationNameMap: [String: String] = [:]

    static func stationName(forStopPrefix prefix: String) -> String? {
        _stationNameMap[prefix]
    }

    func loadStations() async throws -> [Station] {
        if loaded { return stations }

        let stopsFile = Self.cacheDir.appendingPathComponent("stops.txt")
        let routesFile = Self.cacheDir.appendingPathComponent("routes.txt")

        if !FileManager.default.fileExists(atPath: stopsFile.path) {
            try await downloadAndExtract()
        }

        let stopsData = try String(contentsOf: stopsFile, encoding: .utf8)
        let routesData = try String(contentsOf: routesFile, encoding: .utf8)
        let tripsFile = Self.cacheDir.appendingPathComponent("trips.txt")
        let stopTimesFile = Self.cacheDir.appendingPathComponent("stop_times.txt")
        let tripsData = try String(contentsOf: tripsFile, encoding: .utf8)
        let stopTimesData = try String(contentsOf: stopTimesFile, encoding: .utf8)

        let routes = parseRoutes(routesData)
        let stopRoutes = buildStopRoutesMap(tripsCSV: tripsData, stopTimesCSV: stopTimesData)
        stations = parseStops(stopsData, routes: routes, stopRoutes: stopRoutes)
        stationsByPrefix = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        loaded = true

        // Map every stop prefix to the station name (for destination lookups)
        // Build from raw stops.txt so we cover parent stops too
        Self._stationNameMap = buildStopNameMap(stopsCSV: stopsData)

        return stations
    }

    private func downloadAndExtract() async throws {
        let (data, _) = try await URLSession.shared.data(from: Self.gtfsURL)
        try extractZip(data: data, to: Self.cacheDir)
    }

    private func extractZip(data: Data, to directory: URL) throws {
        // Minimal ZIP extraction — handles local file headers for uncompressed and deflated entries
        var offset = 0
        while offset + 30 <= data.count {
            // Check local file header signature: PK\x03\x04
            guard data[offset] == 0x50, data[offset+1] == 0x4B,
                  data[offset+2] == 0x03, data[offset+3] == 0x04 else { break }

            let compressionMethod = UInt16(data[offset+8]) | (UInt16(data[offset+9]) << 8)
            let compressedSize = Int(UInt32(data[offset+18]) | (UInt32(data[offset+19]) << 8) | (UInt32(data[offset+20]) << 16) | (UInt32(data[offset+21]) << 24))
            let uncompressedSize = Int(UInt32(data[offset+22]) | (UInt32(data[offset+23]) << 8) | (UInt32(data[offset+24]) << 16) | (UInt32(data[offset+25]) << 24))
            let nameLength = Int(UInt16(data[offset+26]) | (UInt16(data[offset+27]) << 8))
            let extraLength = Int(UInt16(data[offset+28]) | (UInt16(data[offset+29]) << 8))

            let nameStart = offset + 30
            let nameData = data[nameStart..<nameStart+nameLength]
            let fileName = String(data: nameData, encoding: .utf8) ?? ""

            let dataStart = nameStart + nameLength + extraLength

            if !fileName.hasSuffix("/") && compressedSize > 0 {
                let compressedData = data[dataStart..<dataStart+compressedSize]

                let fileData: Data
                if compressionMethod == 0 {
                    // Stored (no compression)
                    fileData = Data(compressedData)
                } else if compressionMethod == 8 {
                    // Deflated — use Apple's Compression framework
                    let src = Array(compressedData)
                    var dest = [UInt8](repeating: 0, count: uncompressedSize)
                    let decodedSize = compression_decode_buffer(
                        &dest, uncompressedSize,
                        src, src.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                    guard decodedSize > 0 else { continue }
                    fileData = Data(dest.prefix(decodedSize))
                } else {
                    // Unsupported compression
                    offset = dataStart + compressedSize
                    continue
                }

                let filePath = directory.appendingPathComponent((fileName as NSString).lastPathComponent)
                try fileData.write(to: filePath)
            }

            offset = dataStart + compressedSize
        }
    }

    private func parseRoutes(_ csv: String) -> [String: String] {
        let lines = csv.components(separatedBy: "\n")
        guard let header = lines.first else { return [:] }
        let cols = header.components(separatedBy: ",")
        guard let idIdx = cols.firstIndex(of: "route_id"),
              let nameIdx = cols.firstIndex(of: "route_short_name") ?? cols.firstIndex(of: "route_long_name")
        else { return [:] }

        var routes: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let fields = parseCSVLine(line)
            if idIdx < fields.count && nameIdx < fields.count {
                routes[fields[idIdx]] = fields[nameIdx]
            }
        }
        return routes
    }

    /// Build a map of stop_id_prefix → Set<route_id> using trips.txt + stop_times.txt
    private func buildStopRoutesMap(tripsCSV: String, stopTimesCSV: String) -> [String: Set<String>] {
        // Parse trips.txt: trip_id → route_id
        let tripLines = tripsCSV.components(separatedBy: "\n")
        guard let tripHeader = tripLines.first else { return [:] }
        let tripCols = tripHeader.components(separatedBy: ",")
        guard let tripIdIdx = tripCols.firstIndex(of: "trip_id"),
              let routeIdIdx = tripCols.firstIndex(of: "route_id")
        else { return [:] }

        var tripToRoute: [String: String] = [:]
        for line in tripLines.dropFirst() where !line.isEmpty {
            let fields = parseCSVLine(line)
            guard tripIdIdx < fields.count, routeIdIdx < fields.count else { continue }
            tripToRoute[fields[tripIdIdx]] = fields[routeIdIdx]
        }

        // Parse stop_times.txt: collect route_ids per stop_id prefix
        let stLines = stopTimesCSV.components(separatedBy: "\n")
        guard let stHeader = stLines.first else { return [:] }
        let stCols = stHeader.components(separatedBy: ",")
        guard let stTripIdx = stCols.firstIndex(of: "trip_id"),
              let stStopIdx = stCols.firstIndex(of: "stop_id")
        else { return [:] }

        var result: [String: Set<String>] = [:]
        for line in stLines.dropFirst() where !line.isEmpty {
            let fields = parseCSVLine(line)
            guard stTripIdx < fields.count, stStopIdx < fields.count else { continue }
            let tripId = fields[stTripIdx]
            let stopId = fields[stStopIdx]
            guard let routeId = tripToRoute[tripId] else { continue }

            // Use the stop prefix (without N/S direction suffix)
            let prefix: String
            if stopId.hasSuffix("N") || stopId.hasSuffix("S") {
                prefix = String(stopId.dropLast())
            } else {
                prefix = stopId
            }
            result[prefix, default: []].insert(routeId)
        }

        return result
    }

    private func parseStops(_ csv: String, routes: [String: String], stopRoutes: [String: Set<String>]) -> [Station] {
        let lines = csv.components(separatedBy: "\n")
        guard let header = lines.first else { return [] }
        let cols = header.components(separatedBy: ",")
        guard let idIdx = cols.firstIndex(of: "stop_id"),
              let nameIdx = cols.firstIndex(of: "stop_name")
        else { return [] }

        // Also look for parent_station and coordinate columns
        let parentIdx = cols.firstIndex(of: "parent_station")
        let latIdx = cols.firstIndex(of: "stop_lat")
        let lonIdx = cols.firstIndex(of: "stop_lon")

        // First pass: build parent→name map, collect directional stops, and gather coordinates
        var parentNames: [String: String] = [:]  // parentId → name
        var parentStopIds: [String: Set<String>] = [:]  // parentId → set of directional stop IDs
        var parentCoords: [String: [(Double, Double)]] = [:]  // parentId → [(lat, lon)]

        for line in lines.dropFirst() where !line.isEmpty {
            let fields = parseCSVLine(line)
            guard idIdx < fields.count, nameIdx < fields.count else { continue }
            let stopId = fields[idIdx]
            let name = fields[nameIdx]
            let parent = (parentIdx != nil && parentIdx! < fields.count) ? fields[parentIdx!] : ""

            let lat = latIdx.flatMap { $0 < fields.count ? Double(fields[$0]) : nil }
            let lon = lonIdx.flatMap { $0 < fields.count ? Double(fields[$0]) : nil }

            if stopId.hasSuffix("N") || stopId.hasSuffix("S") {
                // Directional stop — group under its parent (or its own prefix if no parent)
                let groupKey = parent.isEmpty ? String(stopId.dropLast()) : parent
                parentStopIds[groupKey, default: []].insert(stopId)
                if parentNames[groupKey] == nil {
                    parentNames[groupKey] = name
                }
                if let lat, let lon {
                    parentCoords[groupKey, default: []].append((lat, lon))
                }
            } else if parent.isEmpty {
                // This is a parent stop itself — record its name and coordinates
                parentNames[stopId] = name
                if let lat, let lon {
                    parentCoords[stopId, default: []].append((lat, lon))
                }
            }
        }

        // Build stations from parent groups
        var stationsList = parentStopIds.map { parentId, stopIds -> Station in
            let name = parentNames[parentId] ?? parentId

            // Collect routes from all prefixes in this group, and map line → stop prefix
            var stationRoutes: Set<String> = []
            var lineToStopPrefix: [String: String] = [:]
            let prefixes = Set(stopIds.map { String($0.dropLast()) })
            for prefix in prefixes {
                if let r = stopRoutes[prefix] {
                    stationRoutes.formUnion(r)
                    for route in r {
                        lineToStopPrefix[route] = prefix
                    }
                }
            }

            // Average coordinates across all directional stops
            let coords = parentCoords[parentId] ?? []
            let latitude = coords.isEmpty ? nil : coords.map(\.0).reduce(0, +) / Double(coords.count)
            let longitude = coords.isEmpty ? nil : coords.map(\.1).reduce(0, +) / Double(coords.count)

            return Station(
                id: parentId,
                name: name,
                lines: stationRoutes.sorted(),
                stopIds: stopIds.sorted(),
                latitude: latitude,
                longitude: longitude,
                lineToStopPrefix: lineToStopPrefix
            )
        }

        // Disambiguate stations that share the same name by appending their lines
        let nameCounts = Dictionary(grouping: stationsList, by: { $0.name })
        for (name, group) in nameCounts where group.count > 1 {
            for station in group {
                guard let idx = stationsList.firstIndex(where: { $0.id == station.id }) else { continue }
                let lineSuffix = station.lines.isEmpty ? "" : " (\(station.lines.joined(separator: "/")))"
                stationsList[idx] = Station(
                    id: station.id,
                    name: name + lineSuffix,
                    lines: station.lines,
                    stopIds: station.stopIds,
                    latitude: station.latitude,
                    longitude: station.longitude,
                    lineToStopPrefix: station.lineToStopPrefix
                )
            }
        }

        return stationsList.sorted { $0.name < $1.name }
    }

    /// Build a comprehensive stop_id/prefix → name map from stops.txt
    private func buildStopNameMap(stopsCSV: String) -> [String: String] {
        let lines = stopsCSV.components(separatedBy: "\n")
        guard let header = lines.first else { return [:] }
        let cols = header.components(separatedBy: ",")
        guard let idIdx = cols.firstIndex(of: "stop_id"),
              let nameIdx = cols.firstIndex(of: "stop_name")
        else { return [:] }

        var map: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let fields = parseCSVLine(line)
            guard idIdx < fields.count, nameIdx < fields.count else { continue }
            let stopId = fields[idIdx]
            let name = fields[nameIdx]

            // Map the raw stop_id (e.g. "D20", "D20N", "D20S")
            map[stopId] = name
            // Also map the prefix without direction suffix
            if stopId.hasSuffix("N") || stopId.hasSuffix("S") {
                map[String(stopId.dropLast())] = name
            }
        }
        return map
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
