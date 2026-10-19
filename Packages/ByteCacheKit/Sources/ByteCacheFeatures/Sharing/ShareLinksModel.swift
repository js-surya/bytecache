import ByteCacheCore
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Observation

public enum ShareExpiry: String, CaseIterable, Identifiable, Sendable {
    case never, oneHour, oneDay, oneWeek, thirtyDays
    public var id: String { rawValue }

    public var seconds: Int? {
        switch self {
        case .never: nil
        case .oneHour: 3600
        case .oneDay: 86_400
        case .oneWeek: 604_800
        case .thirtyDays: 2_592_000
        }
    }

    public var title: String {
        switch self {
        case .never: "Never"
        case .oneHour: "1 Hour"
        case .oneDay: "1 Day"
        case .oneWeek: "7 Days"
        case .thirtyDays: "30 Days"
        }
    }
}

/// Share links for one snippet: create (with expiry / sign-in requirement), list, revoke.
@MainActor @Observable
public final class ShareLinksModel {
    public private(set) var links: [ByteCacheCore.ShareLink] = []
    public private(set) var newestURL: URL?
    public private(set) var isWorking = false
    public var expiry = ShareExpiry.oneWeek
    public var requiresAuth = false
    public var error: String?

    private let session: SessionManager
    private let snippetID: Int

    public init(session: SessionManager, snippetID: Int) {
        self.session = session
        self.snippetID = snippetID
    }

    /// ByteStash only accepts share requests from password sign-ins (not API keys).
    public var canManage: Bool {
        guard let client = session.client else { return false }
        return client.apiKey == nil && client.token != nil
    }

    public func url(for link: ByteCacheCore.ShareLink) -> URL? {
        session.client.map { ByteCacheCore.ShareLink.url(id: link.id, server: $0.server) }
    }

    public func load() async {
        guard canManage, let client = session.client else { return }
        do {
            links = try await client.shareLinks(snippetID: snippetID)
            error = nil
        } catch {
            show(error)
        }
    }

    public func create() async {
        guard canManage, let client = session.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let id = try await client.createShareLink(snippetID: snippetID, requiresAuth: requiresAuth, expiresIn: expiry.seconds)
            newestURL = ByteCacheCore.ShareLink.url(id: id, server: client.server)
            await load()
        } catch {
            show(error)
        }
    }

    public func revoke(_ link: ByteCacheCore.ShareLink) async {
        guard let client = session.client else { return }
        let before = links
        links.removeAll { $0.id == link.id }
        if newestURL?.lastPathComponent == link.id { newestURL = nil }
        do {
            try await client.revokeShareLink(id: link.id)
        } catch {
            links = before
            show(error)
        }
    }

    private func show(_ apiError: APIError) {
        switch apiError {
        case .unauthorized: session.handleUnauthorized()
        case .server(_, let message?), .forbidden(let message?): error = message
        default: error = ErrorText.message(for: apiError)
        }
    }
}

/// QR codes for share links (CoreImage, on device).
public enum QRCode {
    public static func cgImage(for text: String, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
