import Foundation

/// The app's version. `string` is read by scripts/bundle.sh for the Info.plist; the commit is written there
/// by the same script, so a build can say exactly what it was built from (DECISIONS local-034).
enum Version {
    static let string = "0.1.0"

    /// The short commit the bundle was built from, "+changes" when the tree was not clean; nil outside a bundle.
    static var commit: String? {
        guard let c = Bundle.main.object(forInfoDictionaryKey: "GreatGUICommit") as? String, !c.isEmpty else { return nil }
        return c
    }

    /// "0.1.0 (d94ef47)", or the bare version when the commit is not known.
    static var full: String { commit.map { "\(string) (\($0))" } ?? string }
}
