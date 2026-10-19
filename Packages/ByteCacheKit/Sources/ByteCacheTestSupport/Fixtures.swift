import ByteCacheCore
import Foundation

/// JSON builders and a ready signed-in session for feature tests.
public enum TestJSON {
    public static func snippet(
        _ id: Int, title: String = "Snippet", code: String = "echo hi", language: String = "bash",
        pinned: Bool = false, favorite: Bool = false, isPublic: Bool = false, categories: [String] = []
    ) -> String {
        let cats = categories.map { "\"\($0)\"" }.joined(separator: ",")
        let escaped = code.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return #"{"id":\#(id),"title":"\#(title)","description":"","updated_at":"2026-10-18 00:45:14Z","expiry_date":null,"is_public":\#(isPublic ? 1 : 0),"is_pinned":\#(pinned ? 1 : 0),"is_favorite":\#(favorite ? 1 : 0),"categories":[\#(cats)],"share_count":0,"fragments":[{"id":\#(id * 10),"file_name":"main","code":"\#(escaped)","language":"\#(language)","position":0}]}"#
    }

    public static func page(_ snippets: [String], total: Int? = nil, offset: Int = 0, limit: Int = 50) -> String {
        let count = total ?? snippets.count
        return #"{"data":[\#(snippets.joined(separator: ","))],"pagination":{"total":\#(count),"offset":\#(offset),"limit":\#(limit),"hasMore":\#(offset + limit < count)}}"#
    }

    public static let verify = #"{"valid":true,"user":{"id":2,"username":"demo"}}"#
}

extension StubTransport.Reply {
    public static func json(_ body: String, status: Int = 200) -> Self {
        .response(status: status, body: body, contentType: "application/json")
    }
}

@MainActor
public enum TestSession {
    public static let server = try! ServerURL("https://x.io")

    /// A session already signed in as `demo`; `replies` follow the verify call.
    public static func signedIn(_ replies: [StubTransport.Reply]) async -> (SessionManager, StubTransport) {
        let transport = StubTransport([.json(TestJSON.verify)] + replies)
        let store = InMemoryCredentialStore(Credentials(server: server, token: "t", username: "demo"))
        let session = SessionManager(store: store, transport: transport)
        await session.restore()
        return (session, transport)
    }
}
