import ByteCacheCore
import Observation
import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif
#if os(macOS)
import AppKit
#endif

/// Gathers a bug report. Nothing leaves the device here: GitHub, email or a copy each hand the
/// finished report to the user, who reviews it and decides whether to send it.
@MainActor @Observable
public final class ReportBugModel {
    public var title: String
    public var whatHappened = ""
    public var steps = ""
    public var includeLogs = true
    public let device: DeviceInfo
    /// Recent activity with tokens, keys, emails, IP addresses and server addresses removed.
    public let logs: [String]
    /// App details; filled in by the view, which knows the settings.
    public private(set) var context: ReportContext = .empty
    /// The system's newest crash or hang report, if there is one.
    public let diagnostic: CrashWatch.Diagnostic?
    @ObservationIgnored let session: SessionManager

    public init(session: SessionManager, log: AppLog = .shared, device: DeviceInfo? = nil, title: String = "") {
        self.title = title
        self.session = session
        self.device = device ?? DeviceInfo.current
        let hosts = session.accounts.compactMap { $0.server.base.host() }
        logs = log.entries().map { LogScrubber.scrub($0, serverHosts: hosts) }
        diagnostic = CrashWatch.shared.latestDiagnostic()
    }

    func loadContext(settings: AppSettings, session: SessionManager) async {
        context = ReportContext.current(settings: settings, session: session, network: await ReportContext.networkType())
    }

    public var canSend: Bool { whatHappened.contains { !$0.isWhitespace } }

    public var report: BugReport {
        BugReport(title: title, whatHappened: whatHappened, steps: steps, device: device,
                  logs: includeLogs ? logs : [], context: includeLogs ? context.lines : [],
                  diagnostic: includeLogs ? diagnostic.map { String(decoding: $0.json, as: UTF8.self) } : nil)
    }

    /// Whether the logs need attaching as a file because they're too long for the link.
    public var needsLogFile: Bool { includeLogs && !logs.isEmpty && (!report.logsFitInLink || diagnostic != nil) }

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
    /// True when shown on its own (after a crash, or the Mac's Help menu) rather than inside Settings.
    var showsCancel = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var mailFile: MailDraft?
    @State private var copied = false

    public init(model: ReportBugModel, showsCancel: Bool = false) {
        self.model = model
        self.showsCancel = showsCancel
    }

    public var body: some View {
        SettingsList {
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
                Toggle("Include App Details and Activity", isOn: $model.includeLogs)
                if model.includeLogs {
                    NavigationLink {
                        ReportPreview(report: model.report, diagnostic: model.diagnostic)
                    } label: {
                        LabeledContent("Preview Everything", value: "\(model.context.lines.count + model.logs.count) lines")
                    }
                }
            } header: {
                Text("Sent with the report")
            } footer: {
                Text("App details are your settings and counts, like the number of servers. The activity lists what ByteCache did recently, like requests and their results, screens and errors. Neither contains your code, searches, server addresses or passwords. Crash reports come from iOS or macOS and contain no personal data.")
            }
            Section {
                sendButton("Open GitHub Issue", detail: "Needs a GitHub account", symbol: .bug, color: .black) {
                    AppLog.shared.record("support", "opened a bug report on GitHub")
                    openURL(model.report.issueURL())
                    dismiss()
                }
                sendButton("Send by Email", detail: AboutText.contactEmail, symbol: .mail, color: .blue) {
                    AppLog.shared.record("support", "wrote a bug report email")
                    email()
                }
                sendButton(copied ? "Copied" : "Copy Report", detail: "Paste it anywhere", symbol: .copy, color: .gray) {
                    Pasteboard.copy(model.report.plainText)
                    copied = true
                }
            } header: {
                Text("Send")
            } footer: {
                Text("You see the report before anything is sent: GitHub and Mail open it for you to check and submit.")
            }
            if model.needsLogFile, let file = model.logFile() {
                Section {
                    ShareLink(item: file) {
                        Label("Save or Share the Log File", symbol: .download)
                    }
                } header: {
                    Text("Log file")
                } footer: {
                    Text("For a GitHub issue: the details don't all fit in the link. Save \(BugReport.logFileName), then drag it into the issue. Email attaches it for you.")
                }
            }
        }
        .navigationTitle("Report a Bug")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await model.loadContext(settings: settings, session: model.session) }
        .onChange(of: model.whatHappened) { copied = false }
        #if os(iOS)
        .sheet(item: $mailFile) { draft in
            MailComposer(draft: draft) { dismiss() }
                .ignoresSafeArea()
        }
        #endif
        .logScreen("Report a bug")
    }

    private func sendButton(_ title: String, detail: String, symbol: AppSymbol, color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsIcon(symbol, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(model.canSend ? .primary : .secondary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canSend)
    }

    /// The system mail sheet with the log attached where it can; otherwise a mail link.
    private func email() {
        let report = model.report
        let file = model.includeLogs ? model.logFile() : nil
        #if os(iOS)
        if MFMailComposeViewController.canSendMail() {
            mailFile = MailDraft(subject: "ByteCache bug: \(report.issueTitle)", body: report.plainText, attachment: file)
            return
        }
        #elseif os(macOS)
        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = [AboutText.contactEmail]
            service.subject = "ByteCache bug: \(report.issueTitle)"
            service.perform(withItems: [report.plainText] + (file.map { [$0] } ?? []))
            return
        }
        #endif
        openURL(report.mailURL())
    }
}

/// Everything that goes with the report, exactly as it will be sent.
private struct ReportPreview: View {
    let report: BugReport
    let diagnostic: CrashWatch.Diagnostic?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 16) {
                block("App details", report.context)
                block("Recent activity", report.logs.isEmpty ? ["Nothing recorded yet."] : report.logs)
                if let diagnostic {
                    block("Crash or hang report from the system",
                          ["\(diagnostic.summary) on \(diagnostic.date.formatted(date: .abbreviated, time: .shortened))",
                           "The full report (call stacks, no personal data) goes in \(BugReport.logFileName)."])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Preview")
    }

    private func block(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(lines.joined(separator: "\n"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

struct MailDraft: Identifiable {
    let id = UUID()
    let subject: String
    let body: String
    let attachment: URL?
}

#if os(iOS)
/// The system mail sheet, addressed to the developer with the log file attached.
private struct MailComposer: UIViewControllerRepresentable {
    let draft: MailDraft
    let onSent: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSent: onSent) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([AboutText.contactEmail])
        mail.setSubject(draft.subject)
        mail.setMessageBody(draft.body, isHTML: false)
        if let url = draft.attachment, let data = try? Data(contentsOf: url) {
            mail.addAttachmentData(data, mimeType: "text/plain", fileName: BugReport.logFileName)
        }
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onSent: () -> Void
        init(onSent: @escaping () -> Void) { self.onSent = onSent }

        nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            // Mail calls back on the main thread.
            MainActor.assumeIsolated {
                controller.dismiss(animated: true)
                if result == .sent { onSent() }
            }
        }
    }
}
#endif
