import Foundation

struct Departure: Identifiable {
    let id = UUID()
    let line: String
    let destination: String
    let minutes: Int
    let arrivalDate: Date
}
