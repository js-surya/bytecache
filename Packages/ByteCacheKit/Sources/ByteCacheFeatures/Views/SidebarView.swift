import ByteCacheCore
import SwiftUI

public struct SidebarView: View {
    let model: SidebarModel
    @Binding var selection: SidebarItem?
    let session: SessionManager
    @Environment(\.windowToolbarID) private var windowToolbarID
    @State private var showingSettings = false
    /// The Smart Group being created (`.some(nil)`) or edited.
    @State private var editingGroup: SmartGroup??
    @Environment(AppSettings.self) private var settings
    #if DEBUG
    @MainActor private static var debugSettingsShown = false
    #endif

    public init(model: SidebarModel, selection: Binding<SidebarItem?>, session: SessionManager) {
        self.model = model
        _selection = selection
        self.session = session
    }

    public var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach([SidebarItem.all, .pinned, .favorites, .mostUsed, .publicSnippets, .recycleBin], id: \.self) { item in
                    Label(item.title, symbol: item.symbol).tag(item)
                }
            }
            Section("Smart Groups") {
                ForEach(settings.smartGroups) { group in
                    Label(group.name, symbol: .smartGroup)
                        .tag(SidebarItem.smartGroup(group.id))
                        .contextMenu {
                            Button { editingGroup = .some(group) } label: { Label("Edit Smart Group…", symbol: .edit) }
                            Button(role: .destructive) { delete(group) } label: { Label("Delete", symbol: .trash) }
                        }
                }
                .onDelete { offsets in offsets.map { settings.smartGroups[$0] }.forEach(delete) }
                Button { editingGroup = .some(nil) } label: {
                    // A borderless button ignores the list's line limit, so the title sets its own.
                    Label { Text("New Smart Group…").lineLimit(1) } icon: { Icon(.plusCircle) }
                }
                .buttonStyle(.borderless)
            }
            if !model.languages.isEmpty {
                Section("Languages") {
                    ForEach(model.languages, id: \.self) { id in
                        Label { Text(LanguageName.display(id)) } icon: { LanguageIconView(id, size: 18) }
                            .tag(SidebarItem.language(id))
                    }
                }
            }
            if !model.categories.isEmpty {
                Section("Categories") {
                    ForEach(model.categories, id: \.self) { name in
                        Label(name, symbol: .tag).tag(SidebarItem.category(name))
                    }
                }
            }
        }
        // Sidebar rows stay on one line at any width (long tags, languages, Smart Group names).
        .lineLimit(1)
        .navigationTitle(AboutText.appName)
        .sheet(item: Binding(get: { editingGroup.map { EditingGroup(group: $0) } }, set: { if $0 == nil { editingGroup = nil } })) { editing in
            NavigationStack {
                SmartGroupEditor(group: editing.group, languages: model.languages, categories: model.categories) { saved in
                    if let index = settings.smartGroups.firstIndex(where: { $0.id == saved.id }) {
                        settings.smartGroups[index] = saved
                    } else {
                        settings.smartGroups.append(saved)
                        selection = .smartGroup(saved.id)
                    }
                }
            }
            .appSettingsStyle(settings)
        }
        .refreshable { await model.load() }
        .task {
            #if DEBUG
            // Once per launch: the sidebar reappears every time you go back on iPhone.
            if ProcessInfo.processInfo.arguments.contains("-BCShowSettings"), !Self.debugSettingsShown {
                Self.debugSettingsShown = true
                showingSettings = true
            }
            // `-BCSmartGroupDemo`: add (once) and select a sample Smart Group; `-BCNewSmartGroup`: open the editor.
            if ProcessInfo.processInfo.arguments.contains("-BCSmartGroupDemo") {
                if !settings.smartGroups.contains(where: { $0.name == "Recent Python" }) {
                    settings.smartGroups.append(SmartGroup(name: "Recent Python", rules: [
                        SmartRule(field: .language, value: "python"), SmartRule(field: .modifiedWithinDays, value: "365"),
                    ]))
                }
                selection = settings.smartGroups.first { $0.name == "Recent Python" }.map { .smartGroup($0.id) }
            }
            if ProcessInfo.processInfo.arguments.contains("-BCNewSmartGroup") { editingGroup = .some(nil) }
            #endif
            await model.load()
        }
        #if os(iOS)
        .toolbar {
            SettingsToolbarItem { showingSettings = true }
            ToolbarItem(placement: .topBarTrailing) {
                ServerMenu(session: session).toolbarIcon()
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(session: session)
                    .toolbar { Button("Done") { showingSettings = false } }
            }
            .appSettingsStyle(settings)
        }
        #else
        .toolbar(id: windowToolbarID) {
            ToolbarItem(id: "server", placement: .navigation) {
                ServerMenu(session: session).toolbarIcon()
            }
        }
        #endif
    }

    private func delete(_ group: SmartGroup) {
        if selection == .smartGroup(group.id) { selection = .all }
        settings.smartGroups.removeAll { $0.id == group.id }
    }
}

/// Sheet item for the Smart Group editor; a new group has no definition yet.
private struct EditingGroup: Identifiable {
    let group: SmartGroup?
    var id: UUID? { group?.id }
}
