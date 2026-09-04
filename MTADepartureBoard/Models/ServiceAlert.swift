import Foundation

/// A currently-active MTA service alert affecting a specific line (and often a
/// specific direction / set of stations).
struct ServiceAlert: Identifiable, Hashable {
    let id: String
    let header: String
    let details: String?
    /// When the MTA first posted the alert, from the feed's Mercury extension.
    let postedAt: Date?
    /// MTA's own category for the alert, e.g. "Delays", "Planned - Stops Skipped".
    let alertType: String?

    /// Planned work is routine; everything else is happening now.
    var isPlanned: Bool {
        alertType?.hasPrefix("Planned") ?? false
    }

    /// "Planned - Stops Skipped" -> "PLANNED · STOPS SKIPPED"
    var typeHeading: String? {
        alertType?.replacingOccurrences(of: " - ", with: " · ").uppercased()
    }

    /// The alert text with MTA's bracketed line tokens removed, e.g.
    /// "In Manhattan, downtown [A] local skips 50 St" -> "In Manhattan, downtown A local skips 50 St".
    var plainHeader: String {
        ServiceAlert.strippingLineTokens(header)
    }

    static func strippingLineTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "\\[([A-Z0-9]{1,3})\\]",
                                  with: "$1",
                                  options: .regularExpression)
    }
}
