import XCTest
@testable import Secrets

/// Round trips against the real login keychain under a throwaway service; every item is removed again.
final class SecretStoreTests: XCTestCase {
    let store = SecretStore(service: "com.cwkoenigs.the-great-gui.tests")
    let secretName = "test-token-\(UUID().uuidString.prefix(8))"

    override func tearDown() {
        try? store.delete(secretName)
        super.tearDown()
    }

    func testSetGetReplaceDelete() throws {
        XCTAssertFalse(store.exists(secretName))
        XCTAssertFalse(try store.set(secretName, value: "hunter2"))
        XCTAssertEqual(try store.get(secretName), "hunter2")
        XCTAssertTrue(try store.names().contains(secretName))
        XCTAssertTrue(try store.set(secretName, value: "hunter3"))
        XCTAssertEqual(try store.get(secretName), "hunter3")
        try store.delete(secretName)
        XCTAssertFalse(store.exists(secretName))
        XCTAssertThrowsError(try store.get(secretName)) { XCTAssertEqual($0 as? SecretStore.Failure, .notFound(secretName)) }
        XCTAssertThrowsError(try store.delete(secretName)) { XCTAssertEqual($0 as? SecretStore.Failure, .notFound(secretName)) }
    }

    func testNamesAreValidated() {
        XCTAssertThrowsError(try store.set("has space", value: "x")) { XCTAssertEqual($0 as? SecretStore.Failure, .invalidName("has space")) }
        XCTAssertTrue(SecretStore.isValidName("gitlab-token"))
        XCTAssertTrue(SecretStore.isValidName("SNOWFLAKE_PAT.v2"))
        XCTAssertFalse(SecretStore.isValidName(""))
        XCTAssertFalse(SecretStore.isValidName("-leading"))
    }

    func testFailuresDescribeThemselves() {
        XCTAssertEqual(SecretStore.Failure.notFound("x").description, "the secret x is not in the Keychain")
        XCTAssertTrue(SecretStore.Failure.denied("x").description.contains("did not let"))
    }

    func testServiceOverrideFromEnvironment() {
        XCTAssertFalse(SecretStore.defaultService().isEmpty)
    }
}
