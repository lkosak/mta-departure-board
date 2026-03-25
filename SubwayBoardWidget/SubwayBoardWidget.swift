import SwiftUI
import WidgetKit

struct DepartureEntry: TimelineEntry {
    let date: Date
    let feed: WatchedFeed?
    let departures: [CachedDeparture]
}

struct SubwayBoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry(date: .now, feed: nil, departures: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (DepartureEntry) -> Void) {
        let entry = makeEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DepartureEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh in 60 seconds
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func makeEntry() -> DepartureEntry {
        let feeds = SharedDefaults.loadFeeds()
        let allDepartures = SharedDefaults.loadDepartures()

        guard let firstFeed = feeds.first else {
            return DepartureEntry(date: .now, feed: nil, departures: [])
        }

        let deps = allDepartures[firstFeed.id] ?? []
        // Filter out departed trains
        let valid = deps.filter { $0.arrivalTime > Date() }
        return DepartureEntry(date: .now, feed: firstFeed, departures: valid)
    }
}

struct SubwayBoardWidget: Widget {
    let kind = "SubwayBoardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SubwayBoardProvider()) { entry in
            SubwayBoardWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Subway Departures")
        .description("Real-time NYC subway departure times.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
