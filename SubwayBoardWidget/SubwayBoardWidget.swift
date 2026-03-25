import AppIntents
import SwiftUI
import WidgetKit

struct DepartureEntry: TimelineEntry {
    let date: Date
    let feed: WatchedFeed?
    let departures: [CachedDeparture]
}

struct SubwayBoardProvider: AppIntentTimelineProvider {
    typealias Intent = SelectLineIntent

    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry(date: .now, feed: nil, departures: [])
    }

    func snapshot(for configuration: SelectLineIntent, in context: Context) async -> DepartureEntry {
        makeEntry(for: configuration)
    }

    func timeline(for configuration: SelectLineIntent, in context: Context) async -> Timeline<DepartureEntry> {
        let entry = makeEntry(for: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func makeEntry(for configuration: SelectLineIntent) -> DepartureEntry {
        let feeds = SharedDefaults.loadFeeds()
        let allDepartures = SharedDefaults.loadDepartures()

        let feed: WatchedFeed?
        if let selectedId = configuration.feed?.id {
            feed = feeds.first { $0.id == selectedId } ?? feeds.first
        } else {
            feed = feeds.first
        }

        guard let feed else {
            return DepartureEntry(date: .now, feed: nil, departures: [])
        }

        let deps = allDepartures[feed.id] ?? []
        let valid = deps.filter { $0.arrivalTime > Date() }
        return DepartureEntry(date: .now, feed: feed, departures: valid)
    }
}

struct SubwayBoardWidget: Widget {
    let kind = "SubwayBoardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLineIntent.self, provider: SubwayBoardProvider()) { entry in
            SubwayBoardWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Subway Departures")
        .description("Real-time NYC subway departure times.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
