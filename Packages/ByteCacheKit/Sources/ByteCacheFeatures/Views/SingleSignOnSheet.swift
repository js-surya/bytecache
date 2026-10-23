import ByteCacheCore
import SwiftUI
import WebKit

/// Signs in through the server's single sign-on (CP-72) in a web view. ByteStash hands the login back
/// only as a cookie, which the system sign-in sheet (ASWebAuthenticationSession) can't read, so the
/// sheet uses its own private cookie store: nothing is kept once it closes.
public struct SingleSignOnSheet: View {
    let server: ServerURL
    let title: String
    let onToken: (String) -> Void
    @State private var failure: String?
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss

    public init(server: ServerURL, title: String, onToken: @escaping (String) -> Void) {
        self.server = server
        self.title = title
        self.onToken = onToken
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                SignInWebView(server: server, loading: $loading) { result in
                    switch result {
                    case .success(let token):
                        onToken(token)
                        dismiss()
                    case .failure(let message):
                        failure = message
                    }
                }
                if loading { ProgressView() }
                if let failure {
                    ContentUnavailableView {
                        Label("Couldn't Sign In", symbol: .warning)
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Close") { dismiss() }
                    }
                    .background(.background)
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
        .logScreen("Single sign-on")
    }
}

enum SignInResult {
    case success(String)
    case failure(String)
}

/// The web view, and the navigation watcher that spots the end of the sign-in.
@MainActor
private struct SignInWebView {
    let server: ServerURL
    @Binding var loading: Bool
    let onResult: (SignInResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        view.load(URLRequest(url: SingleSignOn.startURL(for: server)))
        return view
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SignInWebView
        private var done = false

        init(_ parent: SignInWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard !done, let url = action.request.url,
                  let step = SingleSignOn.step(for: url, server: parent.server) else { return .allow }
            done = true
            switch step {
            case .finished:
                if let token = await token(in: webView.configuration.websiteDataStore.httpCookieStore) {
                    parent.onResult(.success(token))
                } else {
                    parent.onResult(.failure("The server didn't hand back a login. Try again, or sign in with an API key."))
                }
            case .failed(let message):
                parent.onResult(.failure(message))
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        private func fail(_ error: Error) {
            parent.loading = false
            // A cancelled load is ours (the end of the sign-in), not a failure.
            guard !done, (error as NSError).code != NSURLErrorCancelled else { return }
            done = true
            parent.onResult(.failure(error.localizedDescription))
        }

        /// The cookie can land a moment after the redirect, so look a few times.
        private func token(in store: WKHTTPCookieStore) async -> String? {
            let host = parent.server.base.host()?.lowercased() ?? ""
            for _ in 0..<10 {
                let cookies = await store.allCookies()
                if let cookie = cookies.first(where: { $0.name == SingleSignOn.tokenCookie && host.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()) }),
                   !cookie.value.isEmpty {
                    return cookie.value
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            return nil
        }
    }
}

#if os(iOS)
extension SignInWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
}
#else
extension SignInWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.parent = self }
}
#endif
