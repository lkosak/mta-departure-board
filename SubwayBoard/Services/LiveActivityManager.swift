import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published var activeFeedIds: Set<UUID> = []

    private var activities: [UUID: Activity<SubwayDepartureAttributes>] = [:]
    private var tokenTasks: [UUID: Task<Void, Never>] = [:]

    private init() {
        // Reconnect to any activities that survived an app restart.
        for activity in Activity<SubwayDepartureAttributes>.activities {
            let id = activity.attributes.feed.id
            activities[id] = activity
            activeFeedIds.insert(id)
            observePushToken(for: activity, feed: activity.attributes.feed)
        }
    }

    func start(feed: WatchedFeed, departures: [CachedDeparture]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activities[feed.id] == nil else { return }

        let state = SubwayDepartureAttributes.ContentState(departures: departures, updatedAt: .now)
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 60))

        do {
            let activity = try Activity.request(
                attributes: SubwayDepartureAttributes(feed: feed),
                content: content,
                pushType: .token
            )
            activities[feed.id] = activity
            activeFeedIds.insert(feed.id)
            observePushToken(for: activity, feed: feed)
        } catch {
            print("LiveActivity start failed: \(error)")
        }
    }

    func stop(feedId: UUID) async {
        tokenTasks[feedId]?.cancel()
        tokenTasks[feedId] = nil

        guard let activity = activities[feedId] else { return }

        if let tokenData = activity.pushToken {
            let token = tokenData.map { String(format: "%02x", $0) }.joined()
            await Self.unregisterFromServer(token: token)
        }

        await activity.end(nil, dismissalPolicy: .immediate)
        activities[feedId] = nil
        activeFeedIds.remove(feedId)
    }

    /// Called from AppStore after every departure refresh.
    func updateAll(departures: [UUID: [CachedDeparture]]) async {
        for (feedId, deps) in departures {
            guard let activity = activities[feedId] else { continue }
            let state = SubwayDepartureAttributes.ContentState(departures: deps, updatedAt: .now)
            let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 60))
            await activity.update(content)
        }
    }

    // MARK: - Push Token Observation

    private func observePushToken(for activity: Activity<SubwayDepartureAttributes>, feed: WatchedFeed) {
        tokenTasks[feed.id]?.cancel()
        tokenTasks[feed.id] = Task.detached {
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { break }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await Self.registerWithServer(token: token, feed: feed)
            }
        }
    }

    // MARK: - Server Registration

    private static func registerWithServer(token: String, feed: WatchedFeed) async {
        guard let url = URL(string: "\(ServerConfig.baseURL)/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: String] = [
            "token": token,
            "feedId": feed.id.uuidString,
            "line": feed.line,
            "directionStopId": feed.directionStopId,
            "stationName": feed.stationName,
            "direction": feed.direction.rawValue,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func unregisterFromServer(token: String) async {
        guard let url = URL(string: "\(ServerConfig.baseURL)/register/\(token)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: request)
    }
}
