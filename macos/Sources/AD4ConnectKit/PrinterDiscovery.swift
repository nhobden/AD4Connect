import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A printer found on the local network via UDP discovery.
public struct DiscoveredPrinter: Identifiable, Hashable, Sendable {
    public let name: String
    public let ip: String
    public let port: Int
    public var id: String { "\(ip):\(port)" }

    public init(name: String, ip: String, port: Int) {
        self.name = name
        self.ip = ip
        self.port = port
    }
}

/// FlashForge UDP discovery. Probes the known multicast/broadcast endpoints and
/// collects replies. Legacy Adventurer 3/4 answer on multicast `225.0.0.9:8899`;
/// newer models use `225.0.0.9:19000` / broadcast `255.255.255.255:48899`.
public enum PrinterDiscovery {
    private static let targets: [(host: String, port: UInt16)] = [
        ("225.0.0.9", 8899),        // legacy Adventurer 3/4
        ("225.0.0.9", 19000),       // modern multicast
        ("255.255.255.255", 48899), // modern broadcast
    ]

    /// Blocking. Call off the main thread. Returns unique printers keyed by IP.
    public static func discover(timeout: TimeInterval = 3.0, defaultPort: Int = 8899) -> [DiscoveredPrinter] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { Darwin.close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var ttl: UInt8 = 1
        setsockopt(fd, Int32(IPPROTO_IP), IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        // Short recv timeout so the loop can keep re-checking the overall deadline.
        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let payload = Array("discover".utf8) // ignored by the printer
        for target in targets {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = target.port.bigEndian
            inet_pton(AF_INET, target.host, &addr.sin_addr)
            _ = payload.withUnsafeBytes { raw in
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, raw.baseAddress, payload.count, 0, sa,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var found: [String: DiscoveredPrinter] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            var src = sockaddr_in()
            var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &src) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, raw.baseAddress, raw.count, 0, sa, &srcLen)
                    }
                }
            }
            // Ignore timeouts (n < 0) and any echo of our small probe (n < 32).
            guard n >= 32 else { continue }

            let data = Data(buffer[0..<n])
            var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &src.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: ipBuffer)
            let name = parseName(from: data) ?? ip
            let port = data.count >= 196 ? (parsePort(from: data) ?? defaultPort) : defaultPort
            found[ip] = DiscoveredPrinter(name: name, ip: ip, port: port)
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Printer name: offset 0x00, up to 128 bytes, null-terminated.
    public static func parseName(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let bytes = Array(data.prefix(128))
        let end = bytes.firstIndex(of: 0) ?? bytes.count
        let name = String(decoding: bytes[0..<end], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Command port: offset 0x84, uint16 big endian (modern packets only).
    public static func parsePort(from data: Data) -> Int? {
        let offset = 0x84
        guard data.count >= offset + 2 else { return nil }
        let hi = Int(data[data.startIndex + offset])
        let lo = Int(data[data.startIndex + offset + 1])
        let port = (hi << 8) | lo
        return (1...65535).contains(port) ? port : nil
    }
}
