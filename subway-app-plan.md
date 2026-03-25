# NYC Subway Departures App — Implementation Plan

## Goal
Build an iOS 18+ app + WidgetKit widget that shows real-time NYC subway departures for user-selected stations and lines, styled to match the platform countdown clock displays (black background, colored line bullets, minutes countdown).

---

## Project Setup

- **Xcode project name**: `SubwayBoard` (or `Trains`)
- **Bundle ID prefix**: `io.lou.subwayboard` (adjust to taste)
- **Targets**: `SubwayBoard` (iOS app) + `SubwayBoardWidget` (Widget Extension)
- **Minimum deployment**: iOS 17 (WidgetKit medium/large widgets, SwiftUI)
- **Swift Packages to add**:
  - `https://github.com/apple/swift-protobuf.git` — decode MTA protobuf feeds
- **App Group**: `group.io.lou.subwayboard` — shared container between app + widget
- **Capabilities**: App Groups (on both targets)

---

## Static Data Strategy

The MTA publishes a static GTFS zip that contains the full station list. Rather than bundling a stale copy, **download it once on first launch** and cache it locally. Alternatively, bundle a snapshot at build time for instant first-run.

- **Static GTFS URL**: `http://web.mta.info/developers/data/nyct/subway/google_transit.zip`
- Files needed: `stops.txt`, `routes.txt`, `stop_times.txt`
- Parse on a background thread; store results in a lightweight local model (not SwiftData — just `[Station]` in memory + persisted as JSON in the App Group container)

Each `Stop` in `stops.txt` has an ID like `"127N"` / `"127S"`. A physical station is represented by multiple stop rows (one per direction). Group by the numeric prefix to show one station entry in the picker.

---

## MTA Real-Time Feeds

No API key required for `https://api.mta.info` endpoints.

Feed URLs by line group (all return binary protobuf):

| Lines | URL |
|-------|-----|
| 1 2 3 4 5 6 | `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs` |
| A C E H FS | `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace` |
| B D F M | `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm` |
| G | `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g` |
| J Z | `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz` |
| L | `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l` |
| N Q R W | `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw` |
| 7 | `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-7` |

Feeds update approximately every 30 seconds. Only fetch the feeds for the lines the user has selected.

---

## Proto Files

Download and include these two `.proto` files (commit them into the repo under `Proto/`):

1. **gtfs-realtime.proto** — standard GTFS-RT: https://github.com/google/transit/blob/master/gtfs-realtime/proto/gtfs-realtime.proto
2. **nyct-subway.proto** — NYCT extensions: https://api.mta.info/nyct-subway.proto.txt

Generate Swift bindings once with:
```bash
protoc --swift_out=Sources/SubwayBoard/Generated Proto/gtfs-realtime.proto Proto/nyct-subway.proto
```
Commit the generated `.pb.swift` files — no build plugin needed.

---

## Data Model (in-memory, no SwiftData needed)

```swift
struct Station: Identifiable, Codable {
    let id: String          // numeric prefix, e.g. "127"
    let name: String        // e.g. "Times Sq-42 St"
    let lines: [String]     // routes serving this station, e.g. ["N","Q","R","W"]
    let stopIds: [String]   // e.g. ["127N", "127S"]
}

struct WatchedFeed: Identifiable, Codable {
    let id: UUID
    let stationId: String
    let line: String         // e.g. "N"
    let directionStopId: String  // e.g. "127N"
    let headsign: String?    // last stop name, shown as destination
}

struct Departure: Identifiable {
    let id: UUID
    let line: String
    let destination: String
    let minutes: Int         // minutes until arrival
    let isLast: Bool         // grays out "last train" entries
}
```

Persist `[WatchedFeed]` as JSON in the App Group container so the widget can read it without launching the app.

---

## App Architecture

### Settings / Onboarding
- Launch with a `StationPickerView` if no feeds configured yet
- Search/filter `[Station]` list by name
- Tap a station → `LinePickerView`: shows all lines at that station as colored bullets, pick one
- Direction is inferred from GTFS stop IDs (N = uptown/Bronx, S = downtown/Brooklyn — show human-readable labels from `stop_headsign` in `stop_times.txt` or derive from the last stop of the trip)
- Saved feeds appear as cards on the home screen; swipe to delete, tap + to add more

### Main App View (`DepartureBoardView`)
- Black background, full screen
- One card per `WatchedFeed`, stacked vertically (or scrollable)
- Each card shows the next 3–4 departures for that line+direction
- Auto-refreshes every 30 seconds via `Timer` + `async/await` fetch

### Widget (`SubwayBoardWidget`)
- **Small**: single feed, next 2 trains
- **Medium**: single feed, next 4 trains (preferred default)
- Timeline entries generated from cached data written to App Group by the app
- Widget calls `WidgetCenter.shared.reloadAllTimelines()` is triggered by the app after each fetch
- Widget timeline policy: `.atEnd` with next entry 30s out so WidgetKit re-fetches periodically on its own schedule too
- Widget uses `AppIntent` for interactive configuration (iOS 17+) — user can pick which `WatchedFeed` to display directly in the widget

---

## UI Design (Platform Display Style)

```
┌─────────────────────────────────────────────────┐
│  ⬤N   Times Sq → Astoria                        │
│  ──────────────────────────────────────────────  │
│  2 min                                           │
│  5 min                                           │
│  12 min                                          │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  ⬤Q   Times Sq → Stillwell Av                   │
│  ──────────────────────────────────────────────  │
│  1 min                                           │
│  8 min                                           │
└─────────────────────────────────────────────────┘
```

**Colors**:
```swift
extension Color {
    static let subwayLine: [String: Color] = [
        "1": Color(hex: "#EE352E"), "2": Color(hex: "#EE352E"), "3": Color(hex: "#EE352E"),
        "4": Color(hex: "#00933C"), "5": Color(hex: "#00933C"), "6": Color(hex: "#00933C"),
        "7": Color(hex: "#B933AD"),
        "A": Color(hex: "#0039A6"), "C": Color(hex: "#0039A6"), "E": Color(hex: "#0039A6"),
        "B": Color(hex: "#FF6319"), "D": Color(hex: "#FF6319"), "F": Color(hex: "#FF6319"), "M": Color(hex: "#FF6319"),
        "G": Color(hex: "#6CBE45"),
        "J": Color(hex: "#996633"), "Z": Color(hex: "#996633"),
        "L": Color(hex: "#A7A9AC"),
        "N": Color(hex: "#FCCC0A"), "Q": Color(hex: "#FCCC0A"), "R": Color(hex: "#FCCC0A"), "W": Color(hex: "#FCCC0A"),
    ]
}
```
- `"arriving"` label (bold) when `minutes == 0`
- Dim/gray entries beyond 20 min or that are the last train of night

---

## File Structure

```
SubwayBoard/
├── SubwayBoardApp.swift
├── Models/
│   ├── Station.swift
│   ├── WatchedFeed.swift
│   └── Departure.swift
├── Services/
│   ├── GTFSStaticService.swift     # downloads + parses stops.txt / routes.txt
│   ├── MTAFeedService.swift        # fetches + decodes protobuf, returns [Departure]
│   └── SharedStore.swift           # reads/writes WatchedFeed JSON to App Group
├── Views/
│   ├── DepartureBoardView.swift
│   ├── FeedCardView.swift
│   ├── StationPickerView.swift
│   └── LinePickerView.swift
├── Generated/
│   ├── gtfs-realtime.pb.swift
│   └── nyct-subway.pb.swift
├── Proto/
│   ├── gtfs-realtime.proto
│   └── nyct-subway.proto
SubwayBoardWidget/
├── SubwayBoardWidget.swift         # Widget entry point + timeline provider
├── WidgetFeedCardView.swift
└── SubwayBoardWidgetBundle.swift
```

---

## Key Implementation Details

### Parsing departures from protobuf
```swift
// MTAFeedService.swift — pseudocode
func fetchDepartures(for stopId: String, line: String) async throws -> [Departure] {
    let feedURL = feedURL(forLine: line)
    let data = try await URLSession.shared.data(from: feedURL).0
    let feed = try TransitRealtime_FeedMessage(serializedBytes: data)

    return feed.entity
        .filter { $0.hasTripUpdate }
        .flatMap { entity -> [Departure] in
            let trip = entity.tripUpdate
            guard trip.trip.routeID == line else { return [] }
            return trip.stopTimeUpdate
                .filter { $0.stopID == stopId }
                .compactMap { update -> Departure? in
                    let t = update.hasArrival ? update.arrival.time : update.departure.time
                    let mins = Int((t - Date().timeIntervalSince1970) / 60)
                    guard mins >= 0 else { return nil }
                    return Departure(line: line, destination: lastStopName(for: trip),
                                     minutes: mins)
                }
        }
        .sorted { $0.minutes < $1.minutes }
}
```

### App Group shared store
```swift
// SharedStore.swift
let groupID = "group.io.lou.subwayboard"
let containerURL = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: groupID)!

func saveFeeds(_ feeds: [WatchedFeed]) { /* write JSON */ }
func loadFeeds() -> [WatchedFeed] { /* read JSON */ }
func saveDepartures(_ deps: [String: [Departure]]) { /* keyed by WatchedFeed.id */ }
```

---

## Build Instructions for Claude

1. Create new Xcode project (iOS App, SwiftUI, Swift, no SwiftData needed)
2. Add Widget Extension target
3. Add App Group capability to both targets
4. Add `swift-protobuf` Swift Package
5. Download proto files, generate Swift bindings, add generated files to both targets
6. Implement files in order: Models → Services → Views → Widget
7. Add all new `.swift` files to `project.pbxproj` (PBXFileReference + PBXBuildFile + PBXGroup + PBXSourcesBuildPhase)
8. Test on simulator with a real MTA feed fetch

---

## Out of Scope (keep it simple)
- No SwiftData / CloudKit (plain JSON persistence is sufficient)
- No push notifications
- No service alert parsing (future feature)
- No map view
