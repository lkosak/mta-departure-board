import ActivityKit
import SwiftUI

struct FeedCardView: View {
    let feed: WatchedFeed
    let departures: [Departure]
    var alerts: [ServiceAlert] = []
    var onTap: (() -> Void)? = nil

    @EnvironmentObject private var liveActivityManager: LiveActivityManager

    private var isLiveActive: Bool {
        liveActivityManager.activeFeedIds.contains(feed.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                LineBullet(line: feed.line)

                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.stationName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(feed.direction.label)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                Spacer()

                if ActivityAuthorizationInfo().areActivitiesEnabled {
                    Button {
                        Task {
                            if isLiveActive {
                                await liveActivityManager.stop(feedId: feed.id)
                            } else {
                                let cached = departures.map { CachedDeparture(from: $0) }
                                liveActivityManager.start(feed: feed, departures: cached)
                            }
                        }
                    } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.subheadline)
                            .foregroundStyle(isLiveActive ? .green : .white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Divider()
                .background(Color.gray.opacity(0.5))

            // Service alerts — first one only; the detail view lists them all
            if let alert = alerts.first {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(alert.plainHeader)
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.85))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if alerts.count > 1 {
                        Text("+\(alerts.count - 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.yellow.opacity(0.6))
                    }
                }
                .padding(.vertical, 2)
            }

            // Departures
            if departures.isEmpty {
                Text("No upcoming trains")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .padding(.vertical, 4)
            } else {
                ForEach(departures.prefix(4)) { departure in
                    DepartureRow(departure: departure)
                }
            }
        }
        .padding()
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

struct LineBullet: View {
    let line: String
    var size: CGFloat = 32

    var body: some View {
        Text(line)
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(Color.subwayText(line))
            .frame(width: size, height: size)
            .background(Color.subway(line))
            .clipShape(Circle())
    }
}

struct DepartureRow: View {
    let departure: Departure

    var body: some View {
        HStack {
            if !departure.destination.isEmpty {
                Text(departure.destination)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer()

            if departure.minutes == 0 {
                Text("arriving")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            } else if departure.minutes == 1 {
                Text("1 min")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            } else {
                Text("\(departure.minutes) min")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(departure.minutes > 20 ? .gray : .white)
            }
        }
        .padding(.vertical, 2)
    }
}
