#if os(macOS)
import ByteCacheCore
import SwiftUI

/// Mac Settings in the style of System Settings: every setting in a sidebar, the chosen page beside
/// it. No back buttons; the same pages as on iPhone and iPad.
public struct MacSettingsView: View {
    let session: SessionManager
    @State private var page: MacSettingsPage? = .account
    @Environment(AppSettings.self) private var settings
    @Environment(AppLockModel.self) private var lock

    public init(session: SessionManager) {
        self.session = session
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $page) {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    let pages = MacSettingsPage.allCases.filter { $0.section == section && $0.isAvailable(session) }
                    if !pages.isEmpty {
                        Section(section.title) {
                            ForEach(pages) { page in
                                SettingsLabel(title: page.title, symbol: page.symbol(lock), color: page.color).tag(page)
                            }
                        }
                    }
                }
            }
            // Fixed, like System Settings. The Settings window ignores the column width on its own and
            // drew the sidebar at 144 pt, cutting the labels off ("Ser…", "Ap…"); the frame enforces it.
            .frame(minWidth: 230)
            .navigationSplitViewColumnWidth(230)
            // Like System Settings: the sidebar always shows, so no hide-sidebar button.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack {
                if let page {
                    detail(page).id(page)
                } else {
                    ContentUnavailableView("Settings", symbol: .settings)
                }
            }
        }
        // Signed out, Account and its pages aren't in the sidebar: open the first page that is.
        .onAppear(perform: showAvailablePage)
        .onChange(of: session.state) { showAvailablePage() }
    }

    private func showAvailablePage() {
        guard page.map({ !$0.isAvailable(session) }) ?? true else { return }
        page = MacSettingsPage.allCases.first { $0.isAvailable(session) }
    }

    @ViewBuilder
    private func detail(_ page: MacSettingsPage) -> some View {
        switch page {
        case .account: AccountSettingsView(session: session, showsAccountPages: false)
        case .apiKeys: APIKeysView(model: AccountModel(session: session))
        case .password: ChangePasswordView(model: AccountModel(session: session))
        case .servers: ServersView(session: session)
        case .assistants: MCPSettingsView(model: MCPSettingsModel(session: session))
        case .appearance: AppearanceSettingsView()
        case .codeTheme: CodeThemeSettingsView()
        case .haptics: HapticsSettingsView()
        case .search: MacSearchPage()
        case .suggestions: SuggestionsSettingsView()
        case .appLock: AppLockSettingsView(lock: lock)
        case .privacy: PrivacyInfoView()
        case .iCloud: ICloudSyncSettingsView()
        case .handoff: HandoffSettingsView()
        case .backup: BackupView(model: BackupModel(session: session))
        case .reportBug: ReportBugView(model: ReportBugModel(session: session))
        case .about: AboutView()
        }
    }
}

enum MacSettingsPage: String, CaseIterable, Identifiable, Hashable {
    case account, apiKeys, password, servers, assistants
    case appearance, codeTheme, haptics
    case search, suggestions
    case appLock, privacy
    case iCloud, handoff
    case backup
    case reportBug, about

    var id: String { rawValue }

    var section: SettingsSection {
        switch self {
        case .account, .apiKeys, .password, .servers, .assistants: .account
        case .appearance, .codeTheme, .haptics: .lookAndFeel
        case .search, .suggestions: .snippets
        case .appLock, .privacy: .privacy
        case .iCloud, .handoff, .backup: .sync
        case .reportBug, .about: .support
        }
    }

    var title: String {
        switch self {
        case .account: "Account"
        case .apiKeys: "API Keys"
        case .password: "Change Password"
        case .servers: "Servers"
        case .assistants: "AI Assistants"
        case .appearance: "Appearance"
        case .codeTheme: "Code Theme"
        case .haptics: "Haptics"
        case .search: "Search"
        case .suggestions: "Smart Suggestions"
        case .appLock: "App Lock"
        case .privacy: "Privacy"
        case .iCloud: "iCloud Sync"
        case .handoff: "Handoff"
        case .backup: "Backup & Import"
        case .reportBug: "Report a Bug"
        case .about: "About"
        }
    }

    @MainActor
    func symbol(_ lock: AppLockModel) -> AppSymbol {
        switch self {
        case .account: .signedOut
        case .apiKeys: .key
        case .password: .changePassword
        case .servers: .server
        case .assistants: .assistant
        case .appearance: .appearance
        case .codeTheme: .code
        case .haptics: .haptics
        case .search: .search
        case .suggestions: .sparkles
        case .appLock: lock.biometry.symbol
        case .privacy: .privacy
        case .iCloud: .icloud
        case .handoff: .handoff
        case .backup: .download
        case .reportBug: .bug
        case .about: .info
        }
    }

    var color: Color {
        switch self {
        case .account: .blue
        case .apiKeys: .orange
        case .password: .gray
        case .servers: .green
        case .assistants: .indigo
        case .appearance: .blue
        case .codeTheme: .purple
        case .haptics: .red
        case .search: .indigo
        case .suggestions: .pink
        case .appLock: .green
        case .privacy: .blue
        case .iCloud: .cyan
        case .handoff: .blue
        case .backup: .teal
        case .reportBug: .red
        case .about: .gray
        }
    }

    /// Account pages need a signed-in session.
    @MainActor
    func isAvailable(_ session: SessionManager) -> Bool {
        switch self {
        case .account, .apiKeys, .password, .assistants:
            if case .signedIn = session.state { return true }
            return false
        default:
            return true
        }
    }
}

/// Who's signed in, where, and Sign Out.
/// Search options (a toggle on iPhone's main Settings list).
private struct MacSearchPage: View {
    @Environment(AppSettings.self) private var settings

    private var usesPaste: Bool {
        settings.quickSearchReturnAction == .paste || settings.quickSearchOptionReturnAction == .paste
    }

    var body: some View {
        @Bindable var settings = settings
        SettingsList {
            Section {
                Toggle("Search Inside Code", isOn: $settings.searchInCode)
            } footer: {
                FooterText("When on, searching also matches the code in your snippets, not just titles and descriptions.")
            }
            Section {
                Toggle("Show in Menu Bar", isOn: $settings.quickSearchInMenuBar)
                    .disabled(settings.menuBarOnly)
                Picker("Keyboard Shortcut", selection: $settings.quickSearchShortcut) {
                    ForEach(QuickSearchShortcut.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Quick Search")
            } footer: {
                FooterText("Find a snippet from anywhere: press the shortcut or click the menu bar icon, type, then choose a snippet with Return. ⌘Return always opens it in ByteCache.")
            }
            Section {
                Picker("Return", selection: $settings.quickSearchReturnAction) {
                    ForEach(QuickSearchAction.allCases) { Text($0.title).tag($0) }
                }
                Picker("⌥ Return", selection: $settings.quickSearchOptionReturnAction) {
                    ForEach(QuickSearchAction.allCases) { Text($0.title).tag($0) }
                }
                if usesPaste {
                    PastePermissionRow()
                }
            } header: {
                Text("Choosing a Snippet")
            } footer: {
                FooterText("Paste into Active App puts the snippet straight into the app you were using. It needs Accessibility permission to press ⌘V there; without it, the snippet is copied instead.")
            }
            Section {
                Picker("Starts With", selection: $settings.quickSearchStart) {
                    Text("Recent").tag(QuickSearchStart.recent)
                    Text("Pinned").tag(QuickSearchStart.pinned)
                    Text("Favorites").tag(QuickSearchStart.favorites)
                    if !settings.smartGroups.isEmpty {
                        Divider()
                        ForEach(settings.smartGroups) { Text($0.name).tag(QuickSearchStart.smartGroup($0.id)) }
                    }
                }
                Toggle("Clear Search When Opened", isOn: $settings.quickSearchClearsOnOpen)
                Picker("Menu Bar Window Size", selection: $settings.menuBarPanelSize) {
                    ForEach(MenuBarPanelSize.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Menu Bar Only", isOn: $settings.menuBarOnly)
            } header: {
                Text("Menu Bar")
            } footer: {
                FooterText("Menu Bar Only hides ByteCache from the Dock and the app switcher; open the main window from the menu bar icon. Takes effect right away.")
            }
        }
        .navigationTitle("Search")
    }
}
/// Whether Paste into Active App can work yet, with a way to allow it. Rechecked when ByteCache
/// comes back to the front (after a visit to System Settings).
private struct PastePermissionRow: View {
    @State private var allowed = ActiveAppPaster.shared.isAllowed

    var body: some View {
        HStack {
            if allowed {
                Label("Accessibility allowed", symbol: .checkCircle).foregroundStyle(.green)
            } else {
                Label("Accessibility not allowed yet", symbol: .warning).foregroundStyle(.orange)
                Spacer()
                Button("Allow…") {
                    ActiveAppPaster.shared.askForPermission()
                    ActiveAppPaster.shared.openAccessibilitySettings()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            allowed = ActiveAppPaster.shared.isAllowed
        }
    }
}
#endif
