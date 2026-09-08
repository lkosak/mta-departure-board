import SwiftUI

/// One specific train, boarded at one specific station.
struct TripDetailTarget: Identifiable {
    let feed: WatchedFeed
    let departure: Departure

    var id: String {
        feed.id.uuidString + "|" + departure.tripId + "|" + departure.id.uuidString
    }
}

/// "If I get on this train, what time do I get to station X?" — the rest of the
/// trip, stop by stop, with clock times and ride durations.
struct TripStopsView: View {
    let target: TripDetailTarget

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// The same train from the latest refresh, so times stay live while the
    /// sheet is open. Falls back to the tapped snapshot.
    private var departure: Departure {
        let pool = store.departures[target.feed.id] ?? store.nearbyStationDepartures[target.feed.id] ?? []
        if !target.departure.tripId.isEmpty,
           let fresh = pool.first(where: { $0.tripId == target.departure.tripId }) {
            return fresh
        }
        return target.departure
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    boardingCard

                    if departure.remainingStops.isEmpty {
                        Text("The feed isn't reporting stop-by-stop times for this train.")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                    } else {
                        stopList
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color.black)
            .scrollContentBackground(.hidden)
            .navigationTitle("This train")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Boarding

    private var boardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LineBullet(line: departure.line, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(departure.destination.isEmpty
                         ? "\(departure.line) train"
                         : "to \(departure.destination)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(target.feed.direction.label)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "figure.walk.departure")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Board at \(target.feed.stationName)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 8)
                Text(Self.clock(departure.arrivalDate))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(departure.minutes == 0 ? "now" : "\(departure.minutes) min")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(departure.minutes == 0 ? .green : .gray)
                    .frame(minWidth: 46, alignment: .trailing)
            }
        }
        .padding(14)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Stops

    private var stopList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ARRIVES AT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)
                .kerning(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(departure.remainingStops) { stop in
                    StopRow(
                        stop: stop,
                        line: departure.line,
                        rideMinutes: rideMinutes(to: stop),
                        isLast: stop.id == departure.remainingStops.last?.id
                    )
                }
            }
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    /// Minutes on board, from this train's departure to that stop.
    private func rideMinutes(to stop: TripStop) -> Int {
        max(0, Int(stop.arrivalDate.timeIntervalSince(departure.arrivalDate) / 60))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

private struct StopRow: View {
    let stop: TripStop
    let line: String
    let rideMinutes: Int
    let isLast: Bool

    /// Transfers get crowded at hubs — show a handful, then a count.
    private static let maxTransferBullets = 4

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            rail

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.stationName)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(isLast ? 1 : 0.85))
                    .lineLimit(2)

                if !stop.transferLines.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(stop.transferLines.prefix(Self.maxTransferBullets), id: \.self) { transfer in
                            LineBullet(line: transfer, size: 15)
                        }
                        if stop.transferLines.count > Self.maxTransferBullets {
                            Text("+\(stop.transferLines.count - Self.maxTransferBullets)")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }
            .padding(.vertical, 7)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(TripStopsView.clock(stop.arrivalDate))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white)
                Text(rideMinutes == 0 ? "on board" : "+\(rideMinutes) min")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.gray)
            }
            .padding(.vertical, 7)
        }
        .padding(.horizontal, 14)
    }

    /// Dot-and-line rail down the left, in the train's color.
    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.subway(line))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            Circle()
                .strokeBorder(Color.subway(line), lineWidth: isLast ? 4 : 3)
                .background(Circle().fill(Color(white: 0.1)))
                .frame(width: isLast ? 13 : 10, height: isLast ? 13 : 10)

            Rectangle()
                .fill(isLast ? Color.clear : Color.subway(line))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 14)
        .frame(maxHeight: .infinity)
    }
}
