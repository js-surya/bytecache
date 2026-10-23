import ByteCacheCore
import SwiftUI

/// The groups on the Settings screen, in order.
enum SettingsSection: CaseIterable {
    case account, lookAndFeel, snippets, privacy, sync, support

    var title: String {
        switch self {
        case .account: "Account"
        case .lookAndFeel: "Look & Feel"
        case .snippets: "Snippets"
        case .privacy: "Privacy & Security"
        case .sync: "Sync & Backup"
        case .support: "Support"
        }
    }
}

/// Settings in the style of the iOS Settings app: grouped rows with coloured icons.
public struct SettingsView: View {
    let session: SessionManager
    @Environment(AINoteStore.self) private var aiNotes: AINoteStore?
    @Environment(AppSettings.self) private var settings
    @Environment(AppLockModel.self) private var lock

    public init(session: SessionManager) {
        self.session = session
    }

    public var body: some View {
        SettingsList {
            if case .signedIn(let server, let user) = session.state {
                Section {
                    NavigationLink {
                        AccountSettingsView(session: session)
                    } label: {
                        ProfileCard(user: user, server: server, serverName: activeServerName)
                    }
                }
            }

            Section {
                NavigationLink {
                    ServersView(session: session)
                } label: {
                    SettingsLabel(title: "Servers", symbol: .server, color: .green,
                                  value: session.accounts.count > 1 ? "\(session.accounts.count)" : nil)
                }
                if case .signedIn = session.state {
                    NavigationLink {
                        MCPSettingsView(model: MCPSettingsModel(session: session))
                    } label: {
                        SettingsLabel(title: "AI Assistants", symbol: .assistant, color: .indigo)
                    }
                }
            }

            Section {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsLabel(title: "Appearance", symbol: .appearance, color: .blue,
                                  value: settings.appearance.title)
                }
                NavigationLink {
                    CodeThemeSettingsView()
                } label: {
                    SettingsLabel(title: "Code Theme", symbol: .code,
                                  color: .purple, value: settings.codeTheme.name)
                }
                NavigationLink {
                    HapticsSettingsView()
                } label: {
                    SettingsLabel(title: "Haptics", symbol: .haptics, color: .red,
                                  value: settings.hapticsEnabled ? settings.hapticStrength.title : "Off")
                }
            } header: {
                Text(SettingsSection.lookAndFeel.title)
            }

            Section {
                Toggle(isOn: Binding(get: { settings.searchInCode }, set: { settings.searchInCode = $0 })) {
                    SettingsLabel(title: "Search Inside Code", symbol: .search, color: .indigo)
                }
                // Devices that can't run Apple Intelligence don't show it, unless notes from another device
                // are here to manage.
                if !AIAvailability.current.hidesFeatures || (aiNotes?.count ?? 0) > 0 {
                    NavigationLink {
                        SuggestionsSettingsView()
                    } label: {
                        SettingsLabel(title: "Smart Suggestions", symbol: .sparkles, color: .pink,
                                      value: settings.suggestionsEnabled && AIAvailability.current == .available ? "On" : "Off")
                    }
                }
            } header: {
                Text(SettingsSection.snippets.title)
            } footer: {
                FooterText("Search Inside Code also matches the code itself, not just titles and descriptions.")
            }

            Section {
                NavigationLink {
                    AppLockSettingsView(lock: lock)
                } label: {
                    SettingsLabel(title: "App Lock", symbol: lock.biometry.symbol, color: .green,
                                  value: lock.isEnabled ? lock.biometry.name : "Off")
                }
                NavigationLink {
                    PrivacyInfoView()
                } label: {
                    SettingsLabel(title: "Privacy", symbol: .privacy, color: .blue)
                }
            } header: {
                Text(SettingsSection.privacy.title)
            }

            Section {
                NavigationLink {
                    ICloudSyncSettingsView()
                } label: {
                    SettingsLabel(title: "iCloud Sync", symbol: .icloud, color: .cyan,
                                  value: settings.iCloudSyncEnabled ? "On" : "Off")
                }
                NavigationLink {
                    HandoffSettingsView()
                } label: {
                    SettingsLabel(title: "Handoff", symbol: .handoff, color: .blue,
                                  value: settings.handoffEnabled ? "On" : "Off")
                }
                NavigationLink {
                    BackupView(model: BackupModel(session: session))
                } label: {
                    SettingsLabel(title: "Backup & Import", symbol: .download, color: .teal)
                }
            } header: {
                Text(SettingsSection.sync.title)
            }

            Section {
                NavigationLink {
                    ReportBugView(model: ReportBugModel(session: session))
                } label: {
                    SettingsLabel(title: "Report a Bug", symbol: .bug, color: .red,
                                  value: UnreportedCrash.shared.date == nil ? nil : "Crash found", valueColor: .orange)
                }
                NavigationLink {
                    AboutView()
                } label: {
                    SettingsLabel(title: "About", symbol: .info, color: .gray, value: AboutText.displayVersion)
                }
            } header: {
                Text(SettingsSection.support.title)
            } footer: {
                SettingsSignOff()
            }
        }
        .navigationTitle("Settings")
        // A light tick whenever a setting changes (honours the Haptics setting itself).
        .onChange(of: changeSignature) { Haptics.play(.selection) }
        #if DEBUG
        .modifier(DebugSettingsPage(session: session))
        #endif
        .logScreen("Settings")
    }

    /// The server's own name if it has one, else its address.
    private var activeServerName: String? {
        session.accounts.first { $0.id == session.activeAccountID }?.displayName
    }

    private struct ChangeSignature: Equatable {
        var synced: SyncedSettings
        var flags: [Bool]
    }

    private var changeSignature: ChangeSignature {
        ChangeSignature(synced: settings.synced, flags: [settings.iCloudSyncEnabled, settings.handoffEnabled,
                                                         settings.suggestionsEnabled, settings.hapticsEnabled])
    }
}

#if DEBUG
/// Env `BC_SETTINGS_PAGE=about|acknowledgements|account|haptics|servers|report|mcp|suggestions` opens that page, for screenshots.
private struct DebugSettingsPage: ViewModifier {
    let session: SessionManager
    @State private var page = ProcessInfo.processInfo.environment["BC_SETTINGS_PAGE"]

    func body(content: Content) -> some View {
        content.navigationDestination(isPresented: Binding(get: { page != nil }, set: { if !$0 { page = nil } })) {
            switch page {
            case "haptics": HapticsSettingsView()
            case "servers": ServersView(session: session)
            case "report": ReportBugView(model: ReportBugModel(session: session))
            case "mcp": MCPSettingsView(model: MCPSettingsModel(session: session))
            case "suggestions": SuggestionsSettingsView()
            case "acknowledgements": AcknowledgementsView()
            case "account": AccountSettingsView(session: session)
            default: AboutView()
            }
        }
    }
}
#endif

struct HapticsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsList {
            Section {
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
                if settings.hapticsEnabled {
                    Picker("Strength", selection: $settings.hapticStrength) {
                        ForEach(HapticStrength.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                #if os(macOS)
                FooterText("Gentle taps when you scan code, when a scan works or fails, and when you change a setting. On Mac you feel them on a Force Touch trackpad.")
                #else
                FooterText("Gentle taps when you scan code, when a scan works or fails, and when you change a setting. Changing the strength plays a sample.")
                #endif
            }
        }
        .navigationTitle("Haptics")
        .onChange(of: settings.hapticStrength) { Haptics.play(.tap) }
    }
}

struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var appIcon = AppIconModel()

    var body: some View {
        @Bindable var settings = settings
        SettingsList {
            Section("Appearance") {
                HStack(spacing: 0) {
                    ForEach(AppAppearance.allCases) { option in
                        Button { settings.appearance = option } label: {
                            VStack(spacing: 8) {
                                AppearancePreview(option: option)
                                Text(option.title).font(.subheadline)
                                Icon(settings.appearance == option ? .checkCircle : .circle)
                                    .foregroundStyle(settings.appearance == option ? settings.accent.color : .secondary)
                                    .font(.title3)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(settings.appearance == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)
            }
            if appIcon.isAvailable {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 14) {
                        ForEach(AppIconChoice.allCases) { choice in
                            Button { Task { await appIcon.choose(choice) } } label: {
                                VStack(spacing: 6) {
                                    choice.preview
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .padding(3)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(settings.accent.color, lineWidth: 2.5)
                                                .opacity(appIcon.current == choice ? 1 : 0)
                                        }
                                    Text(choice.title)
                                        .font(.caption)
                                        .foregroundStyle(appIcon.current == choice ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(choice.title) icon")
                            .accessibilityAddTraits(appIcon.current == choice ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("App Icon")
                } footer: {
                    if let error = appIcon.errorMessage {
                        Text(error).foregroundStyle(.red)
                    } else {
                        #if os(macOS)
                        FooterText("Shown in the Dock while ByteCache is open. Finder and Launchpad keep the default icon.")
                        #else
                        FooterText("Each icon has its own look for the Home Screen's Dark, Tinted and Clear styles.")
                        #endif
                    }
                }
            }
            Section {
                ForEach(LanguageIconStyle.allCases) { style in
                    Button { settings.languageIconStyle = style } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(style.title).foregroundStyle(.primary)
                                HStack(spacing: 14) {
                                    ForEach(["python", "swift", "javascript", "rust", "dockerfile", "go", "sql"], id: \.self) { language in
                                        LanguageIconView(language, size: 20, style: style)
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.languageIconStyle == style {
                                Icon(.check).foregroundStyle(.tint).fontWeight(.semibold)
                            }
                        }
                    }
                    .accessibilityAddTraits(settings.languageIconStyle == style ? .isSelected : [])
                }
            } header: {
                Text("Language Icons")
            } footer: {
                FooterText("Shown next to languages in the sidebar, snippet lists, files and the language picker. Logos from Devicon; where a logo is black or missing, Colour uses the language's colour from GitHub Linguist. Trademarks belong to their owners.")
            }
            Section("Accent Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button { settings.accent = choice } label: {
                            Circle()
                                .fill(choice.color.gradient)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if settings.accent == choice {
                                        Icon(.check).font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(settings.accent == choice ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Appearance")
    }
}

/// A tiny phone mock-up in light, dark, or split for Automatic.
private struct AppearancePreview: View {
    let option: AppAppearance

    var body: some View {
        ZStack {
            switch option {
            case .light: screen(dark: false)
            case .dark: screen(dark: true)
            case .system:
                screen(dark: false)
                    .overlay(alignment: .trailing) { screen(dark: true).mask(Rectangle().frame(width: 26).frame(maxWidth: .infinity, alignment: .trailing)) }
            }
        }
        .frame(width: 52, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
    }

    private func screen(dark: Bool) -> some View {
        let bg: Color = dark ? .black : .white, line: Color = dark ? .white.opacity(0.35) : .black.opacity(0.18)
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<5) { i in Capsule().fill(line).frame(width: [30, 22, 34, 18, 26][i], height: 4) }
        }
        .padding(8)
        .frame(width: 52, height: 92, alignment: .topLeading)
        .background(bg)
    }
}

struct CodeThemeSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    private static let sample = """
    // Fetch and decode a user
    func loadUser(id: Int) async throws -> User {
        let url = URL(string: "https://api.example.com/users/\\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(User.self, from: data)
    }
    """

    var body: some View {
        @Bindable var settings = settings
        SettingsList {
            Section {
                CodeView(code: Self.sample, language: "swift")
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } header: {
                Text("Preview")
            }

            Section("Text") {
                HStack {
                    Icon(.textSmaller).foregroundStyle(.secondary)
                    Slider(value: $settings.codeFontSize, in: AppSettings.fontSizes, step: 1)
                    Icon(.textLarger).foregroundStyle(.secondary)
                }
                LabeledContent("Font Size", value: "\(Int(settings.codeFontSize)) pt")
                Toggle("Line Numbers", isOn: $settings.showLineNumbers)
                Toggle("Wrap Long Lines", isOn: $settings.wrapLines)
            }

            themeSection("Follows Appearance", .adaptive)
            themeSection("Dark", .dark)
            themeSection("Light", .light)
        }
        .navigationTitle("Code Theme")
    }

    private func themeSection(_ title: String, _ style: CodeTheme.Style) -> some View {
        Section(title) {
            ForEach(CodeTheme.all.filter { $0.style == style }) { theme in
                Button { settings.codeThemeID = theme.id } label: {
                    HStack(spacing: 12) {
                        ThemeSwatch(palette: theme.palette(for: colorScheme))
                        Text(theme.name).foregroundStyle(.primary)
                        Spacer()
                        if settings.codeThemeID == theme.id {
                            Icon(.check).foregroundStyle(.tint).fontWeight(.semibold)
                        }
                    }
                }
                .accessibilityAddTraits(settings.codeThemeID == theme.id ? .isSelected : [])
            }
        }
    }
}

struct PrivacyInfoView: View {
    var body: some View {
        SettingsList {
            Section {
                Label("No analytics, tracking or ads.", symbol: .eyeOff)
                Label("Snippets go only to the server you enter.", symbol: .server)
                Label("Your login is kept in the Keychain; your password is never stored.", symbol: .key)
                Label("Copied text is read only when you tap Paste.", symbol: .clipboard)
                Label("Language detection runs on this device.", symbol: .cpu)
                Label("Bug reports leave the device only when you send one, after you've seen what's in it.", symbol: .bug)
                Label("After an update, What's New loads that version's notes from GitHub.", symbol: .download)
                Label("AI Notes stay on your devices and in your iCloud, never on your server.", symbol: .sparkles)
            } footer: {
                FooterText(AboutText.privacy)
            }
        }
        .navigationTitle("Privacy")
    }
}

struct AboutView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var appIcon = AppIconModel()

    var body: some View {
        @Bindable var settings = settings
        SettingsList {
            Section {
                AboutHeader(icon: appIcon.current)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            #if os(iOS)
            // Only worth showing when widgets can't use the App Group (some sideloaded copies).
            if WidgetSnapshotStore().sharing != "App Group" {
                Section {
                    LabeledContent("Widgets", value: WidgetSnapshotStore().sharing)
                } footer: {
                    FooterText("How widgets get your snippets on this install.")
                }
            }
            #endif
            Section {
                // Buttons, not Links: a Link tints its whole row like a web link.
                Button { openURL(AboutText.sourceCode) } label: {
                    HStack(spacing: 12) {
                        BrandSettingsIcon(asset: "brand-github", color: .black)
                        Text("Source Code")
                        Spacer(minLength: 8)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens in your browser")
                Button { openURL(AboutText.contact) } label: {
                    SettingsLabel(title: "Contact", symbol: .mail, color: .blue, value: AboutText.contactEmail)
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Writes an email")
                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    SettingsLabel(title: "Acknowledgements", symbol: .acknowledgements, color: .pink)
                }
            } footer: {
                VStack(spacing: 6) {
                    Text(AboutText.credit)
                    Text(AboutText.disclaimer)
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }
        }
        .navigationTitle("About")
    }
}

/// The top of About: the app icon the person picked, name, tagline and version.
private struct AboutHeader: View {
    let icon: AppIconChoice

    var body: some View {
        VStack(spacing: 6) {
            icon.preview
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(AboutText.appName).font(.title2.bold())
            Text(AboutText.tagline).font(.subheadline).foregroundStyle(.secondary)
            Text("Version \(AboutText.versionWithBuild)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.fill.tertiary, in: Capsule())
                .padding(.top, 4)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A brand mark (GitHub) in a Settings-style tile.
private struct BrandSettingsIcon: View {
    let asset: String
    let color: Color

    var body: some View {
        Image(asset, bundle: .module)
            .resizable()
            .renderingMode(.template)
            .frame(width: 17, height: 17)
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        SettingsList {
            Section("Code") {
                credit("HighlightSwift", detail: "MIT License, © 2023 Stefan Britton")
                credit("highlight.js", detail: "BSD 3-Clause License, © 2006 Ivan Sagalaev")
                licence("Mermaid", detail: "MIT License, © 2014 - 2022 Knut Sveidqvist", file: "MERMAID-LICENSE")
            }
            Section {
                licence("Lucide icons", detail: "ISC License, © Lucide Icons and Contributors (some icons © Cole Bemis, MIT)", file: "LUCIDE-LICENSE")
                licence("Devicon language logos", detail: "MIT License, © konpa and Devicon contributors", file: "DEVICON-LICENSE")
                licence("GitHub Linguist language colours", detail: "MIT License, © 2017 GitHub, Inc.", file: "LINGUIST-LICENSE")
                Text("Brand colours and the Rust and Handlebars glyphs from Simple Icons (CC0).")
            } header: {
                Text("Icons and Colours")
            } footer: {
                FooterText("Logos are trademarks of their owners, used only to identify languages. The GitHub mark is a trademark of GitHub, Inc., used to link to GitHub.")
            }
            Section {
                Text("Dracula, Monokai, Nord, Gruvbox, Night Owl and Catppuccin colour palettes by their respective authors (MIT).")
                Text("Language model trained on permissively licensed open-source code.")
            } header: {
                Text("Themes and Language Detection")
            }
        }
        .navigationTitle("Acknowledgements")
    }

    private func credit(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func licence(_ title: String, detail: String, file: String) -> some View {
        NavigationLink {
            ScrollView {
                Text(Bundle.module.url(forResource: file, withExtension: "txt")
                    .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle(title)
        } label: {
            credit(title, detail: detail)
        }
    }
}

struct ICloudSyncSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CloudSyncCoordinator.self) private var sync

    var body: some View {
        @Bindable var settings = settings
        SettingsList {
            Section {
                Toggle("iCloud Sync", isOn: $settings.iCloudSyncEnabled)
                    .onChange(of: settings.iCloudSyncEnabled) {
                        if settings.iCloudSyncEnabled { Task { await sync.syncNow() } }
                    }
            } footer: {
                if !UbiquitousSyncStore.isAvailable {
                    Label("This device isn't signed in to iCloud.", symbol: .icloudWarning)
                        .foregroundStyle(.orange)
                }
            }
            Section("Synced") {
                Label("Appearance and accent colour", symbol: .appearance)
                Label("Code theme, font size, line numbers", symbol: .code)
                Label("Server list", symbol: .server)
            }
            Section {
                Label("Logins and API keys", symbol: .key)
                Label("Snippets (they live on your servers)", symbol: .document)
            } header: {
                Text("Stays on this device")
            } footer: {
                FooterText("Servers added on another device appear here signed out — sign in once on each device. Removing a server removes it from all your devices.")
            }
        }
        .navigationTitle("iCloud Sync")
    }
}

struct HandoffSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsList {
            Section {
                Toggle("Handoff", isOn: $settings.handoffEnabled)
            } footer: {
                FooterText("Pick up the snippet you're viewing on your other iPhone, iPad or Mac. Your devices need the same Apple Account, with Bluetooth and Wi-Fi on. Devices without ByteCache open the snippet in the ByteStash web app. Handoff also needs to be on in the system settings (General → AirPlay & Continuity on iPhone and iPad, General → AirDrop & Handoff on Mac).")
            }
        }
        .navigationTitle("Handoff")
    }
}

struct SuggestionsSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AINoteStore.self) private var aiNotes: AINoteStore?
    @State private var confirmingClear = false
    @Environment(\.scenePhase) private var scenePhase
    /// Read again on returning to the app: turning Apple Intelligence on, or its download finishing,
    /// happens outside ByteCache.
    @State private var availability = AIAvailability.current

    var body: some View {
        @Bindable var settings = settings
        SettingsList {
            Section {
                // Shown off while Apple Intelligence can't be used; the choice itself is kept for later.
                Toggle("Suggest Titles & Tags", isOn: Binding(
                    get: { settings.suggestionsEnabled && availability == .available },
                    set: { settings.suggestionsEnabled = $0 }
                ))
                .disabled(availability != .available)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    FooterText("When you save code, ByteCache suggests a title, a one-line description and categories, and the Explain button describes what a snippet does — all with Apple Intelligence on this device. Your code never leaves it. Suggestions only fill empty fields; what you type always wins.")
                    if let why = availability.explanation {
                        Label(why, symbol: .warning)
                            .foregroundStyle(.orange)
                    }
                }
            }
            if let aiNotes {
                Section {
                    LabeledContent("Saved Notes", value: aiNotes.count == 0 ? "None"
                                   : "\(aiNotes.count) · \(ByteCountFormatter.string(fromByteCount: Int64(aiNotes.byteSize), countStyle: .file))")
                    Picker("Keep Up To", selection: $settings.aiNotesLimit) {
                        ForEach(AINoteStore.limits, id: \.self) { Text("\($0) notes").tag($0) }
                    }
                    .onChange(of: settings.aiNotesLimit) { aiNotes.applyLimit() }
                    Button("Clear All AI Notes", role: .destructive) { confirmingClear = true }
                        .disabled(aiNotes.count == 0)
                } header: {
                    Text("AI Notes")
                } footer: {
                    FooterText("Explain keeps its answer as an AI Note under the code. Notes stay on this device and, with iCloud Sync on, sync to your other devices; they're never sent to your ByteStash server. When the limit is reached, the oldest note makes room.")
                }
            }
        }
        .navigationTitle("Smart Suggestions")
        .confirmationDialog("Clear All AI Notes?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear All AI Notes", role: .destructive) { aiNotes?.clearAll() }
        } message: {
            Text(settings.iCloudSyncEnabled ? "They're removed from this device and your other devices." : "They're removed from this device.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { availability = AIAvailability.current }
        }
    }
}

/// The top of Settings: who is signed in, and where. Opens the Account page.
private struct ProfileCard: View {
    let user: User
    let server: ServerURL
    let serverName: String?
    @Environment(AppSettings.self) private var settings

    private var isAPIKey: Bool { user.username == SessionManager.apiKeyUserName }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if isAPIKey {
                    Icon(.key)
                } else {
                    Text(String(user.username.prefix(1)).uppercased())
                }
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(settings.accent.color.gradient, in: Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(isAPIKey ? "Signed in with an API key" : (user.username.isEmpty ? "Signed In" : user.username))
                    .font(.title3.weight(.semibold))
                HStack(spacing: 5) {
                    Icon(.server).font(.caption)
                    Text(serverName ?? server.base.host() ?? server.base.absoluteString)
                        .truncationMode(.middle)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

/// The bottom of Settings: the app icon in use, name and version.
private struct SettingsSignOff: View {
    @State private var appIcon = AppIconModel()

    var body: some View {
        VStack(spacing: 6) {
            appIcon.current.preview
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            Text("\(AboutText.appName) \(AboutText.displayVersion) · \(AboutText.tagline)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
}

/// Settings → Account: the login on this server and what can be done with it. On the Mac, API Keys
/// and Change Password are separate pages in the sidebar, so they're left out here.
struct AccountSettingsView: View {
    let session: SessionManager
    var showsAccountPages = true

    var body: some View {
        SettingsList {
            if case .signedIn(let server, let user) = session.state {
                Section {
                    ProfileCard(user: user, server: server,
                                serverName: session.accounts.first { $0.id == session.activeAccountID }?.displayName)
                }
                if showsAccountPages {
                    Section {
                        NavigationLink {
                            APIKeysView(model: AccountModel(session: session))
                        } label: {
                            SettingsLabel(title: "API Keys", symbol: .key, color: .orange)
                        }
                        NavigationLink {
                            ChangePasswordView(model: AccountModel(session: session))
                        } label: {
                            SettingsLabel(title: "Change Password", symbol: .changePassword, color: .gray)
                        }
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        SpotlightIndexer.removeAll()
                        session.signOut()
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    FooterText("Signing out keeps the server in Servers, so signing in again is one step.")
                }
            }
        }
        .navigationTitle("Account")
    }
}
