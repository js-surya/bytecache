import SwiftUI
import ByteCatchCore
import ByteCatchFeatures

/// Sidebar | list | detail. Collapses to a stack on iPhone.
struct MainSplitView: View {
    let services: AppServices
    @State private var sidebar: SidebarModel
    @State private var list: SnippetListModel
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var selectedSnippet: Snippet.ID?

    init(services: AppServices) {
        self.services = services
        _sidebar = State(initialValue: SidebarModel(session: services.session))
        _list = State(initialValue: SnippetListModel(session: services.session, cache: services.cache))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: sidebar, selection: $sidebarSelection, session: services.session)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
                #endif
        } content: {
            SnippetListView(model: list, selection: $selectedSnippet)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
                #endif
        } detail: {
            if let id = selectedSnippet, let snippet = list.snippets.first(where: { $0.id == id }) {
                Text(snippet.title).font(.title)
            } else {
                ContentUnavailableView("No Snippet Selected", systemImage: "curlybraces")
            }
        }
        .task(id: sidebarSelection) {
            list.selection = sidebarSelection ?? .all
            selectedSnippet = nil
            await list.refresh()
        }
    }
}
