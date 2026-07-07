import Darwin

public enum UnixSocket {
    public static func canConnect(to path: String) -> Bool {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathCString = path.utf8CString
        guard pathCString.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            return false
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            sunPath.withMemoryRebound(to: CChar.self, capacity: pathCString.count) { dest in
                for (index, byte) in pathCString.enumerated() {
                    dest[index] = byte
                }
            }
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, addrSize) == 0
            }
        }
    }
}
