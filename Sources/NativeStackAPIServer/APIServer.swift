import Foundation
import Darwin

public final class APIServer: @unchecked Sendable {
    private let port: UInt16
    private let router: APIRouter
    private var listenFD: Int32 = -1
    private var isRunning = false

    @MainActor
    public init(router: APIRouter, port: UInt16 = 7842) {
        self.router = router
        self.port = port
    }

    @MainActor
    public func start() throws {
        guard !isRunning else { return }

        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw APIServerError.socketFailed
        }

        var reuse: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(listenFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(listenFD)
            throw APIServerError.bindFailed(port: port)
        }

        guard listen(listenFD, 128) == 0 else {
            close(listenFD)
            throw APIServerError.listenFailed
        }

        isRunning = true
        fputs("NativeStack API listening on http://127.0.0.1:\(port)\n", stderr)

        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.acceptLoop()
        }
    }

    public func stop() {
        isRunning = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
    }

    private func acceptLoop() async {
        while isRunning {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else { continue }
            Task.detached(priority: .utility) { [weak self] in
                await self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ clientFD: Int32) async {
        defer { close(clientFD) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while data.count < 1_048_576 {
            let bytesRead = read(clientFD, &buffer, buffer.count)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
            if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }

        guard let request = HTTPParser.parse(data) else {
            write(clientFD, "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n", 52)
            return
        }

        if request.method == "GET",
           request.path.hasPrefix("/api/containers/"),
           request.path.hasSuffix("/logs/stream") {
            let prefix = request.path.dropFirst("/api/containers/".count)
            let id = String(prefix.dropLast("/logs/stream".count))
            await streamLogs(id: id, clientFD: clientFD)
            return
        }

        let response = await router.handle(request)
        let serialized = response.serialize()
        _ = serialized.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return 0 }
            return write(clientFD, base, serialized.count)
        }
    }

    private func streamLogs(id: String, clientFD: Int32) async {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: *",
            "",
            "",
        ].joined(separator: "\r\n")
        guard writeAll(clientFD, Data(headers.utf8)) else { return }

        for await line in await router.logStream(forContainer: id) {
            let escaped = line.text.replacingOccurrences(of: "\n", with: "\\n")
            guard writeAll(clientFD, Data("data: \(escaped)\n\n".utf8)) else { return }
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return true }
            return write(fd, base, data.count) == data.count
        }
    }
}

public enum APIServerError: LocalizedError {
    case socketFailed
    case bindFailed(port: UInt16)
    case listenFailed

    public var errorDescription: String? {
        switch self {
        case .socketFailed:
            "Failed to create API server socket."
        case let .bindFailed(port):
            "Port \(port) is already in use."
        case .listenFailed:
            "Failed to listen for API connections."
        }
    }
}
