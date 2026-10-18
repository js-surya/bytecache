import Foundation

/// File names, URL paths and editor modelines.
public struct HintStage: RuleStage {
    public init() {}

    public func detect(_ input: DetectionInput) -> String? {
        if let name = input.fileName, let id = Self.fromFileName(name) { return id }
        if let url = input.sourceURL, let id = Self.fromURL(url) { return id }
        return Self.fromModeline(input.text)
    }

    static func fromFileName(_ name: String) -> String? {
        let base = (name as NSString).lastPathComponent
        if let id = LanguageCatalog.fileNames[base.lowercased()] { return id }
        let ext = (base as NSString).pathExtension
        return ext.isEmpty ? nil : LanguageCatalog.id(forExtension: ext)
    }

    static func fromURL(_ url: URL) -> String? {
        // Gist anchors look like `#file-run-sh`: the last dash-separated piece is the extension.
        if let fragment = url.fragment, fragment.hasPrefix("file-"),
           let ext = fragment.split(separator: "-").last,
           let id = LanguageCatalog.id(forExtension: String(ext)) {
            return id
        }
        let last = url.lastPathComponent
        guard last.contains(".") || LanguageCatalog.fileNames[last.lowercased()] != nil else { return nil }
        return fromFileName(last)
    }

    // vim: `vim: ft=ruby`, `vim: set filetype=python :`; emacs: `-*- mode: lua -*-`, `-*- python -*-`.
    nonisolated(unsafe) private static let vimModeline = /(?:vim?|ex):\s*(?:set\s+)?(?:ft|filetype|syntax)=([\w+#-]+)/
    nonisolated(unsafe) private static let emacsModeline = /-\*-\s*(?:.*?mode:\s*)?([\w+#-]+)\s*(?:;.*?)?-\*-/

    static func fromModeline(_ text: String) -> String? {
        let lines = text.meaningfulLines(limit: .max)
        let candidates = lines.prefix(5) + lines.suffix(5)
        for line in candidates {
            if let match = line.firstMatch(of: vimModeline) ?? line.firstMatch(of: emacsModeline),
               let id = LanguageCatalog.id(forAlias: String(match.1).replacingOccurrences(of: "-mode", with: "")) {
                return id
            }
        }
        return nil
    }
}
