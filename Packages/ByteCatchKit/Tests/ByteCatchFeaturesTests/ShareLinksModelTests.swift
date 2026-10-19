import XCTest
import ByteCatchCore
import ByteCatchTestSupport
@testable import ByteCatchFeatures

@MainActor
final class ShareLinksModelTests: XCTestCase {
    private let listJSON = #"[{"id":"old1","snippet_id":3,"requires_auth":0,"expires_at":null,"created_at":"2026-10-18 09:00:00","expired":0}]"#

    func testExpiryPresets() {
        XCTAssertNil(ShareExpiry.never.seconds)
        XCTAssertEqual(ShareExpiry.oneHour.seconds, 3600)
        XCTAssertEqual(ShareExpiry.oneDay.seconds, 86_400)
        XCTAssertEqual(ShareExpiry.oneWeek.seconds, 604_800)
        XCTAssertEqual(ShareExpiry.thirtyDays.seconds, 2_592_000)
    }

    func testLoadCreateRevoke() async {
        let created = #"{"id":"new9","snippetId":3,"requiresAuth":false,"expiresIn":86400}"#
        let (session, transport) = await TestSession.signedIn([.json(listJSON), .json(created, status: 201),
                                                               .json(listJSON.replacingOccurrences(of: "old1", with: "new9")),
                                                               .json(#"{"success":true}"#)])
        let model = ShareLinksModel(session: session, snippetID: 3)
        XCTAssertTrue(model.canManage)
        await model.load()
        XCTAssertEqual(model.links.map(\.id), ["old1"])

        model.expiry = .oneDay
        await model.create()
        XCTAssertEqual(model.newestURL?.absoluteString, "https://x.io/s/new9")
        XCTAssertEqual(model.links.first?.id, "new9")

        await model.revoke(model.links[0])
        XCTAssertEqual(transport.last.httpMethod, "DELETE")
        XCTAssertFalse(model.links.contains { $0.id == "new9" })
    }

    func testAPIKeySessionsCannotShare() async throws {
        let store = InMemoryCredentialStore(Credentials(server: TestSession.server, apiKey: "k"))
        let session = SessionManager(store: store, transport: StubTransport([.json(#"{"categories":[],"languages":[]}"#)]))
        await session.restore()
        XCTAssertFalse(ShareLinksModel(session: session, snippetID: 3).canManage)
    }

    func testQRCodeIsGenerated() {
        let image = QRCode.cgImage(for: "https://x.io/s/abc")
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.width ?? 0, 100)
    }
}
