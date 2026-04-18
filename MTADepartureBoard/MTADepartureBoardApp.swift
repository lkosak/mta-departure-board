import BackgroundTasks
import SwiftUI
import WidgetKit

private let refreshTaskIdentifier = "io.lou.subwayboard.refresh"

@main
struct MTADepartureBoardApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var liveActivityManager = LiveActivityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(liveActivityManager)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                scheduleAppRefresh()
            }
        }
        .backgroundTask(.appRefresh(refreshTaskIdentifier)) {
            await runBackgroundRefresh()
            scheduleAppRefresh()
        }
    }
}

private func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)
}

private func runBackgroundRefresh() async {
    let feeds = SharedDefaults.loadFeeds()
    guard !feeds.isEmpty else { return }

    try? await GTFSStaticService.shared.loadStations()

    let deps = await MTAFeedService.fetchDeparturesForAllFeeds(feeds)
    let now = Date()
    var cached: [UUID: [CachedDeparture]] = [:]
    for (id, departures) in deps {
        cached[id] = departures.map { CachedDeparture(from: $0, now: now) }
    }
    SharedDefaults.saveDepartures(cached)
    WidgetCenter.shared.reloadAllTimelines()
    await LiveActivityManager.shared.updateAll(departures: cached)
}
