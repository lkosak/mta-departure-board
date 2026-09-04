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
                        departures: Array(departures(for: feed).prefix(Self.maxDepartures))
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
    }

    private var header: some View {
        HStack(spacing: 10) {
            LineBullet(line: target.line, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(target.line) train")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Upcoming trains")
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 6) {
                if !directions.isEmpty {
                    Text(directions.map(\.label).joined(separator: " · ").uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow.opacity(0.7))
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
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DirectionSection: View {
    let feed: WatchedFeed
    let departures: [Departure]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(feed.direction.label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)
                .kerning(0.5)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()
                .background(Color.gray.opacity(0.4))
                .padding(.horizontal, 12)

            if departures.isEmpty {
                Text("No upcoming trains")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .padding(12)
            } else {
                ForEach(departures) { departure in
                    DetailDepartureRow(departure: departure)
                    if departure.id != departures.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailDepartureRow: View {
    let departure: Departure

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
