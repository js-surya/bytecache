import XCTest
@testable import ByteCatchFeatures

final class SecretScannerTests: XCTestCase {
    private func kinds(_ text: String) -> [SecretKind] { SecretScanner.scan(text).map(\.kind) }

    // Fake values with the right shapes (not real credentials).
    func testFindsCommonCredentials() {
        XCTAssertEqual(kinds("aws_access_key_id = AKIAIOSFODNN7EXAMPLE"), [.awsAccessKey])
        XCTAssertEqual(kinds("token: ghp_" + String(repeating: "a1B2", count: 9)), [.githubToken])
        XCTAssertEqual(kinds("STRIPE=sk_live_" + String(repeating: "4eC39HqLyjWDarjtT1zdp7dc", count: 1)), [.stripeKey])
        XCTAssertEqual(kinds("SLACK=xoxb-123456789012-123456789012-abcdefghijklmnopqrstuvwx"), [.slackToken])
        XCTAssertEqual(kinds("OPENAI_API_KEY=sk-proj-" + String(repeating: "Ab3d", count: 12)), [.openAIKey])
        XCTAssertEqual(kinds("key = AIza" + String(repeating: "Sy", count: 17) + "A"), [.googleAPIKey])
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        XCTAssertEqual(kinds("Authorization: Bearer \(jwt)"), [.jwt])
        XCTAssertEqual(kinds("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk\n-----END OPENSSH PRIVATE KEY-----"), [.privateKey])
        XCTAssertEqual(kinds(#"db_password = "hunter2-very-secret""#), [.password])
        XCTAssertEqual(kinds("postgres://admin:S3cretPass@db.example.com:5432/app"), [.connectionString])
    }

    func testIgnoresOrdinaryCode() {
        let code = """
        let password = getPassword()
        api_key = os.environ["API_KEY"]
        token = request.headers.get("Authorization")
        id = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
        password: ${{ secrets.DB_PASSWORD }}
        const secret = process.env.SECRET
        password = ""
        postgres://localhost/app
        """
        XCTAssertEqual(SecretScanner.scan(code), [])
    }

    func testRedactReplacesOnlyTheSecretValues() {
        let text = "export GITHUB_TOKEN=ghp_\(String(repeating: "x9Y8", count: 9))\necho done"
        XCTAssertEqual(SecretScanner.redact(text), "export GITHUB_TOKEN={{SECRET}}\necho done")
        XCTAssertEqual(SecretScanner.redact(#"password = "hunter2-very-secret""#), #"password = "{{SECRET}}""#)
        XCTAssertEqual(SecretScanner.redact("postgres://admin:S3cretPass@db/app"), "postgres://admin:{{SECRET}}@db/app")
    }

    func testFindingsReportLineNumbers() {
        let findings = SecretScanner.scan("a\nb\nAKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(findings.first?.line, 3)
        XCTAssertEqual(findings.first?.kind.title, "AWS access key")
    }
}
