import ByteCacheCore
import Observation
import SwiftUI

/// Gathers a bug report. Nothing leaves the device here: "Continue on GitHub" opens a pre-filled
/// issue in the browser, where the user reviews it and decides whether to submit.
@MainActor @Observable
public final class ReportBugModel {
    public var title = ""
    public var whatHappened = ""
    public var steps = ""
    public var includeLogs = true

    public let device: DeviceInfo
    /// Recent activity with tokens, keys, emails, IP addresses and server addresses removed.
    public let logs: [String]

    public init(session: SessionManager, log: AppLog = .shared, device: DeviceInfo? = nil) {
        self.device = device ?? DeviceInfo.current
        let hosts = session.accounts.compactMap { $0.server.base.host() }
        logs = log.entries().map { LogScrubber.scrub($0, serverHosts: hosts) }
    }

    public var canSend: Bool { whatHappened.contains { !$0.isWhitespace } }

    public var report: BugReport {
        BugReport(title: title, whatHappened: whatHappened, steps: steps, device: device,
                  logs: includeLogs ? logs : [])
    }

    /// Whether the logs need attaching as a file because they're too long for the link.
    public var needsLogFile: Bool { includeLogs && !logs.isEmpty && !report.logsFitInLink }

    /// The log file to attach, written to a temporary folder.
    public func logFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: BugReport.logFileName)
        do {
            try report.logFileText.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

public struct ReportBugView: View {
    @Bindable var model: ReportBugModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    public init(model: ReportBugModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                TextField("Short title, e.g. “Scan shows no text”", text: $model.title)
                TextField("What happened? What did you expect?", text: $model.whatHappened, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Steps to reproduce (optional)", text: $model.steps, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("The problem")
            }

            Section {
                LabeledContent("ByteCache", value: model.device.app)
                LabeledContent("System", value: model.device.os)
                LabeledContent("Device", value: model.device.model)
                Toggle("Include recent activity", isOn: $model.includeLogs)
                if model.includeLogs {
                    NavigationLink {
                        LogPreview(lines: model.logs)
                    } label: {
                        LabeledContent("Preview activity", value: model.logs.isEmpty ? "Empty" : "\(model.logs.count) lines")
                    }
                }
            } header: {
                Text("Sent with the report")
            } footer: {
                Text("The activity log lists what ByteCache did recently, like requests and their results, sync and scans. It never contains your code, searches or passwords; tokens, keys, emails, IP addresses and your server addresses are removed. Continue opens a pre-filled issue on GitHub; nothing is sent until you submit it there.")
            }

            if model.needsLogFile, let file = model.logFile() {
                Section {
                    ShareLink(item: file) {
                        Label("Save or Share the Log File", symbol: .download)
                    }
                } header: {
                    Text("Log file")
                } footer: {
                    Text("The activity is too long to fit in the link. Save \(BugReport.logFileName), then drag it into the issue on GitHub.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Report a Bug")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") {
                    AppLog.shared.record("support", "opened a bug report on GitHub")
                    openURL(model.report.issueURL())
                    dismiss()
                }
                .disabled(!model.canSend)
                .help("Opens a pre-filled issue on GitHub to review and submit")
            }
        }
    }
}

private struct LogPreview: View {
    let lines: [String]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(lines.isEmpty ? "Nothing recorded yet." : lines.joined(separator: "\n"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Recent Activity")
    }
}
