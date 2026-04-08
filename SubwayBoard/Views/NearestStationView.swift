import SwiftUI

// Groups departures for a single line (both directions) at the nearest station
private struct NearestLineGroup: Identifiable {
    let line: String
    let uptownDepartures: [Departure]
    let downtownDepartures: [Departure]
    var id: String { line }
}

struct NearestStationView: View {
    @EnvironmentObject var store: AppStore

    private var lineGroups: [NearestLineGroup] {
        let lineOrder = ["1","2","3","4","5","6","7","A","C","E","B","D","F","M","G","J","Z","L","N","Q","R","W","S"]
        let lines = lineOrder.filter { line in
            store.nearestStationFeeds.contains(where: { $0.line == line })
        }
        return lines.map { line in
            let uptownFeed = store.nearestStationFeeds.first { $0.line == line && $0.direction == .uptown }
            let downtownFeed = store.nearestStationFeeds.first { $0.line == line && $0.direction == .downtown }
            return NearestLineGroup(
                line: line,
                uptownDepartures: uptownFeed.flatMap { store.nearestStationDepartures[$0.id] } ?? [],
                downtownDepartures: downtownFeed.flatMap { store.nearestStationDepartures[$0.id] } ?? []
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            ForEach(lineGroups) { group in
                NearestLineFeedCard(group: group)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Spacer(minLength: 4)
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)
            Text("NEAREST")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)
                .kerning(0.5)
            if let station = store.nearestStation {
                Text(station.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer()
            if let meters = store.nearestStationDistance {
                Text(formattedDistance(meters))
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func formattedDistance(_ meters: Double) -> String {
        let feet = meters * 3.28084
        if feet < 528 {  // less than 0.1 mi
            return String(format: "%.0f ft", feet)
        } else {
            return String(format: "%.1f mi", meters / 1609.34)
        }
    }
}

private struct NearestLineFeedCard: View {
    let group: NearestLineGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                LineBullet(line: group.line)
                Text(group.line + " train")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                // Subtle auto-indicator
                Image(systemName: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.teal.opacity(0.6))
            }

            Divider()
                .background(Color.teal.opacity(0.25))

            if !group.uptownDepartures.isEmpty {
                DirectionRow(label: "Uptown", departures: group.uptownDepartures)
            }
            if !group.downtownDepartures.isEmpty {
                DirectionRow(label: "Downtown", departures: group.downtownDepartures)
            }
            if group.uptownDepartures.isEmpty && group.downtownDepartures.isEmpty {
                Text("No upcoming trains")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .padding(.vertical, 2)
            }
        }
        .padding()
        .background(
            ZStack(alignment: .leading) {
                Color(red: 0.04, green: 0.11, blue: 0.18)
                Rectangle()
                    .fill(Color.teal.opacity(0.6))
                    .frame(width: 3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DirectionRow: View {
    let label: String
    let departures: [Departure]

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
                .frame(width: 60, alignment: .leading)

            HStack(spacing: 10) {
                ForEach(departures.prefix(3)) { dep in
                    minutesBadge(dep)
                }
            }

            Spacer()

            if let first = departures.first, !first.destination.isEmpty {
                Text("→ \(first.destination)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func minutesBadge(_ dep: Departure) -> some View {
        if dep.minutes == 0 {
            Text("now")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(dep.minutes)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(dep.minutes <= 2 ? .yellow : .white)
                Text("m")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        }
    }
}
