import SwiftUI
import WidgetKit

struct MTADepartureBoardWidgetView: View {
    let entry: DepartureEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        if let feed = entry.feed {
            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack(spacing: 6) {
                    WidgetLineBullet(line: feed.line, size: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(feed.stationName)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(feed.direction.label)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                }

                Divider()
                    .background(Color.gray.opacity(0.4))

                let maxRows = family == .systemSmall ? 3 : 4
                let deps = Array(entry.departures.prefix(maxRows))

                if deps.isEmpty {
                    Text("No trains")
                        .font(.caption)
                        .foregroundStyle(.gray)
                } else {
                    ForEach(deps) { dep in
                        HStack {
                            if family == .systemMedium {
                                Text(dep.destination)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            Spacer()
                            if dep.minutes == 0 {
                                Text("now")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            } else {
                                Text("\(dep.minutes) min")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(dep.minutes > 20 ? .gray : .white)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "tram.fill")
                    .font(.title2)
                    .foregroundStyle(.gray)
                Text("Open app to\nadd a station")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct WidgetLineBullet: View {
    let line: String
    var size: CGFloat = 22

    var body: some View {
        Text(line)
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(Color.subwayText(line))
            .frame(width: size, height: size)
            .background(Color.subway(line))
            .clipShape(Circle())
    }
}
