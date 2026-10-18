import Foundation

/// Unambiguous document shapes: parses, prologs and anchored first-line forms.
/// Every rule needs more than one weak signal, so ordinary code falls through to the classifier.
public struct StructuralStage: RuleStage {
    public init() {}

    public func detect(_ input: DetectionInput) -> String? {
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lines = text.meaningfulLines()
        let lower = text.prefix(200).lowercased()

        if Self.isJSON(text) { return "json" }
        if lower.hasPrefix("<?xml") { return "xml" }
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") { return "html" }
        if lower.hasPrefix("<?php") { return "php" }
        if Self.isGo(lines) { return "go" }
        if Self.isDockerfile(lines) { return "dockerfile" }
        if Self.isKubernetes(lines) { return "kubernetes" }
        if let config = Self.configFormat(lines) { return config }
        if Self.isSQL(lines) { return "sql" }
        if Self.isYAML(lines) { return "yaml" }
        if Self.isMarkdown(lines) { return "markdown" }
        return nil
    }

    static func isJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[",
              let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    static func isGo(_ lines: [Substring]) -> Bool {
        guard let first = lines.first(where: { !$0.hasPrefix("//") }),
              first.wholeMatch(of: /package [a-z_][a-z0-9_]*\s*/) != nil else { return false }
        return lines.contains { $0.hasPrefix("import") || $0.hasPrefix("func ") || $0.hasPrefix("type ") }
    }

    private static let dockerDirectives: Set<String> = [
        "RUN", "COPY", "CMD", "ENTRYPOINT", "WORKDIR", "ENV", "EXPOSE", "ARG", "ADD", "USER", "LABEL", "VOLUME",
    ]

    static func isDockerfile(_ lines: [Substring]) -> Bool {
        let code = lines.filter { !$0.hasPrefix("#") }
        guard let first = code.first, first.wholeMatch(of: /FROM\s+\S+(\s+AS\s+\S+)?\s*/.ignoresCase()) != nil else {
            return false
        }
        return code.dropFirst().contains { line in
            dockerDirectives.contains(String(line.prefix { !$0.isWhitespace }))
        }
    }

    static func isKubernetes(_ lines: [Substring]) -> Bool {
        lines.contains { $0.hasPrefix("apiVersion:") } && lines.contains { $0.hasPrefix("kind:") }
    }

    nonisolated(unsafe) private static let sectionHeader = /\[{1,2}[\w.\- "]+\]{1,2}\s*/
    nonisolated(unsafe) private static let assignment = /([\w.\-"]+)\s*=\s*(.*)/
    nonisolated(unsafe) private static let tomlValue = /(".*"|'.*'|-?\d[\d_.eE+\-:TZ]*|true|false|\[.*|\{.*|""".*|'''.*)\s*(#.*)?/

    /// TOML vs INI: both are `[section]` + `key = value`; TOML values must be typed literals.
    static func configFormat(_ lines: [Substring]) -> String? {
        let body = lines.filter { !$0.hasPrefix("#") && !$0.hasPrefix(";") }
        guard body.contains(where: { $0.wholeMatch(of: sectionHeader) != nil }) else { return nil }
        let assignments = body.compactMap { $0.wholeMatch(of: assignment) }
        let others = body.filter { $0.wholeMatch(of: sectionHeader) == nil && $0.wholeMatch(of: assignment) == nil }
        guard !assignments.isEmpty, others.isEmpty else { return nil }
        let typed = assignments.allSatisfy { $0.2.wholeMatch(of: tomlValue) != nil }
        return typed ? "toml" : "ini"
    }

    nonisolated(unsafe) private static let sqlStart =
        /(?i)(select\s.+\sfrom\s|insert\s+into\s|update\s+\S+\s+set\s|delete\s+from\s|create\s+(or\s+replace\s+)?(table|index|view|unique\s+index|function|procedure)\s|alter\s+table\s|drop\s+(table|index|view)\s|with\s+\w+\s+as\s*\()/

    static func isSQL(_ lines: [Substring]) -> Bool {
        let code = lines.filter { !$0.hasPrefix("--") }
        guard let first = code.first else { return false }
        // Join the first statement so multi-line SELECT … FROM is seen whole.
        let statement = code.prefix(8).joined(separator: " ")
        return first.prefixMatch(of: /(?i)(select|insert|update|delete|create|alter|drop|with)\s/) != nil
            && statement.prefixMatch(of: sqlStart) != nil
    }

    nonisolated(unsafe) private static let yamlLine = /\s*(-\s+.*|-\s*|[\w.\-"']+:(\s.*)?|#.*)/

    static func isYAML(_ lines: [Substring]) -> Bool {
        let startsWithMarker = lines.first == "---"
        let body = lines.drop { $0 == "---" }
        guard body.count >= (startsWithMarker ? 1 : 3),
              body.allSatisfy({ $0.wholeMatch(of: yamlLine) != nil }) else { return false }
        // Needs at least one key, and no code punctuation that YAML values rarely end with.
        return body.contains { $0.contains(":") } && !body.contains { $0.hasSuffix(";") || $0.hasSuffix("{") }
    }

    static func isMarkdown(_ lines: [Substring]) -> Bool {
        var signals = 0
        if lines.contains(where: { $0.prefixMatch(of: /#{1,6}\s+\S/) != nil }) { signals += 1 }
        if lines.contains(where: { $0.prefixMatch(of: /\s*([-*+]|\d+\.)\s+\S/) != nil }) { signals += 1 }
        let strong = lines.contains { $0.firstMatch(of: /\[[^\]]+\]\([^)]+\)/) != nil || $0.hasPrefix("```") }
        if strong { signals += 1 }
        return strong && signals >= 2
    }
}
