import SwiftUI

struct FeedCardView: View {
    let feed: WatchedFeed
    let departures: [Departure]

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
            }

            Divider()
                .background(Color.gray.opacity(0.5))

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
