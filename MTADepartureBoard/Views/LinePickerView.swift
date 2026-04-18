import SwiftUI

struct LinePickerView: View {
    @EnvironmentObject var store: AppStore
    let station: Station
    var onAdd: (() -> Void)?

    // Display order for lines
    private let lineOrder = ["1","2","3","4","5","6","7","A","C","E","B","D","F","M","G","J","Z","L","N","Q","R","W","S"]

    // Only lines that actually serve this station
    private var availableLines: [String] {
        lineOrder.filter { station.lines.contains($0) }
    }

    // Get all stop prefixes for this station
    private var stopPrefixes: [String] {
        Array(Set(station.stopIds.map { String($0.dropLast()) })).sorted()
    }

    private var northStopIds: [String] {
        station.stopIds.filter { $0.hasSuffix("N") }
    }

    private var southStopIds: [String] {
        station.stopIds.filter { $0.hasSuffix("S") }
    }

    // Pick the first matching north stop ID from any prefix at this station
    private func firstNorthStopId() -> String? {
        northStopIds.first
    }

    private func firstSouthStopId() -> String? {
        southStopIds.first
    }

    var body: some View {
        List {
                if !northStopIds.isEmpty {
                    Section("Uptown") {
                        ForEach(availableLines, id: \.self) { line in
                            if let stopId = firstNorthStopId() {
                                Button {
                                    addFeed(line: line, direction: .uptown, directionStopId: stopId)
                                } label: {
                                    HStack(spacing: 12) {
                                        LineBullet(line: line, size: 28)
                                        Text(line)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }

                if !southStopIds.isEmpty {
                    Section("Downtown") {
                        ForEach(availableLines, id: \.self) { line in
                            if let stopId = firstSouthStopId() {
                                Button {
                                    addFeed(line: line, direction: .downtown, directionStopId: stopId)
                                } label: {
                                    HStack(spacing: 12) {
                                        LineBullet(line: line, size: 28)
                                        Text(line)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
        }
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addFeed(line: String, direction: WatchedFeed.Direction, directionStopId: String) {
        let feed = WatchedFeed(
            id: UUID(),
            stationId: station.id,
            stationName: station.name,
            line: line,
            directionStopId: directionStopId,
            direction: direction
        )
        store.addFeed(feed)
        onAdd?()
    }
}
