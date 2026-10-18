import ByteCatchCore
import CoreSpotlight
import UniformTypeIdentifiers

/// Makes recently seen snippets findable in Spotlight. Selecting one opens ByteCatch with
/// `CSSearchableItemActionType` and the snippet id as `CSSearchableItemActivityIdentifier`.
public enum SpotlightIndexer {
    public static func index(_ snippets: [Snippet], server: ServerURL) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let items = snippets.map { snippet in
            let attributes = CSSearchableItemAttributeSet(contentType: .sourceCode)
            attributes.title = snippet.title
            let code = snippet.fragments.sorted { $0.position < $1.position }.first?.code ?? ""
            attributes.contentDescription = String(code.prefix(300))
            attributes.keywords = snippet.categories + snippet.fragments.map(\.language)
            return CSSearchableItem(uniqueIdentifier: String(snippet.id), domainIdentifier: server.cacheKey, attributeSet: attributes)
        }
        CSSearchableIndex.default().indexSearchableItems(items)
    }

    public static func remove(ids: [Int]) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(String.init))
    }

    public static func removeAll() {
        CSSearchableIndex.default().deleteAllSearchableItems()
    }
}
