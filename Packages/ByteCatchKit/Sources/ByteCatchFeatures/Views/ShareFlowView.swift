import ByteCatchCore
import ByteCatchLanguage
import SwiftUI

/// Everything a share extension shows: load what was shared, then the capture sheet.
/// No SwiftData, no list loading — extensions have tight memory limits.
public struct ShareFlowView: View {
    private enum Phase {
        case loading
        case ready(CaptureModel)
        case problem(String)
        case saved
    }

    let items: [NSExtensionItem]
    let onFinish: () -> Void
    @State private var phase = Phase.loading
    @State private var settings = AppSettings()

    public init(items: [NSExtensionItem], onFinish: @escaping () -> Void) {
        self.items = items
        self.onFinish = onFinish
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView()
                case .ready(let model):
                    CaptureSheet(model: model) { saved in
                        if saved != nil {
                            phase = .saved
                            Task {
                                try? await Task.sleep(for: .seconds(0.8))
                                onFinish()
                            }
                        } else {
                            onFinish()
                        }
                    }
                case .problem(let message):
                    ContentUnavailableView {
                        Label("Nothing to Save", systemImage: "text.badge.xmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Close", action: onFinish)
                    }
                case .saved:
                    ContentUnavailableView("Saved to ByteCatch", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .appSettingsStyle(settings)
        .task { await load() }
    }

    private func load() async {
        switch await SharedItemLoader.load(from: items) {
        case .failure(let problem):
            phase = .problem(problem.message)
        case .success(let payload):
            let store = AppEnvironment.makeCredentialStore()
            let credentials = store.load()
            let client = credentials.flatMap { c in c.token.map { APIClient(server: c.server, token: $0) } }
            let model = CaptureModel(
                text: payload.text, fileName: payload.fileName, sourceURL: payload.sourceURL,
                pageTitle: payload.pageTitle, client: client, detector: LanguageDetector()
            ) {
                // Token rejected: forget it so the app shows login next time; keep the server.
                if let credentials {
                    try? store.save(Credentials(server: credentials.server, token: nil, username: credentials.username))
                }
            }
            phase = .ready(model)
        }
    }
}
