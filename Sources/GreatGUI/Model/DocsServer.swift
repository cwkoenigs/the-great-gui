import Foundation
import Network
import UniformTypeIdentifiers

/// A read-only static file server, bound to IPv4 loopback on a port assigned by macOS.
final class DocsServer {
    private let site: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "the-great-gui.docs-http")
    private static let headerEnd = Data("\r\n\r\n".utf8)
    private static let headerLimit = 16 * 1024

    init(site: URL) throws {
        self.site = site
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    deinit { listener.cancel() }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 10) { [weak connection] in connection?.cancel() }
                self.receive(connection, prefix: Data())
            }
            listener.stateUpdateHandler = { [weak listener] state in
                guard let listener else { return }
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    guard let port = listener.port else {
                        continuation.resume(throwing: DocsBuild.Failure(message: "macOS did not assign a local port."))
                        return
                    }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/")!)
                case .failed(let error), .waiting(let error):
                    listener.stateUpdateHandler = nil
                    listener.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func receive(_ connection: NWConnection, prefix: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.headerLimit - prefix.count) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            let request = prefix + (data ?? Data())
            if let end = request.range(of: Self.headerEnd)?.lowerBound {
                self.handle(connection, request: String(decoding: request[..<end], as: UTF8.self))
            } else if request.count == Self.headerLimit || complete {
                self.reply(connection, status: "400 Bad Request")
            } else {
                self.receive(connection, prefix: request)
            }
        }
    }

    private func handle(_ connection: NWConnection, request: String) {
        let lines = request.components(separatedBy: "\r\n")
        let line = lines[0].split(separator: " ")
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
        guard line.count == 3, let port = listener.port, hosts.count == 1,
              hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == "127.0.0.1:\(port.rawValue)" else {
            reply(connection, status: "400 Bad Request")
            return
        }
        guard line[0] == "GET" || line[0] == "HEAD" else {
            reply(connection, status: "405 Method Not Allowed", headers: "Allow: GET, HEAD\r\n")
            return
        }
        guard let file = file(for: String(line[1])),
              let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            reply(connection, status: "404 Not Found")
            return
        }
        let type = file.pathExtension == "js" ? "text/javascript" :
            (UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
        reply(connection, status: "200 OK", type: type, body: data, head: line[0] == "HEAD")
    }

    private func file(for target: String) -> URL? {
        guard target.hasPrefix("/"), !target.hasPrefix("//"),
              let path = target.split(separator: "?", maxSplits: 1)[0].removingPercentEncoding,
              !path.contains("\0") else { return nil }
        let parts = path.split(separator: "/")
        guard parts.allSatisfy({ !$0.hasPrefix(".") }) else { return nil }

        let root = site.resolvingSymlinksInPath().standardizedFileURL
        let file = parts.reduce(root) { $0.appendingPathComponent(String($1)) }
        for candidate in [file, file.appendingPathComponent("index.html")] {
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(root.path + "/") else { continue }
            if (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return resolved }
        }
        return nil
    }

    private func reply(_ connection: NWConnection, status: String, type: String = "text/plain",
                       headers: String = "", body: Data = Data(), head: Bool = false) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Connection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n" + headers + "\r\n"
        let response = Data(header.utf8) + (head ? Data() : body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
