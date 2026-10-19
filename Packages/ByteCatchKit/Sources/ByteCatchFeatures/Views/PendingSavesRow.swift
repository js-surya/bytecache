import ByteCatchCore
import SwiftUI

/// Top-of-list notice for snippets saved while offline that haven't reached the server yet.
struct PendingSavesRow: View {
    let flusher: SaveQueueFlusher
    @State private var confirmingDiscard = false

    var body: some View {
        HStack(spacing: 12) {
            Icon(.offline).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(flusher.pendingCount == 1 ? "1 snippet waiting to upload" : "\(flusher.pendingCount) snippets waiting to upload")
                    .font(.subheadline.weight(.medium))
                Text("Saved on this device while offline.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if flusher.isFlushing {
                ProgressView().controlSize(.small)
            } else {
                Button("Retry") { Task { await flusher.flush() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .contextMenu {
            Button(role: .destructive) { confirmingDiscard = true } label: { Label("Discard Waiting Snippets", symbol: .trash) }
        }
        .swipeActions {
            Button(role: .destructive) { confirmingDiscard = true } label: { Label("Discard", symbol: .trash) }
        }
        .confirmationDialog("Discard snippets waiting to upload?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { flusher.discardAll() }
        } message: {
            Text("They were never uploaded, so this can't be undone.")
        }
    }
}
