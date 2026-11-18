import Foundation
import TOMLKit

/// Editing the file in place. The file is read as the text before the first `[[command]]` or `[[file]]`
/// and then one block per entry: the comment lines directly above its header, the header, and everything
/// up to the next block. Replace, remove and reorder touch only the blocks they name; the rest of the file, comments
/// and hand-written entries included, is kept as it is. Every write re-parses the whole file first, as
/// `append` does, so a file that does not parse is never written.
extension RegistryWriter {
    struct Block {
        enum Kind: String { case command, file, tool }
        var kind: Kind = .command
        var name: String?
        var text: String
    }

    struct Blocks {
        var preamble: String
        var blocks: [Block]
    }

    static let headerLine = try! NSRegularExpression(pattern: "^\\s*\\[\\[\\s*(command|file|tool)\\s*\\]\\]\\s*(#.*)?$")

    /// The file as its preamble and blocks. Line endings stay with their lines.
    static func split(_ text: String) -> Blocks {
        let pieces = text.components(separatedBy: "\n")
        let lines = pieces.enumerated().map { i, p in i < pieces.count - 1 ? p + "\n" : p }
        func kind(_ l: String) -> Block.Kind? {
            guard let m = headerLine.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)), let r = Range(m.range(at: 1), in: l) else { return nil }
            return Block.Kind(rawValue: String(l[r]))
        }
        func isComment(_ l: String) -> Bool { l.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        var starts: [Int] = []
        var kinds: [Block.Kind] = []
        for (i, l) in lines.enumerated() {
            guard let k = kind(l) else { continue }
            var s = i
            while s > 0, isComment(lines[s - 1]) { s -= 1 }
            starts.append(s)
            kinds.append(k)
        }
        guard let first = starts.first else { return Blocks(preamble: text, blocks: []) }
        var blocks: [Block] = []
        for (k, s) in starts.enumerated() {
            let e = k + 1 < starts.count ? starts[k + 1] : lines.count
            let body = lines[s..<e].joined()
            blocks.append(Block(kind: kinds[k], name: blockName(body, kind: kinds[k]), text: body))
        }
        return Blocks(preamble: lines[0..<first].joined(), blocks: blocks)
    }

    /// The command's name, read by the TOML parser so quoting and escapes are its business.
    static func blockName(_ block: String, kind: Block.Kind = .command) -> String? {
        guard let table = try? TOMLTable(string: block), let arr = table[kind.rawValue]?.array, arr.count == 1 else { return nil }
        return arr[0].table?["name"]?.string
    }

    /// The comment lines above the header, kept when a block is rewritten.
    static func leadingComments(_ block: String) -> String {
        var out = ""
        for line in block.components(separatedBy: "\n") {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { break }
            out += line + "\n"
        }
        return out
    }

    /// The blank lines that end a block, kept so the spacing between blocks does not change.
    static func trailingBlanks(_ block: String) -> String {
        var out = ""
        var rest = Substring(block)
        while rest.hasSuffix("\n") {
            rest = rest.dropLast()
            let lineStart = rest.lastIndex(of: "\n").map { rest.index(after: $0) } ?? rest.startIndex
            let line = rest[lineStart...]
            if line.allSatisfy({ $0 == " " || $0 == "\t" }) {
                out = "\n" + out
                rest = rest[..<lineStart]
            } else {
                break
            }
        }
        return out
    }

    static func read(_ url: URL) throws -> (text: String, registry: Registry) {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RegistryError("no registry at \(url.path)", fix: "great-gui add creates it")
        }
        return (text, try Registry.parse(text, url: url))
    }

    static func write(_ parts: Blocks, to url: URL) throws -> Registry {
        var text = parts.preamble + parts.blocks.map(\.text).joined()
        while text.hasSuffix("\n\n") { text.removeLast() }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        let registry = try Registry.parse(text, url: url)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return registry
    }

    static func notFound(_ name: String, in url: URL) -> RegistryError {
        RegistryError("no command named \(name)", fix: "great-gui list shows the names in \(url.lastPathComponent)")
    }

    static func unusualShape(_ name: String, in url: URL) -> RegistryError {
        RegistryError("could not find the block for \(name) in \(url.lastPathComponent)",
                      fix: "the file parses, but that block is not in the usual shape; edit the file by hand (⌥⌘E)")
    }

    // MARK: replace · remove · reorder

    /// Rewrites the block named `old` as `c`, keeping the comments above it and the spacing after it.
    /// A new name that another command has is refused.
    @discardableResult
    public static func replace(_ old: String, with c: Command, in url: URL) throws -> Registry {
        let (text, current) = try read(url)
        guard current.command(named: old) != nil else { throw notFound(old, in: url) }
        if c.name != old, current.command(named: c.name) != nil {
            throw RegistryError("a command named \(c.name) exists", fix: "pick another name")
        }
        var parts = split(text)
        guard let i = parts.blocks.firstIndex(where: { $0.kind == .command && $0.name == old }) else { throw unusualShape(old, in: url) }
        let was = parts.blocks[i].text
        parts.blocks[i] = Block(name: c.name, text: leadingComments(was) + render(c) + trailingBlanks(was))
        return try write(parts, to: url)
    }

    /// Removes the block, its comments above included.
    @discardableResult
    public static func remove(_ name: String, from url: URL) throws -> Registry {
        let (text, current) = try read(url)
        guard current.command(named: name) != nil else { throw notFound(name, in: url) }
        var parts = split(text)
        guard let i = parts.blocks.firstIndex(where: { $0.kind == .command && $0.name == name }) else { throw unusualShape(name, in: url) }
        parts.blocks.remove(at: i)
        return try write(parts, to: url)
    }

    /// Removes a `[[file]]` block, its comments above included. The Keychain item and the file on disk are not its business.
    @discardableResult
    public static func removeFile(_ name: String, from url: URL) throws -> Registry {
        let (text, current) = try read(url)
        guard current.file(named: name) != nil else {
            throw RegistryError("no file named \(name)", fix: "great-gui file lists the names in \(url.lastPathComponent)")
        }
        var parts = split(text)
        guard let i = parts.blocks.firstIndex(where: { $0.kind == .file && $0.name == name }) else { throw unusualShape(name, in: url) }
        parts.blocks.remove(at: i)
        return try write(parts, to: url)
    }

    /// Removes a `[[tool]]` block, its comments above included. Nothing is uninstalled.
    @discardableResult
    public static func removeTool(_ name: String, from url: URL) throws -> Registry {
        let (text, current) = try read(url)
        guard current.tool(named: name) != nil else {
            throw RegistryError("no tool named \(name)", fix: "great-gui tools lists the names in \(url.lastPathComponent)")
        }
        var parts = split(text)
        guard let i = parts.blocks.firstIndex(where: { $0.kind == .tool && $0.name == name }) else { throw unusualShape(name, in: url) }
        parts.blocks.remove(at: i)
        return try write(parts, to: url)
    }

    /// Puts the blocks in the order given, one blank line between them. `names` must name every command once.
    @discardableResult
    public static func reorder(_ names: [String], in url: URL) throws -> Registry {
        let (text, current) = try read(url)
        let have = current.commands.map(\.name)
        guard names.count == have.count, Set(names) == Set(have) else {
            throw RegistryError("reorder needs every command exactly once", fix: "\(names.count) given, \(have.count) in \(url.lastPathComponent)")
        }
        let parts = split(text)
        var byName: [String: Block] = [:]
        for b in parts.blocks where b.kind == .command { if let n = b.name { byName[n] = b } }
        guard byName.count == have.count, names.allSatisfy({ byName[$0] != nil }) else {
            throw RegistryError("could not tell the blocks apart in \(url.lastPathComponent)",
                                fix: "a block is not in the usual shape; edit the file by hand (⌥⌘E)")
        }
        func spaced(_ b: Block) -> Block {
            var body = Substring(b.text)
            while body.hasSuffix("\n") { body = body.dropLast() }
            return Block(kind: b.kind, name: b.name, text: body + "\n\n")
        }
        // The commands take the new order in the slots commands held; a [[file]] block keeps its place.
        var next = names.makeIterator()
        let ordered = parts.blocks.map { b in b.kind == .command ? spaced(byName[next.next()!]!) : spaced(b) }
        return try write(Blocks(preamble: parts.preamble, blocks: ordered), to: url)
    }

    // MARK: the form's text fields, from a command

    /// The inverse of `parseParam`: `name:desc=default!`.
    public static func paramSpec(_ p: Param) -> String {
        var s = p.name
        if !p.desc.isEmpty { s += ":" + p.desc }
        if let d = p.defaultValue { s += "=" + d }
        if p.required { s += "!" }
        return s
    }

    public static func paramsSpec(_ params: [Param]) -> String { params.map(paramSpec).joined(separator: "; ") }

    public static func envSpec(_ env: [String: EnvValue]) -> String {
        env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.display)" }.joined(separator: "; ")
    }
}
