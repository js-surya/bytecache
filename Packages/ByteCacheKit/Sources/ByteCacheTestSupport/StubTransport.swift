import Foundation
import ByteCacheCore

/// Records every request and replays queued responses (or errors).
public final class StubTransport: HTTPTransport, @unchecked Sendable {
    public enum Reply {
        case response(status: Int, body: String, contentType: String)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [URLRequest] = []

    public init(_ replies: [Reply]) { self.replies = replies }

    public convenience init(status: Int = 200, body: String = "{}", contentType: String = "application/json") {
        self.init([.response(status: status, body: body, contentType: contentType)])
    }

    public var requests: [URLRequest] { lock.withLock { recorded } }
    public var last: URLRequest { requests[requests.count - 1] }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let reply: Reply = lock.withLock {
            recorded.append(request)
            return replies.count > 1 ? replies.removeFirst() : replies[0]
        }
        switch reply {
        case .failure(let error):
            throw error
        case .response(let status, let body, let contentType):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": contentType]
            )!
            return (Data(body.utf8), response)
        }
    }
}
