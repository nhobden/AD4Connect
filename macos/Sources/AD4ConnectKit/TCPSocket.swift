import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum SocketError: Error, LocalizedError {
    case resolveFailed(String)
    case connectFailed(String)
    case connectTimeout
    case sendFailed(String)

    public var errorDescription: String? {
        switch self {
        case .resolveFailed(let msg): return "Could not resolve host: \(msg)"
        case .connectFailed(let msg): return "Connection failed: \(msg)"
        case .connectTimeout: return "Connection timed out"
        case .sendFailed(let msg): return "Send failed: \(msg)"
        }
    }
}

/// Minimal blocking TCP socket. Mirrors the behaviour of `ad4core.client`'s
/// socket usage: a fresh connection per command, read until we see `ok`.
final class TCPSocket {
    private let fd: Int32
    private let timeout: TimeInterval

    private init(fd: Int32, timeout: TimeInterval) {
        self.fd = fd
        self.timeout = timeout
    }

    static func connect(host: String, port: Int, timeout: TimeInterval) throws -> TCPSocket {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var info: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &info)
        guard status == 0, let head = info else {
            throw SocketError.resolveFailed(String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(info) }

        var lastError = "no usable address"
        var candidate: UnsafeMutablePointer<addrinfo>? = head
        while let addr = candidate {
            defer { candidate = addr.pointee.ai_next }
            let fd = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
            if fd < 0 { lastError = String(cString: strerror(errno)); continue }

            // Non-blocking connect so we can enforce a bounded connect timeout.
            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

            let result = Darwin.connect(fd, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
            if result == 0 {
                _ = fcntl(fd, F_SETFL, flags)
                let sock = TCPSocket(fd: fd, timeout: timeout)
                sock.applyTimeouts()
                return sock
            }
            if errno == EINPROGRESS {
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let ms = Int32(max(1, timeout * 1000))
                let polled = poll(&pfd, 1, ms)
                if polled > 0 {
                    var soError: Int32 = 0
                    var len = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
                    if soError == 0 {
                        _ = fcntl(fd, F_SETFL, flags)
                        let sock = TCPSocket(fd: fd, timeout: timeout)
                        sock.applyTimeouts()
                        return sock
                    }
                    lastError = String(cString: strerror(soError))
                } else if polled == 0 {
                    Darwin.close(fd)
                    throw SocketError.connectTimeout
                } else {
                    lastError = String(cString: strerror(errno))
                }
            } else {
                lastError = String(cString: strerror(errno))
            }
            Darwin.close(fd)
        }
        throw SocketError.connectFailed(lastError)
    }

    /// Apply the receive/send timeout so a silent printer can't block forever.
    private func applyTimeouts() {
        var tv = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    func setReceiveTimeout(_ seconds: TimeInterval) {
        var tv = timeval(
            tv_sec: Int(seconds),
            tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    func sendCommand(_ gcode: String) throws {
        try sendAll(Array("~\(gcode)\r\n".utf8))
    }

    func sendAll(_ bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.send(fd, base + offset, bytes.count - offset, 0)
                if n > 0 {
                    offset += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    throw SocketError.sendFailed(String(cString: strerror(errno)))
                }
            }
        }
    }

    /// Read until the printer's `ok` sentinel appears or `timeout` elapses.
    func readResponse(timeout: TimeInterval) -> String {
        setReceiveTimeout(timeout)
        var data = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 8192)
        while Date() < deadline {
            let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 8192, 0) }
            if n > 0 {
                data.append(contentsOf: buffer[0..<n])
                let text = String(decoding: data, as: UTF8.self)
                if text.contains("\nok")
                    || text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("ok") {
                    break
                }
            } else {
                break // closed, timed out (EAGAIN/EWOULDBLOCK), or error
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Read whatever is immediately available, stopping early once `ok` is seen.
    @discardableResult
    func readAvailable(timeout: TimeInterval) -> String {
        setReceiveTimeout(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 8192, 0) }
            if n > 0 {
                data.append(contentsOf: buffer[0..<n])
                if data.range(of: Data("ok".utf8)) != nil { break }
            } else {
                break
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    func close() {
        Darwin.close(fd)
    }
}
