import Foundation

/// A currently-active MTA service alert affecting a specific line (and often a
/// specific direction / set of stations).
struct ServiceAlert: Identifiable, Hashable {
    let id: String
    let header: String
    let details: String?

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
