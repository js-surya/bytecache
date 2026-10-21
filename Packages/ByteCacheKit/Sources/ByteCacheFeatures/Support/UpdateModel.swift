import ByteCacheCore
import Foundation
import Observation
import SwiftUI

/// Decides when to show "ByteCache X is available" and "What's New" (CP-25).
@MainActor @Observable
public final class UpdateModel {
    /// A newer release to offer; drives the update sheet.
    public var offered: GitHubRelease?
    /// The running version's notes after an update; drives the What's New sheet.
    public var whatsNew: GitHubRelease?
    public private(set) var isChecking = false
    /// Result of the last "Check Now", for Settings.
    public private(set) var status: String?

    /// False for App Store and TestFlight copies: Apple updates those, so Settings hides Updates.
    public let offersUpdates: Bool

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let checker: UpdateChecker
    @ObservationIgnored private var askedWhatsNew = false

    public init(settings: AppSettings, checker: UpdateChecker = UpdateChecker(), source: InstallSource = .current) {
        self.settings = settings
        self.checker = checker
        offersUpdates = source == .direct
    }

    public static var platform: GitHubRelease.Platform {
        #if os(macOS)
        .macOS
        #else
        .iOS
        #endif
    }

    /// On launch and whenever the app comes back: What's New once after an update, then the daily check.
    public func appBecameActive() async {
        if !askedWhatsNew {
            askedWhatsNew = true
            if checker.takeWhatsNew(), let release = await checker.currentRelease() {
                whatsNew = release
            }
        }
        guard offersUpdates, settings.checkForUpdates, offered == nil else { return }
        if case .available(let release) = await checker.check(force: false) { offered = release }
    }

    /// Settings → Check Now: always asks GitHub and says what it found.
    public func checkNow() async {
        guard offersUpdates else { return }
        isChecking = true
        defer { isChecking = false }
        switch await checker.check(force: true) {
        case .available(let release):
            offered = release
            status = "ByteCache \(release.version) is available."
        case .upToDate:
            status = "ByteCache \(checker.version) is the latest version."
        case .failed, .skippedRecentlyChecked:
            status = "Couldn't reach GitHub. Try again later."
        }
    }

    /// The version this app reports (Debug builds can pretend to be older).
    public var runningVersion: AppVersion { checker.version }

    public func skipOffered() {
        if let offered { checker.skip(offered.version) }
        offered = nil
    }
}

/// The update and What's New sheet.
public struct UpdateSheet: View {
    public enum Kind { case update, whatsNew }

    let release: GitHubRelease
    let kind: Kind
    var current: AppVersion = .current
    let onSkip: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(release: GitHubRelease, kind: Kind, current: AppVersion = .current, onSkip: @escaping () -> Void = {}) {
        self.release = release
        self.kind = kind
        self.current = current
        self.onSkip = onSkip
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind == .update ? "ByteCache \(release.version) is available" : "What's New in ByteCache \(release.version)")
                            .font(.title2.weight(.bold))
                        if kind == .update {
                            Text("You have \(current). ByteCache is installed from GitHub, so updates are downloaded there.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    MarkdownView(release.notes.isEmpty ? "No release notes." : ReleaseNotes.forDisplay(release.notes))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(kind == .update ? "Update" : "What's New")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(kind == .update ? "Later" : "Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if kind == .update {
                    VStack(spacing: 10) {
                        if let file = release.download(for: UpdateModel.platform) {
                            Button {
                                openURL(file)
                                dismiss()
                            } label: {
                                Label("Download \(file.lastPathComponent)", symbol: .download).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        HStack {
                            Button("View on GitHub") { openURL(release.page) }
                            Spacer()
                            Button("Skip This Version") {
                                onSkip()
                                dismiss()
                            }
                            .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(.bar)
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

/// Release notes as shown in the update sheet.
enum ReleaseNotes {
    /// Drops the "Install" section (the sheet has its own Download button), turns tables into plain
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
