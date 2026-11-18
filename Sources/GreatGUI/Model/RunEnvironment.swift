import Foundation
import Registry
import Secrets

/// What a command's process is given beyond the shell's own environment, and what its output must not
/// show. The window and `great-gui run` both build it here, so a scheduled run and a clicked one get the
/// same thing. The order: the env file's entries first, then the command's own `env`, which wins.
enum RunEnvironment {
    struct Built: Sendable {
        var env: [String: String] = [:]
        var redact: [String] = []
    }

    /// Why a run cannot start, in the window's two lines.
    struct Refusal: Error, Sendable {
        var what: String
        var fix: String
    }

    /// An env file holds settings as well as secrets, and masking `1` or `true` would shred the output:
    /// only values this long or longer are redacted. A `keychain:NAME` env value is always redacted.
    static let minRedactedLength = 6

    static func build(_ r: Resolved, secrets: SecretStore) throws -> Built {
        var out = Built()
        if let name = r.envFile {
            let text = try read(name, for: r.name, kind: "env file", fix: "great-gui file add \(name) --path /path/to/.env stores it; or ⌘K → Add file", secrets: secrets)
            do {
                for (key, value) in try DotEnv.parse(text) {
                    out.env[key] = value
                    if value.count >= minRedactedLength { out.redact.append(value) }
                }
            } catch let e as FileSecretError {
                throw Refusal(what: "\(r.name): \(name): \(e.what)", fix: e.fix)
            }
        }
        for (key, value) in r.env {
            switch value {
            case .literal(let s):
                out.env[key] = s
            case .keychain(let name):
                let s = try read(name, for: r.name, kind: "secret", fix: "⌘K adds it", secrets: secrets)
                out.env[key] = s
                out.redact.append(s)
            }
        }
        return out
    }

    private static func read(_ name: String, for command: String, kind: String, fix: String, secrets: SecretStore) throws -> String {
        do {
            return try secrets.get(name)
        } catch SecretStore.Failure.notFound {
            throw Refusal(what: "\(command) needs the \(kind) \(name), which is not in the Keychain", fix: fix)
        } catch SecretStore.Failure.denied {
            throw Refusal(what: "the Keychain did not let this app read \(name)",
                          fix: "allow the-great-gui in the Keychain dialog, or sign the build with a certificate (README › Signing)")
        } catch {
            throw Refusal(what: "\(error)", fix: "")
        }
    }
}
