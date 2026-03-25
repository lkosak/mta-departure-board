import ActivityKit
import SwiftUI
import WidgetKit

struct SubwayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SubwayDepartureAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
                .containerBackground(.black, for: .widget)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WidgetLineBullet(line: context.attributes.feed.line, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.attributes.feed.stationName)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.attributes.feed.direction.label)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveDepartureList(departures: context.state.departures, maxRows: 3)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                WidgetLineBullet(line: context.attributes.feed.line, size: 22)
                    .padding(.leading, 4)
            } compactTrailing: {
                if let next = context.state.departures.first(where: { $0.arrivalTime > .now }) {
                    Text(next.minutes == 0 ? "now" : "\(next.minutes)m")
                        .font(.caption.bold())
                        .foregroundStyle(next.minutes == 0 ? .green : .white)
                        .frame(minWidth: 28, alignment: .trailing)
                        .padding(.trailing, 4)
                }
            } minimal: {
                WidgetLineBullet(line: context.attributes.feed.line, size: 22)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<SubwayDepartureAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                WidgetLineBullet(line: context.attributes.feed.line, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.attributes.feed.stationName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(context.attributes.feed.direction.label)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                // Relative timestamp updates automatically
                Text(context.state.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.trailing)
            }

            Divider()
                .background(Color.gray.opacity(0.4))

            LiveDepartureList(departures: context.state.departures, maxRows: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Shared departure rows

private struct LiveDepartureList: View {
    let departures: [CachedDeparture]
    let maxRows: Int

    var body: some View {
        let upcoming = Array(departures.filter { $0.arrivalTime > .now }.prefix(maxRows))
        if upcoming.isEmpty {
            Text("No upcoming trains")
                .font(.caption)
                .foregroundStyle(.gray)
        } else {
            ForEach(upcoming) { dep in
                HStack {
                    Text(dep.destination)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    Group {
                        if dep.minutes == 0 {
                            Text("arriving")
                                .foregroundStyle(.green)
                        } else {
                            Text("\(dep.minutes) min")
                                .foregroundStyle(dep.minutes > 20 ? .gray : .white)
                        }
                    }
                    .font(.caption.bold())
                    .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}
