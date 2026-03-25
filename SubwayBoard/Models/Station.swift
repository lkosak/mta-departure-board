import Foundation

struct Station: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let lines: [String]
    let stopIds: [String]

    var northStopIds: [String] { stopIds.filter { $0.hasSuffix("N") } }
    var southStopIds: [String] { stopIds.filter { $0.hasSuffix("S") } }
}
