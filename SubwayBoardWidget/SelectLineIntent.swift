import AppIntents
import WidgetKit

struct WatchedFeedEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Subway Line"
    static var defaultQuery = WatchedFeedQuery()

    let id: UUID
    let line: String
    let stationName: String
    let direction: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(line) · \(stationName) \(direction)")
    }
}

struct WatchedFeedQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WatchedFeedEntity] {
        SharedDefaults.loadFeeds()
            .filter { identifiers.contains($0.id) }
            .map(WatchedFeedEntity.init)
    }

    func suggestedEntities() async throws -> [WatchedFeedEntity] {
        SharedDefaults.loadFeeds().map(WatchedFeedEntity.init)
    }

    func defaultResult() async -> WatchedFeedEntity? {
        SharedDefaults.loadFeeds().first.map(WatchedFeedEntity.init)
    }
}

private extension WatchedFeedEntity {
    init(_ feed: WatchedFeed) {
        self.id = feed.id
        self.line = feed.line
        self.stationName = feed.stationName
        self.direction = feed.direction.label
    }
}

struct SelectLineIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Line"
    static var description = IntentDescription("Choose which subway line to display.")

    @Parameter(title: "Line")
    var feed: WatchedFeedEntity?
}
