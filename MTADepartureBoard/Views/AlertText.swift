import SwiftUI

/// Renders MTA alert text, turning its bracketed line tokens ("[A]", "[6]")
/// into real line bullets that flow inline with the surrounding words.
struct AlertText: View {
    let text: String
    var font: Font = .footnote

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        composed
            .font(font)
    }

    private var composed: Text {
        Self.tokenize(text).reduce(Text("")) { result, token in
            switch token {
            case .words(let words):
                return result + Text(words)
            case .line(let line):
                return result + bullet(line)
            }
        }
    }

    private func bullet(_ line: String) -> Text {
        if let image = Self.bulletImage(line: line, scale: displayScale) {
            return Text(Image(uiImage: image)).baselineOffset(-3)
        }
        // Fallback: the bare letter in the line's color.
        return Text(line).bold().foregroundColor(.subway(line))
    }

    // MARK: - Tokenizing

    private enum Token {
        case words(String)
        case line(String)
    }

    private static let tokenPattern = try? NSRegularExpression(pattern: "\\[([A-Z0-9]{1,3})\\]")

    private static func tokenize(_ text: String) -> [Token] {
        guard let tokenPattern else { return [.words(text)] }

        let ns = text as NSString
        var tokens: [Token] = []
        var cursor = 0

        for match in tokenPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                tokens.append(.words(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            tokens.append(.line(ns.substring(with: match.range(at: 1))))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            tokens.append(.words(ns.substring(from: cursor)))
        }
        return tokens
    }

    // MARK: - Bullet rasterizing

    private static var bulletCache: [String: UIImage] = [:]
    private static let bulletSize: CGFloat = 16

    @MainActor
    private static func bulletImage(line: String, scale: CGFloat) -> UIImage? {
        let key = "\(line)@\(scale)"
        if let cached = bulletCache[key] { return cached }

        let renderer = ImageRenderer(content: LineBullet(line: line, size: bulletSize))
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }

        bulletCache[key] = image
        return image
    }
}
