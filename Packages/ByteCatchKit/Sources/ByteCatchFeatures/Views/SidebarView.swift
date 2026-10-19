import ByteCatchCore
import SwiftUI

public struct SidebarView: View {
    let model: SidebarModel
    @Binding var selection: SidebarItem?
    let session: SessionManager
    @State private var showingSettings = false
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
                ForEach([SidebarItem.all, .pinned, .favorites, .recycleBin], id: \.self) { item in
                    Label(item.title, symbol: item.symbol).tag(item)
                }
            }
            if !model.languages.isEmpty {
                Section("Languages") {
                    ForEach(model.languages, id: \.self) { id in
                        Label(LanguageName.display(id), symbol: SidebarItem.language(id).symbol)
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
        .navigationTitle(AboutText.appName)
        .refreshable { await model.load() }
        .task {
            #if DEBUG
            // Once per launch: the sidebar reappears every time you go back on iPhone.
            if ProcessInfo.processInfo.arguments.contains("-BCShowSettings"), !Self.debugSettingsShown {
                Self.debugSettingsShown = true
                showingSettings = true
            }
            #endif
            await model.load()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ServerMenu(session: session)
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Label("Settings", symbol: .settings) }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(session: session)
                    .toolbar { Button("Done") { showingSettings = false } }
            }
            .appSettingsStyle(settings)
        }
        #endif
    }
}
