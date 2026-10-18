import Foundation

/// Talks to a ByteStash server's HTTP API. Stateless: create one per server and login.
/// Authenticates with a session token (`bytestashauth`) or an API key (`x-api-key`; ByteStash
/// accepts keys on `/api/snippets/...` only, which covers everything the app does once signed in).
public struct APIClient: Sendable {
    public let server: ServerURL
    public let token: String?
    public let apiKey: String?
    private let transport: any HTTPTransport

    public init(server: ServerURL, token: String?, apiKey: String? = nil, transport: any HTTPTransport = URLSession.shared) {
        self.server = server
        self.token = token
        self.apiKey = apiKey
        self.transport = transport
    }

    // MARK: Auth

    public func authConfig() async throws(APIError) -> AuthConfig {
        try await send(.get, "/api/auth/config")
    }

    public func login(username: String, password: String) async throws(APIError) -> (token: String, user: User) {
        let response: LoginResponse = try await send(
            .post, "/api/auth/login", body: LoginBody(username: username, password: password)
        )
        guard let user = response.user else { throw .decoding("Login response had no user") }
        return (response.token, user)
    }

    /// For single-user servers that don't require a login.
    public func anonymousLogin() async throws(APIError) -> (token: String, user: User) {
        let response: LoginResponse = try await send(.post, "/api/auth/anonymous")
        return (response.token, response.user ?? User(id: 0, username: "anonymous"))
    }

    /// Checks the current token; throws `.unauthorized` when it is expired or revoked.
    public func verify() async throws(APIError) -> User {
        let response: VerifyResponse = try await send(.get, "/api/auth/verify")
        guard response.valid, let user = response.user else { throw .unauthorized }
        return user
    }

    // MARK: Snippets

    public func snippets(_ query: SnippetQuery) async throws(APIError) -> SnippetPage {
        try await send(.get, "/api/snippets", query: query.queryItems)
    }

    public func snippet(id: Int) async throws(APIError) -> Snippet {
        try await send(.get, "/api/snippets/\(id)")
    }

    public func metadata() async throws(APIError) -> SnippetMetadata {
        try await send(.get, "/api/snippets/metadata")
    }

    public func create(_ draft: SnippetDraft) async throws(APIError) -> Snippet {
        try await send(.post, "/api/snippets", body: draft)
    }

    /// Replaces the whole snippet; build the draft with `SnippetDraft(from:)` so nothing is dropped.
    public func update(id: Int, _ draft: SnippetDraft) async throws(APIError) -> Snippet {
        try await send(.put, "/api/snippets/\(id)", body: draft)
    }

    public func setPinned(id: Int, _ value: Bool) async throws(APIError) {
        try await sendVoid(.patch, "/api/snippets/\(id)/pin", body: ["is_pinned": value])
    }

    public func setFavorite(id: Int, _ value: Bool) async throws(APIError) {
        try await sendVoid(.patch, "/api/snippets/\(id)/favorite", body: ["is_favorite": value])
    }

    public func recycle(id: Int) async throws(APIError) {
        try await sendVoid(.patch, "/api/snippets/\(id)/recycle")
    }

    public func restore(id: Int) async throws(APIError) {
        try await sendVoid(.patch, "/api/snippets/\(id)/restore")
    }

    public func delete(id: Int) async throws(APIError) {
        try await sendVoid(.delete, "/api/snippets/\(id)")
    }
}

// MARK: - Transport

private enum Method: String {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

private struct LoginBody: Encodable {
    let username: String
    let password: String
}

private struct LoginResponse: Decodable {
    let token: String
    let user: User?
}

private struct VerifyResponse: Decodable {
    let valid: Bool
    let user: User?
}

private struct ErrorBody: Decodable {
    let error: String?
}

extension APIClient {
    private static let timeout: TimeInterval = 30

    private func send<T: Decodable>(
        _ method: Method, _ path: String,
        query: [URLQueryItem] = [], body: (any Encodable)? = nil
    ) async throws(APIError) -> T {
        let data = try await perform(method, path, query: query, body: body)
        do {
            return try JSONDecoder.byteStash.decode(T.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    private func sendVoid(
        _ method: Method, _ path: String, body: (any Encodable)? = nil
    ) async throws(APIError) {
        _ = try await perform(method, path, query: [], body: body)
    }

    /// Sends one request and maps every failure to an `APIError`.
    private func perform(
        _ method: Method, _ path: String, query: [URLQueryItem], body: (any Encodable)?
    ) async throws(APIError) -> Data {
        var url = server.endpoint(path)
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw .invalidServer
            }
            components.queryItems = query
            guard let withQuery = components.url else { throw .invalidServer }
            url = withQuery
        }

        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        } else if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "bytestashauth")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw .decoding("Could not encode request: \(error)")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            throw .offline
        }

        guard let http = response as? HTTPURLResponse else { throw .notByteStash }
        switch http.statusCode {
        case 200..<300:
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("text/html") { throw .notByteStash }
            return data
        case 401: throw .unauthorized
        case 403: throw .forbidden(Self.message(in: data))
        case 404: throw .notFound
        default: throw .server(status: http.statusCode, message: Self.message(in: data))
        }
    }

    private static func message(in data: Data) -> String? {
        try? JSONDecoder().decode(ErrorBody.self, from: data).error
    }

    private static func map(_ error: URLError) -> APIError {
        switch error.code {
        case .badURL, .unsupportedURL: .invalidServer
        default: .offline
        }
    }
}
