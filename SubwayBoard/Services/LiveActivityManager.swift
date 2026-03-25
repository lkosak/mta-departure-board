import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published var activeFeedIds: Set<UUID> = []

    private var activities: [UUID: Activity<SubwayDepartureAttributes>] = [:]

    private init() {
        // Reconnect to any activities that survived an app restart.
        for activity in Activity<SubwayDepartureAttributes>.activities {
            let id = activity.attributes.feed.id
            activities[id] = activity
            activeFeedIds.insert(id)
        }
    }

    func start(feed: WatchedFeed, departures: [CachedDeparture]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activities[feed.id] == nil else { return }

        let state = SubwayDepartureAttributes.ContentState(departures: departures, updatedAt: .now)
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 90))

        do {
            let activity = try Activity.request(
                attributes: SubwayDepartureAttributes(feed: feed),
                content: content,
                pushType: nil
            )
            activities[feed.id] = activity
            activeFeedIds.insert(feed.id)
        } catch {
            print("LiveActivity start failed: \(error)")
        }
    }

    func stop(feedId: UUID) async {
        guard let activity = activities[feedId] else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        activities[feedId] = nil
        activeFeedIds.remove(feedId)
    }

    /// Called from AppStore after every departure refresh.
    func updateAll(departures: [UUID: [CachedDeparture]]) async {
        for (feedId, deps) in departures {
            guard let activity = activities[feedId] else { continue }
            let state = SubwayDepartureAttributes.ContentState(departures: deps, updatedAt: .now)
            let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 90))
            await activity.update(content)
        }
    }
}
