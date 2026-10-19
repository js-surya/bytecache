import XCTest
@testable import ByteCatchCore
import ByteCatchTestSupport

final class AccountAPITests: XCTestCase {
    private func client(_ stub: StubTransport) throws -> APIClient {
        APIClient(server: try ServerURL("https://x.io"), token: "t", transport: stub)
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testListKeys() async throws {
        let stub = StubTransport(body: #"[{"id":3,"name":"Laptop","created_at":"2026-10-18 10:00:00Z","last_used_at":null,"is_active":1}]"#)
        let keys = try await client(stub).apiKeys()
        XCTAssertEqual(stub.last.url?.path, "/api/keys")
        XCTAssertEqual(keys.map(\.name), ["Laptop"])
        XCTAssertTrue(keys[0].isActive)
        XCTAssertNil(keys[0].lastUsedAt)
        XCTAssertNotNil(keys[0].createdAt)
    }

    func testCreateKeyReturnsSecretOnce() async throws {
        let stub = StubTransport(status: 201, body: #"{"id":4,"key":"abc123","name":"Phone","created_at":"2026-10-19T01:00:00.000Z","is_active":true}"#)
        let created = try await client(stub).createAPIKey(name: "Phone")
        XCTAssertEqual(stub.last.httpMethod, "POST")
        XCTAssertEqual(try body(stub.last)["name"] as? String, "Phone")
        XCTAssertEqual(created.key, "abc123")
        XCTAssertEqual(created.info.id, 4)
    }

    func testDeleteKey() async throws {
        let stub = StubTransport(body: #"{"sucess":true}"#)
        try await client(stub).deleteAPIKey(id: 4)
        XCTAssertEqual(stub.last.httpMethod, "DELETE")
        XCTAssertEqual(stub.last.url?.path, "/api/keys/4")
    }

    func testChangePassword() async throws {
        let stub = StubTransport(body: #"{"success":true,"message":"Password changed successfully"}"#)
        try await client(stub).changePassword(current: "old", new: "newpass1")
        XCTAssertEqual(stub.last.url?.path, "/api/auth/change-password")
        XCTAssertEqual(try body(stub.last)["currentPassword"] as? String, "old")
        XCTAssertEqual(try body(stub.last)["newPassword"] as? String, "newpass1")
    }

    func testAuthConfigReadsPasswordChangeFlag() throws {
        let off = try JSONDecoder.byteStash.decode(AuthConfig.self, from: Data(#"{"authRequired":true,"allowPasswordChanges":false}"#.utf8))
        XCTAssertFalse(off.allowPasswordChanges)
        let missing = try JSONDecoder.byteStash.decode(AuthConfig.self, from: Data(#"{"authRequired":true}"#.utf8))
        XCTAssertTrue(missing.allowPasswordChanges)
    }
}
