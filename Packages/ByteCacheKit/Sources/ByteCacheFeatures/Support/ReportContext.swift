import ByteCacheCore
import Foundation
import Network

/// App details sent with a bug report: how ByteCache is set up and what state it's in. Settings and
/// counts only — no server addresses, names, snippets or anything typed.
public struct ReportContext: Equatable, Sendable {
    public struct Inputs: Equatable, Sendable {
        public var install: InstallSource
        public var language: String
        public var appearance: String
        public var languageIcons: String
        public var appIcon: String
        public var iCloudSync: Bool
        public var handoff: Bool
        public var appLock: Bool
        public var widgetsWhileLocked: String
        public var servers: Int
        /// "password", "API key" or "signed out".
        public var signIn: String
        public var network: String?
        public var lowPower: Bool
        /// How widgets get snippets (iPhone and iPad).
        public var widgets: String?
        /// The newest crash or hang the system reported, or that the last session ended unexpectedly.
        public var lastProblem: String?
    }

    public let lines: [String]

    public init(_ i: Inputs) {
        func onOff(_ value: Bool) -> String { value ? "on" : "off" }
        var lines = [
            "Installed from: \(i.install == .appStore ? "App Store or TestFlight" : "GitHub or Xcode")",
            "Language: \(i.language)",
            "Look: \(i.appearance) · \(i.languageIcons) language icons · \(i.appIcon) app icon",
            "iCloud Sync: \(onOff(i.iCloudSync)) · Handoff: \(onOff(i.handoff)) · App Lock: \(onOff(i.appLock))"
                + (i.appLock ? " (widgets: \(i.widgetsWhileLocked))" : ""),
            "Servers: \(i.servers) · Signed in with: \(i.signIn)",
            (i.network.map { "Network: \($0) · " } ?? "") + "Low Power Mode: \(onOff(i.lowPower))",
        ]
        if let widgets = i.widgets { lines.append("Widgets: \(widgets)") }
        if let problem = i.lastProblem { lines.append("Last problem: \(problem)") }
        self.lines = lines
    }

    public static let empty = ReportContext(lines: [])

    private init(lines: [String]) {
        self.lines = lines
    }
}

extension ReportContext {
    /// Builds the context from the running app.
    @MainActor
    static func current(settings: AppSettings, session: SessionManager, network: String?) -> ReportContext {
        let active = session.accounts.first { $0.id == session.activeAccountID }
        let signIn = switch (active?.apiKey != nil, active?.isSignedIn ?? false) {
        case (true, _): "API key"
        case (false, true): "password"
        default: "signed out"
        }
        let crash = CrashWatch.shared
        let lastProblem = crash.latestDiagnostic().map {
            "\($0.summary) on \($0.date.formatted(.iso8601.year().month().day()))"
        } ?? (crash.endedUnexpectedly ? "the last session ended unexpectedly" : nil)
        #if os(iOS)
        let widgets: String? = WidgetSnapshotStore().sharing
        #else
        let widgets: String? = nil
        #endif
        return ReportContext(Inputs(
            install: .current,
            language: Locale.preferredLanguages.first ?? Locale.current.identifier,
            appearance: settings.appearance.title,
            languageIcons: settings.languageIconStyle.title,
            appIcon: AppIconChoice(iconName: SystemAppIconSwitcher.shared.currentName).title,
            iCloudSync: settings.iCloudSyncEnabled,
            handoff: settings.handoffEnabled,
            appLock: AppEnvironment.isAppLockEnabled,
            widgetsWhileLocked: WidgetLockMode.stored().title,
            servers: session.accounts.count,
            signIn: signIn,
            network: network,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            widgets: widgets,
            lastProblem: lastProblem))
    }

    /// The connection type right now ("Wi-Fi", "Cellular", "Wired", "Offline"), or nil if unknown.
    static func networkType() async -> String? {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                let type: String = if path.status != .satisfied { "Offline" }
                    else if path.usesInterfaceType(.wifi) { "Wi-Fi" }
                    else if path.usesInterfaceType(.cellular) { "Cellular" }
                    else if path.usesInterfaceType(.wiredEthernet) { "Wired" }
                    else { "Other" }
                continuation.resume(returning: type)
            }
            monitor.start(queue: DispatchQueue(label: "ReportContext.network"))
        }
    }
}
