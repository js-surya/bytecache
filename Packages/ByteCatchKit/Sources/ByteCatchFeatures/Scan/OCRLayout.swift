import CoreGraphics
import Foundation

/// A recognised line as Vision reports it: text and its four corners in pixels, top-left origin.
/// Corners (not a box) so a tilted photo can be straightened.
public struct OCRLine: Equatable, Sendable {
    public var text: String
    public var topLeft, topRight, bottomLeft, bottomRight: CGPoint

    public init(text: String, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        self.text = text
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
}

/// A piece of recognised text with its box, in top-left normalised coordinates (0…1).
public struct OCRPiece: Equatable, Sendable {
    public var text: String
    public var minX, minY, width, height: Double

    public init(text: String, minX: Double, minY: Double, width: Double, height: Double) {
        self.text = text
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    var midY: Double { minY + height / 2 }
    var maxX: Double { minX + width }
}

/// Turns recognised text pieces back into code: rows top to bottom, pieces left to right,
/// indentation from the left offset, and blank lines from larger vertical gaps.
public enum OCRLayout {
    public static func reconstruct(_ pieces: [OCRPiece]) -> String {
        let pieces = pieces.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !pieces.isEmpty else { return "" }
        let lineHeight = median(pieces.map(\.height))
        let charWidth = median(pieces.filter { $0.text.count >= 3 }.map { $0.width / Double($0.text.count) })
            .nonZero ?? median(pieces.map { $0.width / Double(max($0.text.count, 1)) })

        // Group into rows by vertical centre.
        var rows: [[OCRPiece]] = []
        for piece in pieces.sorted(by: { $0.midY < $1.midY }) {
            if let last = rows.last?.first, abs(piece.midY - last.midY) < lineHeight * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        rows = rows.map { $0.sorted { $0.minX < $1.minX } }

        let left = rows.map { $0[0].minX }.min() ?? 0
        let centres = rows.map { $0[0].midY }
        let gaps = zip(centres, centres.dropFirst()).map { $1 - $0 }
        let pitch = gaps.filter { $0 > lineHeight * 0.6 }.min() ?? lineHeight * 1.2

        var lines: [String] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let skipped = Int(((centres[index] - centres[index - 1]) / pitch).rounded()) - 1
                lines += Array(repeating: "", count: min(max(skipped, 0), 2))
            }
            let indent = charWidth > 0 ? Int(((row[0].minX - left) / charWidth).rounded()) : 0
            var line = String(repeating: " ", count: max(indent, 0)) + fixLookAlikes(row[0].text)
            for (previous, piece) in zip(row, row.dropFirst()) {
                let spaces = charWidth > 0 ? Int(((piece.minX - previous.maxX) / charWidth).rounded()) : 1
                line += String(repeating: " ", count: max(spaces, 1)) + fixLookAlikes(piece.text)
            }
            lines.append(line)
        }
        return snapIndents(lines).map { repairBrackets(normalizeSymbols($0)) }.joined(separator: "\n")
    }

    /// Straightens a tilted photo: rotates every line by the median text angle, then makes
    /// normalised boxes for `reconstruct`.
    public static func pieces(from lines: [OCRLine], imageSize: CGSize) -> [OCRPiece] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }
        let angles = lines.filter { $0.text.count >= 3 }.map {
            atan2($0.topRight.y - $0.topLeft.y, $0.topRight.x - $0.topLeft.x)
        }
        let angle = median(angles.map(Double.init))
        let straighten = abs(angle) > 0.3 * .pi / 180
        let centre = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let (c, s) = (cos(-angle), sin(-angle))
        func turn(_ p: CGPoint) -> CGPoint {
            guard straighten else { return p }
            let x = p.x - centre.x, y = p.y - centre.y
            return CGPoint(x: centre.x + x * c - y * s, y: centre.y + x * s + y * c)
        }
        return lines.map { line in
            let points = [line.topLeft, line.topRight, line.bottomLeft, line.bottomRight].map(turn)
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            return OCRPiece(text: line.text, minX: minX / imageSize.width, minY: minY / imageSize.height,
                            width: (maxX - minX) / imageSize.width, height: (maxY - minY) / imageSize.height)
        }
    }

    private static let symbols: [(String, String)] = [
        ("→", "->"), ("⇒", "=>"), ("≠", "!="), ("≤", "<="), ("≥", ">="), ("“", "\""), ("”", "\""),
        ("‘", "'"), ("’", "'"), ("…", "..."), ("—", "--"), ("–", "-"),
    ]

    /// Code-font ligatures and typography that OCR reads as single symbols, back to ASCII.
    public static func normalizeSymbols(_ line: String) -> String {
        symbols.reduce(line) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    private static let partner: [Character: Character] = ["(": ")", "[": "]", "{": "}", ")": "(", "]": "[", "}": "{"]
    /// OCR mostly mistakes other brackets for round ones, so the less round one wins.
    private static let strength: [Character: Int] = ["(": 0, ")": 0, "[": 1, "]": 1, "{": 2, "}": 2]

    /// Fixes pairs whose ends disagree, such as `("a": 1}` → `{"a": 1}`. Balanced lines are untouched.
    public static func repairBrackets(_ line: String) -> String {
        var chars = Array(line)
        var stack: [Int] = []
        for i in chars.indices {
            switch chars[i] {
            case "(", "[", "{":
                stack.append(i)
            case ")", "]", "}":
                guard let open = stack.popLast() else { continue }
                if partner[chars[open]] == chars[i] { continue }
                if strength[chars[open]]! < strength[chars[i]]! {
                    chars[open] = partner[chars[i]]!
                } else {
                    chars[i] = partner[chars[open]]!
                }
            default:
                continue
            }
        }
        return String(chars)
    }

    /// Indents one space off the code's indent step (2 or 4) snap to it.
    public static func snapIndents(_ lines: [String]) -> [String] {
        let indents = lines.map { $0.prefix { $0 == " " }.count }
        let step = indents.contains { $0 > 0 && $0 % 4 == 2 } ? 2 : 4
        return zip(lines, indents).map { line, indent in
            guard indent > 0, !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let snapped = Int((Double(indent) / Double(step) - 0.001).rounded()) * step
            guard abs(snapped - indent) == 1 else { return line }
            return String(repeating: " ", count: snapped) + line.drop { $0 == " " }
        }
    }

    /// Cyrillic/Greek letters that look like Latin ones, as OCR sometimes returns inside code.
    private static let lookAlikes: [Character: Character] = [
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y", "і": "i", "ј": "j", "ѕ": "s",
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X",
        "ο": "o", "α": "a", "ν": "v", "ρ": "p", "Ο": "O", "Α": "A", "Β": "B", "Ε": "E", "Κ": "K", "Μ": "M", "Ν": "N",
        "Τ": "T", "Χ": "X", "Ρ": "P", "Ι": "I", "Ζ": "Z",
    ]

    /// Swaps look-alike letters for Latin ones on lines that are at least half Latin; real Cyrillic/Greek text stays.
    public static func fixLookAlikes(_ line: String) -> String {
        let letters = line.filter(\.isLetter)
        let latin = letters.filter { $0.isASCII }.count
        guard latin * 2 >= letters.count, latin > 0 else { return line }
        return String(line.map { lookAlikes[$0] ?? $0 })
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

private extension Double {
    var nonZero: Double? { self > 0 ? self : nil }
}
