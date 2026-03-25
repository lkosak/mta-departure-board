import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }

    static func subway(_ line: String) -> Color {
        switch line {
        case "1", "2", "3": return Color(hex: "EE352E")
        case "4", "5", "6": return Color(hex: "00933C")
        case "7": return Color(hex: "B933AD")
        case "A", "C", "E": return Color(hex: "0039A6")
        case "B", "D", "F", "M": return Color(hex: "FF6319")
        case "G": return Color(hex: "6CBE45")
        case "J", "Z": return Color(hex: "996633")
        case "L": return Color(hex: "A7A9AC")
        case "N", "Q", "R", "W": return Color(hex: "FCCC0A")
        case "S": return Color(hex: "808183")
        default: return .gray
        }
    }

    static func subwayText(_ line: String) -> Color {
        switch line {
        case "N", "Q", "R", "W": return .black
        default: return .white
        }
    }
}
