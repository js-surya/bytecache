import ByteCatchCore
import Foundation
import Observation

public enum SidebarItem: Hashable, Sendable {
    case all, pinned, favorites, recycleBin
    case language(String)
    case category(String)

    public var title: String {
        switch self {
        case .all: "All Snippets"
        case .pinned: "Pinned"
        case .favorites: "Favorites"
        case .recycleBin: "Recycle Bin"
        case .language(let id): id
        case .category(let name): name
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin"
        case .favorites: "star"
        case .recycleBin: "trash"
        case .language: "chevron.left.forwardslash.chevron.right"
        case .category: "tag"
        }
    }
}

/// Languages and categories for the sidebar, from `/api/snippets/metadata`.
@MainActor @Observable
public final class SidebarModel {
    public private(set) var languages: [String] = []
    public private(set) var categories: [String] = []

    private let session: SessionManager

    public init(session: SessionManager) {
        self.session = session
    }

    public func load() async {
        guard let client = session.client else { return }
        do {
            let metadata = try await client.metadata()
            languages = metadata.languages.sorted()
            categories = metadata.categories.sorted()
        } catch .unauthorized {
            session.handleUnauthorized()
        } catch {
            // Offline or server trouble: keep whatever the sidebar showed before.
        }
    }
}
