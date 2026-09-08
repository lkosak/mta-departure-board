import SwiftUI

/// A line at a station, with one feed per available direction.
struct LineDetailTarget: Identifiable, Hashable {
    let line: String
    let stationName: String
    let feeds: [WatchedFeed]

    var id: String {
        stationName + "|" + line + "|" + feeds.map(\.id.uuidString).joined(separator: ",")
    }
}

struct LineDetailView: View {
    let target: LineDetailTarget

    @EnvironmentObject var store: AppStore
    @State private var selectedTrip: TripDetailTarget?

    private static let maxDepartures = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !alertGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(alertGroups, id: \.alert.id) { group in
                            AlertCard(alert: group.alert,
                                      directions: group.directions.count == target.feeds.count ? [] : group.directions)
                        }
                    }
                }

                ForEach(target.feeds) { feed in
                    DirectionSection(
                        feed: feed,
                        departures: Array(departures(for: feed).prefix(Self.maxDepartures)),
                        onSelectDeparture: { departure in
                            selectedTrip = TripDetailTarget(feed: feed, departure: departure)
                        }
                    )
                }
            }
            .padding(16)
        }
        .background(Color.black)
        .scrollContentBackground(.hidden)
        .navigationTitle(target.stationName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable {
            await store.refreshDepartures()
        }
        .onAppear {
            store.startAutoRefresh()
        }
        .sheet(item: $selectedTrip) { trip in
            TripStopsView(target: trip)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            LineBullet(line: target.line, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(target.line) train")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Tap a train for stop-by-stop times")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            Spacer()
        }
    }

    /// Alerts across the target's directions, deduped, keeping track of which
    /// directions each one applies to.
    private var alertGroups: [(alert: ServiceAlert, directions: [WatchedFeed.Direction])] {
        var order: [String] = []
        var byId: [String: (alert: ServiceAlert, directions: [WatchedFeed.Direction])] = [:]

        for feed in target.feeds {
            for alert in store.alerts[feed.id] ?? [] {
                if var existing = byId[alert.id] {
                    existing.directions.append(feed.direction)
                    byId[alert.id] = existing
                } else {
                    order.append(alert.id)
                    byId[alert.id] = (alert, [feed.direction])
                }
            }
        }
        return order.compactMap { byId[$0] }
    }

    private func departures(for feed: WatchedFeed) -> [Departure] {
        store.departures[feed.id] ?? store.nearbyStationDepartures[feed.id] ?? []
    }
}

private struct AlertCard: View {
    let alert: ServiceAlert
    /// Only shown when the alert applies to some, but not all, of the directions on screen.
    let directions: [WatchedFeed.Direction]

    /// Planned work is muted; anything happening now gets the warning color.
    private var accent: Color {
        alert.isPlanned ? .cyan : .yellow
    }

    /// "DELAYS", or "DELAYS · DOWNTOWN" when the alert hits only one of the
    /// directions on screen. Falls back to the directions alone if the feed
    /// omits a type.
    private var headingText: String? {
        let directionText = directions.map { $0.label.uppercased() }
        let parts = [alert.typeHeading].compactMap { $0 } + directionText
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Time alone for today's alerts, date and time for older ones.
    private static func postedFormat(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: alert.isPlanned ? "calendar" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 6) {
                if let heading = headingText {
                    Text(heading)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .kerning(0.5)
                }

                AlertText(text: alert.header)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let details = alert.details, details != alert.header {
                    AlertText(text: details, font: .caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let postedAt = alert.postedAt {
                    Text("Posted \(Self.postedFormat(postedAt))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DirectionSection: View {
    let feed: WatchedFeed
    let departures: [Departure]
    let onSelectDeparture: (Departure) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(feed.direction.label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)
                .kerning(0.5)

            Divider()
                .background(Color.gray.opacity(0.5))

            if departures.isEmpty {
                Text("No upcoming trains")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .padding(.vertical, 4)
            } else {
                ForEach(departures) { departure in
                    DetailDepartureRow(departure: departure) {
                        onSelectDeparture(departure)
                    }
                }
            }
        }
        .padding()
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailDepartureRow: View {
    let departure: Departure
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(departure.destination.isEmpty ? departure.line : departure.destination)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(departure.arrivalDate.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.gray)

            countdown
                .frame(minWidth: 60, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var countdown: some View {
        if departure.minutes == 0 {
            Text("arriving")
                .font(.subheadline.bold())
                .foregroundStyle(.green)
        } else {
            Text("\(departure.minutes) min")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(departure.minutes > 20 ? .gray : .white)
        }
    }
}
