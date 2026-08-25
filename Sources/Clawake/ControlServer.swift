import Foundation

/// A tiny HTTP server on a unix domain socket. The installed Claude Code hooks
/// `curl --unix-socket ... /caffeinate|/uncaffeinate`, and this turns those into
/// callbacks. Handlers are delivered on the main queue.
final class ControlServer {
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "app.clawake.control")

    var onCaffeinate: ((String) -> Void)?
    var onUncaffeinate: ((String) -> Void)?

    func start() {
        let path = Paths.socketPath
        try? FileManager.default.createDirectory(
            at: Paths.configDir, withIntermediateDirectories: true)
        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                _ = strncpy(dst, path, 103)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0, listen(listenFD, 16) == 0 else {
            close(listenFD)
            listenFD = -1
            return
        }

        let src = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        if listenFD >= 0 { close(listenFD) }
        unlink(Paths.socketPath)
    }

    private func acceptOne() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        defer { close(clientFD) }
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = read(clientFD, &buf, buf.count)
        guard n > 0 else { return }
        let request = String(decoding: buf[0..<n], as: UTF8.self)
        handle(request, clientFD)
    }

    private func handle(_ request: String, _ fd: Int32) {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            respond(fd, 400)
            return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(fd, 400)
            return
        }
        let path = String(parts[1])

        var sessionId = "cli"
        if let r = request.range(of: "\r\n\r\n") {
            let body = String(request[r.upperBound...])
            if let data = body.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sid = obj["session_id"] as? String {
                sessionId = sid
            }
        }

        if path.hasPrefix("/caffeinate") {
            DispatchQueue.main.async { [weak self] in self?.onCaffeinate?(sessionId) }
            respond(fd, 200)
        } else if path.hasPrefix("/uncaffeinate") {
            DispatchQueue.main.async { [weak self] in self?.onUncaffeinate?(sessionId) }
            respond(fd, 200)
        } else {
            respond(fd, 404)
        }
    }

    private func respond(_ fd: Int32, _ status: Int) {
        let line = status == 200 ? "200 OK" : (status == 404 ? "404 Not Found" : "400 Bad Request")
        let resp = "HTTP/1.1 \(line)\r\nContent-Length: 0\r\n\r\n"
        let bytes = Array(resp.utf8)
        bytes.withUnsafeBufferPointer { _ = write(fd, $0.baseAddress, $0.count) }
    }
}
