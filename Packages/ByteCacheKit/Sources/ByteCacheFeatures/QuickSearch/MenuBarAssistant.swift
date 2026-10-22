#if os(macOS)
import ByteCacheCore
import SwiftUI

/// The menu bar window (CP-69): Browse finds and uses snippets, Create saves a new one, without
/// opening ByteCache's main window.
public struct MenuBarAssistantView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case browse, create
        var id: Self { self }
        var title: String { self == .browse ? "Browse" : "Create" }
    }

    let services: AppServices
    let onClose: () -> Void
    @State private var pane = Pane.browse
    @State private var capture: CaptureModel?
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    public init(services: AppServices, onClose: @escaping () -> Void) {
        self.services = services
        self.onClose = onClose
    }

    public var body: some View {
        let size = settings.menuBarPanelSize.size
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Pane", selection: $pane) {
                    ForEach(Pane.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // ⌘1 / ⌘2, as in the window's own Browse / Create.
                .background {
                    Button("") { pane = .browse }.keyboardShortcut("1", modifiers: .command).hidden()
                    Button("") { pane = .create }.keyboardShortcut("2", modifiers: .command).hidden()
                }
                Spacer()
                Button { openMainWindow() } label: { Label("Open ByteCache", symbol: .newWindow) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Open ByteCache")
                Menu {
                    Button("Open ByteCache") { openMainWindow() }
                    Button("New Snippet") { pane = .create }
                    Divider()
                    SettingsLink { Text("Settings…") }
                    Button("Report a Bug…") {
                        onClose()
                        openWindow(id: "report-bug")
                    }
                    Divider()
                    Button("Quit ByteCache") { NSApp.terminate(nil) }
                } label: {
                    Icon(.settings)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            switch pane {
            case .browse:
                QuickSearchView(model: services.quickSearch, lock: services.lock,
                                size: CGSize(width: size.width, height: size.height - 45), onClose: onClose)
            case .create:
                createPane
                    .frame(width: size.width, height: size.height - 45)
            }
        }
    }

    @ViewBuilder
    private var createPane: some View {
        if services.lock.isLocked {
            ContentUnavailableView("ByteCache is Locked", symbol: .lock,
                                   description: Text("Open ByteCache to unlock it."))
        } else if let capture {
            NavigationStack {
                CaptureSheet(model: capture, onQueued: { finishCreating(nil) }) { saved in finishCreating(saved) }
            }
        } else {
            LoadingMark().task { startCreating() }
        }
    }

    private func startCreating() {
        let session = services.session
        capture = CaptureModel(text: "", client: session.client, detector: services.detector,
                               suggester: services.settings.suggester, queue: .shared) {
            session.handleUnauthorized()
        }
    }

    /// Saved (or queued offline): back to Browse with a fresh form for next time.
    private func finishCreating(_ saved: Snippet?) {
        if let saved { services.quickSearch.list.didSave(saved) }
        services.saveQueue.refresh()
        capture = nil
        pane = .browse
        if saved != nil { CopyFeedback.copied("Saved") }
    }

    private func openMainWindow() {
        onClose()
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else if let url = URL(string: "bytecache://open") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
