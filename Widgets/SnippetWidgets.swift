import AppIntents
import ByteCacheCore
import SwiftUI
import WidgetKit

struct SnippetEntry: TimelineEntry {
    enum Content { case snippets([WidgetSnippet], server: String), locked, signedOut, problem(String), notShared }
    let date: Date
    let content: Content
    /// The configurable widget's heading (the chosen source); nil for the fixed widgets.
    var title: String?
}

/// Builds an entry for one source from the shared snapshot.
enum SnippetEntries {
    static func entry(for source: WidgetSource) -> SnippetEntry {
        guard !AppEnvironment.isAppLockEnabled else { return SnippetEntry(date: .now, content: .locked, title: source.title) }
        let snapshot: WidgetSnapshot
        switch WidgetSnapshotStore().state() {
        case .snapshot(let shared): snapshot = shared
        case .signedOut: return SnippetEntry(date: .now, content: .signedOut, title: source.title)
        case .unavailable: return SnippetEntry(date: .now, content: .notShared, title: source.title)
        }
        if let problem = snapshot.problem, snapshot.pinned.isEmpty, snapshot.recent.isEmpty {
            return SnippetEntry(date: .now, content: .problem(problem), title: source.title)
        }
        return SnippetEntry(date: .now, content: .snippets(snapshot.list(for: source), server: snapshot.serverName),
                            title: source.title)
    }
}

struct SnippetProvider: TimelineProvider {
    let pinnedOnly: Bool

    private func entry() -> SnippetEntry {
        guard !AppEnvironment.isAppLockEnabled else { return SnippetEntry(date: .now, content: .locked) }
        let snapshot: WidgetSnapshot
        switch WidgetSnapshotStore().state() {
        case .snapshot(let shared): snapshot = shared
        case .signedOut: return SnippetEntry(date: .now, content: .signedOut)
        // The app's data is out of reach, which isn't the same as signed out.
        case .unavailable: return SnippetEntry(date: .now, content: .notShared)
        }
        if let problem = snapshot.problem, snapshot.pinned.isEmpty, snapshot.recent.isEmpty {
            return SnippetEntry(date: .now, content: .problem(problem))
        }
        return SnippetEntry(date: .now, content: .snippets(pinnedOnly ? snapshot.pinned : snapshot.recent, server: snapshot.serverName))
    }

    func placeholder(in context: Context) -> SnippetEntry {
        SnippetEntry(date: .now, content: .snippets(SnippetWidgetView.samples, server: "bytestash.example.com"))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnippetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnippetEntry>) -> Void) {
        // The app reloads timelines whenever its data changes; this is only a safety net.
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct SnippetWidgetView: View {
    let entry: SnippetEntry
    let title: String
    let emptyMessage: String
    @Environment(\.widgetFamily) private var family

    static let samples: [WidgetSnippet] = []

    var body: some View {
        switch entry.content {
        case .locked:
            message("ByteCache is Locked", systemImage: "lock.fill")
        case .signedOut:
            message("Open ByteCache to sign in", systemImage: "curlybraces")
        case .problem(let problem):
            message(problem, systemImage: "wifi.exclamationmark")
        case .notShared:
            message("Open ByteCache once. If this stays, this install can't share data with widgets — see Settings → About.",
                    systemImage: "exclamationmark.triangle")
        case .snippets(let snippets, _) where snippets.isEmpty:
            message(emptyMessage, systemImage: "tray")
        case .snippets(let snippets, _):
            content(snippets)
        }
    }

    @ViewBuilder
    private func content(_ snippets: [WidgetSnippet]) -> some View {
        switch family {
        case .accessoryInline:
            Text(snippets[0].title)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                ForEach(snippets.prefix(3)) { snippet in
                    Text(snippet.title).font(.caption).lineLimit(1)
                }
            }
            .widgetURL(DeepLink.snippet(snippets[0].id).url)
        case .systemSmall:
            single(snippets[0])
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: "curlybraces").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                ForEach(snippets.prefix(family == .systemLarge ? 7 : 3)) { snippet in
                    row(snippet)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func single(_ snippet: WidgetSnippet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(snippet.title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                copyButton(snippet)
            }
            Text(snippet.preview)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(6)
            Spacer(minLength: 0)
        }
        .widgetURL(DeepLink.snippet(snippet.id).url)
    }

    private func row(_ snippet: WidgetSnippet) -> some View {
        HStack(spacing: 8) {
            Link(destination: DeepLink.snippet(snippet.id).url) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snippet.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(snippet.preview.split(separator: "\n").first.map(String.init) ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            copyButton(snippet)
        }
    }

    private func copyButton(_ snippet: WidgetSnippet) -> some View {
        Button(intent: CopySnippetIntent(snippetID: snippet.id)) {
            Image(systemName: "doc.on.doc").font(.caption)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Copy \(snippet.title)")
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.title3).foregroundStyle(.tint)
            Text(text).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private var supportedFamilies: [WidgetFamily] {
    #if os(iOS)
    [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]
    #else
    [.systemSmall, .systemMedium, .systemLarge]
    #endif
}

struct PinnedSnippetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "me.suryajs.bytecache.pinned", provider: SnippetProvider(pinnedOnly: true)) { entry in
            SnippetWidgetView(entry: entry, title: "Pinned", emptyMessage: "Pin snippets in ByteCache to see them here")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Snippets")
        .description("Your pinned snippets. Tap to open, or copy straight from the widget.")
        .supportedFamilies(supportedFamilies)
    }
}

struct RecentSnippetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "me.suryajs.bytecache.recent", provider: SnippetProvider(pinnedOnly: false)) { entry in
            SnippetWidgetView(entry: entry, title: "Recent", emptyMessage: "No snippets yet")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Snippets")
        .description("Your latest snippets. Tap to open, or copy straight from the widget.")
        .supportedFamilies(supportedFamilies)
    }
}

#if os(iOS)
@available(iOS 18.0, *)
struct SaveClipboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "me.suryajs.bytecache.saveClipboard") {
            ControlWidgetButton(action: SaveClipboardIntent()) {
                Label("Save Clipboard", systemImage: "doc.on.clipboard")
            }
        }
        .displayName("Save Clipboard")
        .description("Save what you copied to ByteCache.")
    }
}
#endif

#if os(iOS)
@available(iOS 18.0, *)
struct ScanCodeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "me.suryajs.bytecache.scanCode") {
            ControlWidgetButton(action: ScanCodeIntent()) {
                Label("Scan Code", systemImage: "camera.viewfinder")
            }
        }
        .displayName("Scan Code")
        .description("Scan code from the camera into ByteCache.")
    }
}
#endif

/// A source the configurable widget can show; the choices come from the app's snapshot.
struct WidgetSourceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Snippets to Show"
    static let defaultQuery = WidgetSourceQuery()

    let source: WidgetSource
    var id: String { source.id }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(source.title)") }
}

struct WidgetSourceQuery: EntityQuery {
    private var available: [WidgetSource] {
        WidgetSnapshotStore().read()?.sources ?? [.recent, .pinned, .favorites]
    }

    func entities(for identifiers: [String]) async throws -> [WidgetSourceEntity] {
        available.filter { identifiers.contains($0.id) }.map(WidgetSourceEntity.init)
    }

    func suggestedEntities() async throws -> [WidgetSourceEntity] {
        available.map(WidgetSourceEntity.init)
    }

    func defaultResult() async -> WidgetSourceEntity? {
        WidgetSourceEntity(source: .recent)
    }
}

struct SnippetSourceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Snippets"
    static let description = IntentDescription("Choose what the widget shows: recent, pinned or favorite snippets, a Smart Group, a tag or a language.")

    @Parameter(title: "Show")
    var source: WidgetSourceEntity?
}

struct ConfigurableSnippetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnippetEntry {
        SnippetEntry(date: .now, content: .snippets(SnippetWidgetView.samples, server: "bytestash.example.com"), title: "Recent")
    }

    func snapshot(for configuration: SnippetSourceIntent, in context: Context) async -> SnippetEntry {
        context.isPreview ? placeholder(in: context) : SnippetEntries.entry(for: configuration.source?.source ?? .recent)
    }

    func timeline(for configuration: SnippetSourceIntent, in context: Context) async -> Timeline<SnippetEntry> {
        // The app reloads timelines whenever its data changes; this is only a safety net.
        Timeline(entries: [SnippetEntries.entry(for: configuration.source?.source ?? .recent)],
                 policy: .after(.now.addingTimeInterval(3600)))
    }
}

struct ConfigurableSnippetsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "me.suryajs.bytecache.snippets", intent: SnippetSourceIntent.self,
                               provider: ConfigurableSnippetProvider()) { entry in
            SnippetWidgetView(entry: entry, title: entry.title ?? "Snippets", emptyMessage: "Nothing here yet")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Snippets")
        .description("Recent, pinned or favorite snippets, a Smart Group, a tag or a language — choose with Edit Widget.")
        .supportedFamilies(supportedFamilies)
    }
}

@main
struct ByteCacheWidgets: WidgetBundle {
    var body: some Widget {
        ConfigurableSnippetsWidget()
        PinnedSnippetsWidget()
        RecentSnippetsWidget()
        #if os(iOS)
        if #available(iOS 18.0, *) {
            SaveClipboardControl()
            ScanCodeControl()
        }
        #endif
    }
}
