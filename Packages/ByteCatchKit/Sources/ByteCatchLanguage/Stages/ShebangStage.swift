import Foundation

/// `#!` interpreter lines.
public struct ShebangStage: RuleStage {
    public init() {}

    private static let interpreters: [String: String] = [
        "python": "python", "bash": "bash", "sh": "bash", "zsh": "bash", "ksh": "bash", "dash": "bash",
        "node": "javascript", "nodejs": "javascript", "deno": "javascript", "bun": "javascript",
        "ts-node": "typescript", "tsx": "typescript", "pwsh": "powershell", "powershell": "powershell",
        "perl": "perl", "ruby": "ruby", "php": "php", "lua": "lua", "luajit": "lua", "rscript": "r",
        "julia": "julia", "swift": "swift", "groovy": "groovy", "scala": "scala", "kotlin": "kotlin",
    ]

    public func detect(_ input: DetectionInput) -> String? {
        let trimmed = input.text.drop { $0.isWhitespace }
        guard trimmed.hasPrefix("#!"), let firstLine = trimmed.split(whereSeparator: \.isNewline).first else { return nil }
        var tokens = firstLine.dropFirst(2).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        var program = (tokens.removeFirst() as NSString).lastPathComponent
        if program == "env" {
            tokens.removeAll { $0.hasPrefix("-") }
            guard let next = tokens.first else { return nil }
            program = next
        }
        // python3.12 → python, perl5 → perl
        let name = program.lowercased().replacing(/[\d.]+$/, with: "")
        return Self.interpreters[name]
    }
}
