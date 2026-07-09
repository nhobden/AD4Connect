import Foundation

/// Builds the MJPEG stream / snapshot URLs for a FlashForge camera.
/// The Adventurer 4 exposes an mjpg-streamer service on port 8080.
public enum CameraStream {
    public static let defaultPort = 8080
    public static let defaultPath = "/?action=stream"

    public static func streamURL(host: String, port: Int = defaultPort, path: String = defaultPath) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: "http://\(trimmed):\(port)\(normalizedPath)")
    }
}
