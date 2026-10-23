import XCTest
import ByteCacheCore
@testable import ByteCacheFeatures

/// CP-79: Explain results kept as AI Notes, limited, clearable and synced through iCloud.
@MainActor
final class AINoteStoreTests: XCTestCase {
    private let server = "https://a.io"

    private func directory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func settings(sync: Bool = true, limit: Int = 50) -> AppSettings {
        let name = "bytecache.ainotes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults)
        s.iCloudSyncEnabled = sync
        s.aiNotesLimit = limit
        return s
    }

    func testSavesAndReadsANoteAcrossLaunches() {
        let dir = directory()
        let store = AINoteStore(directory: dir, settings: settings(), cloud: nil)
        store.save("Prints hello.", code: "echo hi", server: server, snippetID: 7)
        let again = AINoteStore(directory: dir, settings: settings(), cloud: nil)
        XCTAssertEqual(again.note(server: server, snippetID: 7)?.text, "Prints hello.")
        XCTAssertNil(again.note(server: server, snippetID: 8))
        XCTAssertNil(again.note(server: "https://b.io", snippetID: 7), "servers don't mix")
    }

    func testKnowsWhenTheCodeChanged() throws {
        let store = AINoteStore(directory: directory(), settings: settings(), cloud: nil)
        store.save("Prints hello.", code: "echo hi", server: server, snippetID: 7)
        let note = try XCTUnwrap(store.note(server: server, snippetID: 7))
        XCTAssertFalse(note.isStale(for: "echo hi"))
        XCTAssertTrue(note.isStale(for: "echo bye"))
    }

    func testKeepsOnlyTheNewestUpToTheLimit() {
        let store = AINoteStore(directory: directory(), settings: settings(limit: 25), cloud: nil)
        for id in 1...30 { store.save("note \(id)", code: "x", server: server, snippetID: id, date: Date(timeIntervalSince1970: Double(id))) }
        XCTAssertEqual(store.count, 25)
        XCTAssertNil(store.note(server: server, snippetID: 5), "the oldest went")
        XCTAssertNotNil(store.note(server: server, snippetID: 6))
        XCTAssertNotNil(store.note(server: server, snippetID: 30))
    }

    func testLongExplanationsAreCut() {
        let store = AINoteStore(directory: directory(), settings: settings(), cloud: nil)
        store.save(String(repeating: "a", count: 10_000), code: "x", server: server, snippetID: 1)
        XCTAssertEqual(store.note(server: server, snippetID: 1)?.text.count, AINoteStore.maxCharacters)
    }

    func testSyncsThroughICloudWhenOn() {
        let cloud = InMemorySyncStore()
        let store = AINoteStore(directory: directory(), settings: settings(sync: true), cloud: cloud)
        store.save("Prints hello.", code: "echo hi", server: server, snippetID: 7)
        XCTAssertEqual(cloud.allKeys.filter { $0.hasPrefix(AINoteStore.keyPrefix) }.count, 1)

        let other = AINoteStore(directory: directory(), settings: settings(sync: true), cloud: cloud)
        other.start()
        XCTAssertEqual(other.note(server: server, snippetID: 7)?.text, "Prints hello.", "another device gets it")

        store.delete(server: server, snippetID: 7)
        XCTAssertTrue(cloud.allKeys.filter { $0.hasPrefix(AINoteStore.keyPrefix) }.isEmpty)
    }

    func testDeletingOnAnotherDeviceDeletesHere() {
        let cloud = InMemorySyncStore()
        let here = AINoteStore(directory: directory(), settings: settings(), cloud: cloud)
        here.save("Prints hello.", code: "echo hi", server: server, snippetID: 7)
        let there = AINoteStore(directory: directory(), settings: settings(), cloud: cloud)
        there.start()
        there.clearAll()
        here.remoteChanged(keys: [AINoteStore.key(server, 7)])
        XCTAssertNil(here.note(server: server, snippetID: 7))
    }

    func testStaysOnTheDeviceWhenSyncIsOff() {
        let cloud = InMemorySyncStore()
        let store = AINoteStore(directory: directory(), settings: settings(sync: false), cloud: cloud)
        store.save("Prints hello.", code: "echo hi", server: server, snippetID: 7)
        XCTAssertTrue(cloud.allKeys.isEmpty)
    }

    func testClearAllRemovesEverything() {
        let cloud = InMemorySyncStore()
        let store = AINoteStore(directory: directory(), settings: settings(), cloud: cloud)
        for id in 1...3 { store.save("n", code: "x", server: server, snippetID: id) }
        XCTAssertGreaterThan(store.byteSize, 0)
        store.clearAll()
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(cloud.allKeys.filter { $0.hasPrefix(AINoteStore.keyPrefix) }.isEmpty)
    }
}
