import SwiftUI
import WebKit

/// A ```mermaid block drawn as a diagram (CP-73), as ByteStash's web app does. Mermaid (MIT) is bundled,
/// so nothing is fetched; it runs in strict mode in a web view that can't navigate anywhere. Shows the
/// code instead if the diagram can't be drawn.
struct MermaidView: View {
    let source: String
    @State private var height: CGFloat = 160
    @State private var failed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if failed {
            CodeView(code: source, language: "plaintext")
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            MermaidWebView(source: source, dark: colorScheme == .dark, height: $height, failed: $failed)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Diagram")
        }
    }
}

@MainActor
private struct MermaidWebView {
    let source: String
    let dark: Bool
    @Binding var height: CGFloat
    @Binding var failed: Bool

    /// mermaid.min.js, read once and kept inline so the page needs no file access.
    private static let script: String = {
        guard let url = Bundle.module.url(forResource: "mermaid.min", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text.replacingOccurrences(of: "</script", with: "<\\/script")
    }()

    static var background: (dark: String, light: String) { ("#1e1e1e", "#ffffff") }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: "mermaid")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        #if os(iOS)
        view.scrollView.isScrollEnabled = false
        #endif
        load(view)
        coordinator.loaded = (source, dark)
        return view
    }

    func update(_ view: WKWebView, _ coordinator: Coordinator) {
        coordinator.parent = self
        guard coordinator.loaded.source != source || coordinator.loaded.dark != dark else { return }
        coordinator.loaded = (source, dark)
        load(view)
    }

    private func load(_ view: WKWebView) {
        guard !Self.script.isEmpty,
              let data = try? JSONEncoder().encode(source), let json = String(data: data, encoding: .utf8) else {
            failed = true
            return
        }
        let background = dark ? Self.background.dark : Self.background.light
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;background:\(background)}#d{display:flex;justify-content:center;padding:12px}svg{max-width:100%;height:auto}</style>
        <script>\(Self.script)</script></head><body><div id="d"></div><script>
        mermaid.initialize({startOnLoad:false, securityLevel:'strict', theme:'\(dark ? "dark" : "default")'});
        mermaid.render('diagram', \(json)).then(function(r){
          document.getElementById('d').innerHTML = r.svg;
          requestAnimationFrame(function(){ webkit.messageHandlers.mermaid.postMessage({height: document.body.scrollHeight}); });
        }).catch(function(e){ webkit.messageHandlers.mermaid.postMessage({error: String(e)}); });
        </script></body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidWebView
        var loaded: (source: String, dark: Bool) = ("", false)

        init(_ parent: MermaidWebView) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if let height = body["height"] as? Double, height > 0 {
                parent.height = min(CGFloat(height), 1600)
            } else if body["error"] != nil {
                parent.failed = true
            }
        }

        /// Only the page itself; links in a diagram go nowhere.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .other && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel
        }
    }
}

#if os(iOS)
extension MermaidWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, context.coordinator) }
}
#else
extension MermaidWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, context.coordinator) }
}
#endif
