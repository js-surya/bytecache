import ByteCacheCore
import Foundation
import Observation
import SwiftUI

/// Shows "What's New" once after an update (CP-25). Updates themselves come through TestFlight and
/// the App Store.
@MainActor @Observable
public final class UpdateModel {
    /// The running version's notes after an update; drives the What's New sheet.
    public var whatsNew: GitHubRelease?

    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private var askedWhatsNew = false

    public init(checker: UpdateChecker = UpdateChecker()) {
        self.checker = checker
    }

    /// On launch: What's New once after an update.
    public func appBecameActive() async {
        guard !askedWhatsNew else { return }
        askedWhatsNew = true
        if checker.takeWhatsNew(), let release = await checker.currentRelease() {
            whatsNew = release
        }
    }
}

/// The What's New sheet: the release notes of the version that's now running.
public struct WhatsNewSheet: View {
    let release: GitHubRelease
    @Environment(\.dismiss) private var dismiss

    public init(release: GitHubRelease) {
        self.release = release
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What's New in ByteCache \(release.version)")
                        .font(.title2.weight(.bold))
                    MarkdownView(release.notes.isEmpty ? "No release notes." : ReleaseNotes.forDisplay(release.notes))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("What's New")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}

extension GitHubRelease: Identifiable {
    public var id: String { version.description }
}

/// Release notes as shown in What's New.
enum ReleaseNotes {
    /// Drops the "Install" section (the app is already installed), turns tables into plain
    /// lines (the Markdown view doesn't draw tables) and removes commit-type prefixes like "fix(ui): ".
    static func forDisplay(_ notes: String) -> String {
        var lines: [String] = []
        var skippingInstall = false
        for raw in notes.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                skippingInstall = line.range(of: #"^#+\s*Install\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                if skippingInstall { continue }
            }
            if skippingInstall { continue }
            if line.hasPrefix("|") {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if cells.allSatisfy({ $0.allSatisfy { "-:".contains($0) } }) { continue } // |---|---|
                lines.append("- " + cells.joined(separator: " · "))
                continue
            }
            lines.append(Self.withoutCommitType(raw))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "- fix(scan): fall back…" → "- Fall back…"
    private static func withoutCommitType(_ line: String) -> String {
        guard let match = line.range(of: #"^\s*[-*]\s+[a-z]+(\([^)]*\))?!?:\s+"#, options: .regularExpression) else { return line }
        let bullet = line[match].prefix { $0 == " " || $0 == "-" || $0 == "*" }
        let rest = line[match.upperBound...]
        return bullet + rest.prefix(1).uppercased() + rest.dropFirst()
    }
}
