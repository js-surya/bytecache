import ByteCacheCore

/// User-facing copy for API errors.
public enum ErrorText {
    public static func message(for error: APIError) -> String {
        switch error {
        case .invalidServer: "Enter a server address like https://bytestash.example.com."
        case .unauthorized: "Wrong username or password, or your session expired."
        case .forbidden(let message): message ?? "The server refused this request."
        case .notFound: "That snippet no longer exists on the server."
        case .server(let status, let message): "Server error (\(status))" + (message.map { ": \($0)" } ?? "")
        case .offline: "You're offline. Check your connection and try again."
        case .decoding: "The server sent a response ByteCache didn't understand."
        case .notByteStash: "That address doesn't look like a ByteStash server."
        case .duplicateServer: "Another saved server already uses that address."
        }
    }
}
