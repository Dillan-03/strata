import StrataCore
import XCTest

final class SecretRedactorTests: XCTestCase {
    private let mask = SecretRedactor.mask

    func testMasksValueAfterSensitiveFlag() {
        let arguments = ["--port", "8080", "--api-key", "abc123", "--token", "${GITHUB_TOKEN}"]
        XCTAssertEqual(SecretRedactor.redactArguments(arguments), ["--port", "8080", "--api-key", mask, "--token", "${GITHUB_TOKEN}"])
    }

    func testMasksFlagEqualsValue() {
        XCTAssertEqual(SecretRedactor.redactArguments(["--password=hunter2", "--name=demo"]), ["--password=\(mask)", "--name=demo"])
    }

    func testMasksTokenShapedArguments() {
        let redacted = SecretRedactor.redactArguments([
            "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWX",
            "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
            "xoxb-1234567890-abcdefghij",
            "AKIAABCDEFGHIJKLMNOP",
            "plain-argument",
        ])
        XCTAssertEqual(redacted, [mask, mask, mask, mask, "plain-argument"])
    }

    func testMasksPasswordsInConnectionStringArguments() {
        let redacted = SecretRedactor.redactArguments(["-y", "server-postgres", "postgresql://app:example-password@localhost/acme"])
        XCTAssertFalse(redacted.joined().contains("example-password"))
        XCTAssertTrue(redacted[2].contains("localhost/acme"))
    }

    func testMasksBearerTokenInsideText() {
        XCTAssertEqual(SecretRedactor.redactText("Authorization: Bearer abcdef123456"), "Authorization: \(mask)")
    }

    func testRedactsURLCredentialsAndSecretQueryValues() {
        let redacted = SecretRedactor.redactURL("https://user:pa55@mcp.example.com/sse?token=s3cr3t&region=eu")
        XCTAssertFalse(redacted.contains("pa55"))
        XCTAssertFalse(redacted.contains("s3cr3t"))
        XCTAssertFalse(redacted.contains("user:"))
        XCTAssertTrue(redacted.contains("region=eu"))
        XCTAssertTrue(redacted.contains("mcp.example.com"))
    }

    func testLeavesOrdinaryURLsAlone() {
        XCTAssertEqual(SecretRedactor.redactURL("https://mcp.stripe.com/v1"), "https://mcp.stripe.com/v1")
    }

    func testMapRedactionMasksEveryValueButKeepsVariableReferences() {
        let redacted = SecretRedactor.redactMap(["DB_URL": "postgres://u:p@h/db", "API_KEY": "${API_KEY}", "REGION": "eu"], maskAllValues: true)
        XCTAssertEqual(redacted.map(\.key), ["API_KEY", "DB_URL", "REGION"])
        XCTAssertEqual(redacted.map(\.value), ["${API_KEY}", mask, mask])
    }

    func testSensitiveNameDetection() {
        for name in ["Authorization", "X-Api-Key", "GITHUB_TOKEN", "client_secret", "DB_PASSWORD", "OPENAI_KEY"] {
            XCTAssertTrue(SecretRedactor.isSensitiveName(name), name)
        }
        for name in ["REGION", "PORT", "LOG_LEVEL"] {
            XCTAssertFalse(SecretRedactor.isSensitiveName(name), name)
        }
    }
}
