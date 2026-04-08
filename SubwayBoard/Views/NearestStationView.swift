import SwiftUI

private struct NearestLineGroup: Identifiable {
    let line: String
    let uptownDepartures: [Departure]
    let downtownDepartures: [Departure]
    var id: String { line }
}

// One card per station in the nearby list
struct NearbyStationsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section label
            HStack(spacing: 5) {
                Image(systemName: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.teal)
                Text("NEARBY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.teal)
                    .kerning(0.5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(store.nearbyStations, id: \.station.id) { nearby in
                NearbyStationCard(nearby: nearby, departures: store.nearbyStationDepartures)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct NearbyStationCard: View {
    let nearby: NearbyStation
    let departures: [UUID: [Departure]]

    private static let lineOrder = ["1","2","3","4","5","6","7","A","C","E","B","D","F","M","G","J","Z","L","N","Q","R","W","S"]

    private var lineGroups: [NearestLineGroup] {
        let lines = Self.lineOrder.filter { line in
            nearby.feeds.contains(where: { $0.line == line })
        }
        return lines.map { line in
            let uptownFeed = nearby.feeds.first { $0.line == line && $0.direction == .uptown }
            let downtownFeed = nearby.feeds.first { $0.line == line && $0.direction == .downtown }
            return NearestLineGroup(
                line: line,
                uptownDepartures: uptownFeed.flatMap { departures[$0.id] } ?? [],
                downtownDepartures: downtownFeed.flatMap { departures[$0.id] } ?? []
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Station header
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.teal.opacity(0.7))
                Text(nearby.station.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(formattedDistance(nearby.distance))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.teal.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()
                .background(Color.teal.opacity(0.2))
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(lineGroups) { group in
                    LineRow(group: group)
                    if group.id != lineGroups.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 4)
                    }
                }
                if lineGroups.isEmpty {
                    Text("No upcoming trains")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 6)
        }
        .background(
            ZStack(alignment: .leading) {
                Color(red: 0.04, green: 0.11, blue: 0.18)
                Rectangle()
                    .fill(Color.teal.opacity(0.55))
                    .frame(width: 3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formattedDistance(_ meters: Double) -> String {
        let feet = meters * 3.28084
        if feet < 528 {
            return String(format: "%.0f ft", feet)
        } else {
            return String(format: "%.1f mi", meters / 1609.34)
        }
    }
}

private struct LineRow: View {
    let group: NearestLineGroup

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LineBullet(line: group.line, size: 26)

            VStack(alignment: .leading, spacing: 3) {
                if !group.uptownDepartures.isEmpty {
                    DirectionDepartures(label: "↑", departures: group.uptownDepartures)
                }
                if !group.downtownDepartures.isEmpty {
                    DirectionDepartures(label: "↓", departures: group.downtownDepartures)
                }
                if group.uptownDepartures.isEmpty && group.downtownDepartures.isEmpty {
                    Text("No trains")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct DirectionDepartures: View {
    let label: String
    let departures: [Departure]

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.gray)
                .frame(width: 10)

            HStack(spacing: 10) {
                ForEach(departures.prefix(3)) { dep in
                    minuteView(dep)
                }
            }

            if let first = departures.first, !first.destination.isEmpty {
                Text(first.destination)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func minuteView(_ dep: Departure) -> some View {
        if dep.minutes == 0 {
            Text("now")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(dep.minutes)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("m")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        }
    }
}
