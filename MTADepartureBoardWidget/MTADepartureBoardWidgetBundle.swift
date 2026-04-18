import SwiftUI
import WidgetKit

@main
struct MTADepartureBoardWidgetBundle: WidgetBundle {
    var body: some Widget {
        MTADepartureBoardWidget()
        SubwayLiveActivity()
    }
}
