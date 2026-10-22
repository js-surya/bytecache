import ByteCacheCore
import Foundation

/// Handoff for "viewing a snippet": the server address and snippet id, plus a web fallback
/// (`<server>/snippets/<id>` in the ByteStash web app) for devices without ByteCache.
public enum SnippetActivity {
    public static let type = "me.suryajs.bytecache.snippet"
    private static let serverKey = "server", idKey = "snippetID"

    public static func userInfo(server: ServerURL, snippetID: Int) -> [String: Any] {
        [serverKey: server.base.absoluteString, idKey: snippetID]
    }

    public static func parse(_ info: [AnyHashable: Any]?) -> (server: ServerURL, snippetID: Int)? {
        guard let raw = info?[serverKey] as? String, let server = try? ServerURL(raw),
              let id = info?[idKey] as? Int else { return nil }
        return (server, id)
    }

    public static func webURL(server: ServerURL, snippetID: Int) -> URL {
        server.endpoint("/snippets/\(snippetID)")
    }
}
