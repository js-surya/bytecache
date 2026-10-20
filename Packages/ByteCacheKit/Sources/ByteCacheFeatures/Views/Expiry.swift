import ByteCacheCore
import SwiftUI

extension AppSettings {
    /// When a snippet expires: ByteCache's own date, or one the server sent.
    public func expiry(of snippet: Snippet, server: ServerURL?) -> Date? {
        server.flatMap { snippetExpiries.date(snippetID: snippet.id, server: $0) } ?? snippet.expiryDate
    }

    public func setExpiry(_ date: Date?, snippetID: Int, server: ServerURL) {
        snippetExpiries.set(date, snippetID: snippetID, server: server)
    }
}

/// "Expires in 2d 4h": updates every minute, every second in the last hour (shown in orange).
struct ExpiryBadge: View {
    let date: Date
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: ExpiryText.isSoon(date) ? 1 : 60)) { context in
            let soon = ExpiryText.isSoon(date, now: context.date)
            Label { Text(ExpiryText.remaining(until: date, now: context.date)).monospacedDigit() } icon: {
                Icon(.timer, size: compact ? 11 : 13)
            }
            .font(compact ? .caption2.weight(.medium) : .caption.weight(.semibold))
            .foregroundStyle(soon ? .orange : .secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The editor's "Expires" section.
struct ExpiryEditorSection: View {
    @Binding var choice: ExpiryChoice

    var body: some View {
        Section {
            Picker("Expires", selection: Binding(
                get: { if case .date = choice { return ExpiryChoice.date(.distantFuture) } else { return choice } },
                set: { picked in
                    if case .date = picked {
                        if case .date = choice { return }
                        choice = .date(Date().addingTimeInterval(86_400))
                    } else {
                        choice = picked
                    }
                }
            )) {
                ForEach(ExpiryChoice.presets, id: \.self) { Text($0.title).tag($0) }
                Text(ExpiryChoice.date(.distantFuture).title).tag(ExpiryChoice.date(.distantFuture))
            }
            if case .date(let date) = choice {
                DatePicker("Date", selection: Binding(get: { date }, set: { choice = .date($0) }), in: Date()...)
            }
        } header: {
            Text("Expires")
        } footer: {
            Text("When the time runs out, ByteCache moves the snippet to the Recycle Bin. This happens on any of your devices with ByteCache open; the ByteStash website doesn't know about it.")
        }
    }
}

/// Moves expired snippets of the current server to the Recycle Bin. Runs while the app is open.
@MainActor
public enum ExpirySweeper {
    public static func sweep(settings: AppSettings, list: SnippetListModel) async {
        guard let client = list.session.client else { return }
        let server = client.server
        for id in settings.snippetExpiries.due(server: server) {
            if await list.recycleExpired(id: id) {
                settings.setExpiry(nil, snippetID: id, server: server)
            }
        }
    }
}
