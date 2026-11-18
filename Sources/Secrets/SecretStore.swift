import Foundation
import Security

/// Secrets by name: generic-password items this app owns in the login keychain, under one service.
///
/// The service is the app's bundle identifier, so the work Mac's build finds its own items and nobody
/// else's. Values are read only when a command runs and go into its environment; this type never logs,
/// prints or keeps one. Listing reads attributes only, so it never triggers a Keychain prompt.
public struct SecretStore: Sendable {
    public let service: String

    public init(service: String = SecretStore.defaultService()) { self.service = service }

    /// `GREAT_GUI_KEYCHAIN_SERVICE` overrides (a test instance keeps its items apart from yours).
    public static func defaultService() -> String {
        if let s = ProcessInfo.processInfo.environment["GREAT_GUI_KEYCHAIN_SERVICE"], !s.isEmpty { return s }
        return Bundle.main.bundleIdentifier ?? "com.cwkoenigs.the-great-gui"
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notFound(String)
        case denied(String)
        case invalidName(String)
        case other(String, Int32)

        public var description: String {
            switch self {
            case .notFound(let n): "the secret \(n) is not in the Keychain"
            case .denied(let n): "the Keychain did not let this app read \(n)"
            case .invalidName(let n): "'\(n)' is not a valid secret name"
            case .other(let m, let code): "Keychain: \(m) (\(code))"
            }
        }
    }

    public static let nameRule = try! NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$")

    public static func isValidName(_ name: String) -> Bool {
        nameRule.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    // MARK: reading

    /// Every secret's name, sorted. Attributes only: no value is read and no prompt appears.
    public func names() throws -> [String] {
        var query = base(nil)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return [] }
        try check(status, name: "")
        let items = out as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    public func exists(_ name: String) -> Bool {
        (try? names().contains(name)) ?? false
    }

    /// The value. The Keychain may ask the user to allow this app the first time a build reads an item.
    public func get(_ name: String) throws -> String {
        guard let value = String(data: try data(name), encoding: .utf8) else {
            throw Failure.other("the value of \(name) is not text", errSecSuccess)
        }
        return value
    }

    /// The value as bytes: a whole file kept under one name need not be text.
    public func data(_ name: String) throws -> Data {
        var query = base(name)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        try check(status, name: name)
        guard let data = out as? Data else { throw Failure.other("the value of \(name) could not be read", status) }
        return data
    }

    // MARK: writing

    /// Adds the secret, or replaces its value when the name exists. Returns true when it replaced.
    @discardableResult
    public func set(_ name: String, value: String) throws -> Bool {
        try setData(name, Data(value.utf8))
    }

    /// The same, for bytes.
    @discardableResult
    public func setData(_ name: String, _ data: Data) throws -> Bool {
        guard Self.isValidName(name) else { throw Failure.invalidName(name) }
        let status = SecItemUpdate(base(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { try check(status, name: name) }
        var item = base(name)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "the-great-gui · \(name)"
        item[kSecAttrDescription as String] = "the-great-gui secret"
        try check(SecItemAdd(item as CFDictionary, nil), name: name)
        return false
    }

    public func delete(_ name: String) throws {
        try check(SecItemDelete(base(name) as CFDictionary), name: name)
    }

    // MARK: plumbing

    private func base(_ name: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let name { q[kSecAttrAccount as String] = name }
        return q
    }

    private func check(_ status: OSStatus, name: String) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw Failure.notFound(name)
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecMissingEntitlement:
            throw Failure.denied(name)
        default:
            let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            throw Failure.other(message, status)
        }
    }
}
