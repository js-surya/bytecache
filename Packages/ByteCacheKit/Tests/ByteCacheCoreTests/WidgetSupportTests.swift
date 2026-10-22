import XCTest
@testable import ByteCacheCore

final class WidgetSnapshotTests: XCTestCase {
    private func snippet(_ id: Int, code: String, language: String = "swift") -> Snippet {
        Snippet(id: id, title: "S\(id)", description: "", updatedAt: nil, expiryDate: nil, isPublic: false,
                isPinned: false, isFavorite: false, categories: [],
                fragments: [Fragment(id: 1, fileName: "a", code: code, language: language, position: 0)], shareCount: 0)
    }

    func testRowsKeepPreviewShortAndCodeCapped() {
        let long = (1...40).map { "line \($0)" }.joined(separator: "\n")
        let row = WidgetSnippet(snippet(1, code: long))
        XCTAssertEqual(row.preview.split(separator: "\n").count, WidgetSnippet.previewLines)
        XCTAssertEqual(row.language, "swift")
        XCTAssertEqual(row.code, long)
        let huge = String(repeating: "x", count: WidgetSnippet.maxCodeLength + 10)
        XCTAssertEqual(WidgetSnippet(snippet(2, code: huge)).code.count, WidgetSnippet.maxCodeLength)
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(directory: dir)
        XCTAssertNil(store.read())
        let snap = WidgetSnapshot(serverName: "x.io", pinned: [WidgetSnippet(snippet(1, code: "a"))],
                                  recent: [WidgetSnippet(snippet(2, code: "b"))])
        try store.write(snap)
        XCTAssertEqual(store.read()?.pinned.first?.id, 1)
        XCTAssertEqual(store.read()?.recent.first?.code, "b")
        try store.clear()
        XCTAssertNil(store.read())
    }
}

final class DeepLinkTests: XCTestCase {
    func testRoundTrips() {
        for link in [DeepLink.snippet(42), .captureClipboard, .scanCode] {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
        XCTAssertEqual(DeepLink.snippet(42).url.absoluteString, "bytecache://snippet/42")
        XCTAssertNil(DeepLink(url: URL(string: "https://x.io/snippet/1")!))
        XCTAssertNil(DeepLink(url: URL(string: "bytecache://snippet/abc")!))
    }
}

final class PendingCaptureTests: XCTestCase {
    func testRequestIsConsumedOnce() {
        let name = "bytecache.pending.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        XCTAssertNil(PendingCapture.consume(from: d))
        PendingCapture.request(.captureClipboard, in: d)
        XCTAssertEqual(PendingCapture.consume(from: d), .captureClipboard)
        XCTAssertNil(PendingCapture.consume(from: d))
    }
}

/// CP-49: installs without an App Group share the widget snapshot through the keychain.
final class WidgetKeychainFallbackTests: XCTestCase {
    private func store() -> (WidgetSnapshotStore, KeychainBlob) {
        let blob = KeychainBlob(service: "me.suryajs.bytecache.tests.\(UUID().uuidString)", account: "snapshot", accessGroup: nil)
        addTeardownBlock { blob.delete() }
        return (WidgetSnapshotStore(keychain: blob), blob)
    }

    private func snippet(code: String) -> WidgetSnippet {
        WidgetSnippet(Snippet(id: 1, title: "t", description: "", updatedAt: nil, expiryDate: nil, isPublic: false,
                              isPinned: false, isFavorite: false, categories: [],
                              fragments: [Fragment(id: 1, fileName: "f", code: code, language: "bash", position: 0)],
                              shareCount: 0))
    }

    func testNothingWrittenMeansUnavailable() {
        XCTAssertEqual(store().0.state(), .unavailable)
        XCTAssertEqual(store().0.sharing, "Shared keychain")
    }

    func testWritesACompactSnapshotAndSignsOutExplicitly() throws {
        let (store, _) = store()
        let long = String(repeating: "x", count: WidgetSnapshotStore.keychainCodeLimit + 500)
        try store.write(WidgetSnapshot(serverName: "x.io", pinned: [], recent: [snippet(code: long)]))
        XCTAssertEqual(store.read()?.recent.first?.code.count, WidgetSnapshotStore.keychainCodeLimit)
        try store.clear()
        XCTAssertEqual(store.state(), .signedOut)
    }
}
