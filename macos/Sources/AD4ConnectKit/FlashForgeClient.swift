import Foundation

/// Swift port of `ad4core.FlashForgeClient`. All methods are blocking and
/// throwing; call them off the main thread (see `PrinterViewModel`).
public struct FlashForgeClient: Sendable {
    public let host: String
    public let port: Int
    public let timeout: TimeInterval

    public init(host: String, port: Int = 8899, timeout: TimeInterval = 8.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    public func command(_ gcode: String, readTimeout: TimeInterval? = nil) throws -> String {
        let effective = readTimeout ?? timeout
        let socket = try TCPSocket.connect(host: host, port: port, timeout: effective)
        defer { socket.close() }
        try socket.sendCommand(gcode)
        return socket.readResponse(timeout: effective)
    }

    public func status() throws -> PrinterStatus {
        let m119 = try command("M119")
        let m105 = try command("M105")
        let m27 = try command("M27")
        return StatusParser.parseStatus(m119, m105, m27)
    }

    public func filesRaw() throws -> String {
        try command("M661", readTimeout: 12.0)
    }

    public func files() throws -> [String] {
        StatusParser.parseFileList(try filesRaw())
    }

    /// Upload a local file. `progress` is called from this (background) thread
    /// with (bytesSent, totalBytes).
    @discardableResult
    public func upload(
        localFile: URL,
        remoteName: String? = nil,
        chunkSize: Int = 4096,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: localFile.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let remote = remoteName ?? localFile.lastPathComponent
        let remotePath = remote.hasPrefix("/data/") ? remote : "/data/\(remote)"

        let handle = try FileHandle(forReadingFrom: localFile)
        defer { try? handle.close() }

        let attributes = try fm.attributesOfItem(atPath: localFile.path)
        let total = (attributes[.size] as? Int) ?? 0
        var sent = 0

        let socket = try TCPSocket.connect(host: host, port: port, timeout: max(timeout, 30.0))
        defer { socket.close() }

        try socket.sendCommand("M28 \(remotePath)")
        // Some printers reply before data, some stay quiet until M29. Read briefly only.
        socket.readAvailable(timeout: 0.5)

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            try socket.sendAll([UInt8](chunk))
            sent += chunk.count
            progress?(sent, total)
        }

        try socket.sendCommand("M29")
        _ = socket.readResponse(timeout: 20.0)
        return remotePath
    }

    @discardableResult
    public func printFile(_ remoteName: String) throws -> String {
        let remotePath = remoteName.hasPrefix("/data/") ? remoteName : "/data/\(remoteName)"
        // Proven on the AD4: select the SD file, then start/resume the SD print.
        let select = try command("M23 \(remotePath)")
        let start = try command("M24")
        return select + "\n" + start
    }

    @discardableResult public func pause() throws -> String { try command("M25") }
    @discardableResult public func resume() throws -> String { try command("M24") }
    @discardableResult public func cancel() throws -> String { try command("M26") }
}
