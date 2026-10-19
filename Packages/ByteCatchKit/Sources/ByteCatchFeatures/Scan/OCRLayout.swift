import Foundation

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
        return lines.joined(separator: "\n")
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
