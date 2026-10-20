import AppIntents
import ByteCacheCore
import SwiftUI
import WidgetKit

struct SnippetEntry: TimelineEntry {
    enum Content { case snippets([WidgetSnippet], server: String), locked, signedOut, problem(String), notShared }
    let date: Date
    let content: Content
}

struct SnippetProvider: TimelineProvider {
    let pinnedOnly: Bool

    private func entry() -> SnippetEntry {
        guard !AppEnvironment.isAppLockEnabled else { return SnippetEntry(date: .now, content: .locked) }
        // Without an App Group the app's snapshot is out of reach, which isn't the same as signed out.
        guard WidgetSnapshotStore.isShared else { return SnippetEntry(date: .now, content: .notShared) }
        guard let snapshot = WidgetSnapshotStore().read() else { return SnippetEntry(date: .now, content: .signedOut) }
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
            message("This copy of ByteCache can't share data with widgets. Reinstall it with App Groups enabled.",
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
        StaticConfiguration(kind: "app.bytecache.pinned", provider: SnippetProvider(pinnedOnly: true)) { entry in
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
        StaticConfiguration(kind: "app.bytecache.recent", provider: SnippetProvider(pinnedOnly: false)) { entry in
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
        StaticControlConfiguration(kind: "app.bytecache.saveClipboard") {
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
        StaticControlConfiguration(kind: "app.bytecache.scanCode") {
            ControlWidgetButton(action: ScanCodeIntent()) {
                Label("Scan Code", systemImage: "camera.viewfinder")
            }
        }
        .displayName("Scan Code")
        .description("Scan code from the camera into ByteCache.")
    }
}
#endif

@main
struct ByteCacheWidgets: WidgetBundle {
    var body: some Widget {
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
