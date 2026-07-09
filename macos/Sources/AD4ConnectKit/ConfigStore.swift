import Foundation

/// Reads and writes the same INI file as the `ad4ctl` CLI
/// (`~/.config/ad4connect/config.ini`, `[connection]` section), so connection
/// defaults are shared between the command line and the app.
public enum ConfigStore {
    public static let appName = "ad4connect"
    public static let section = "connection"
    public static let keys = ["host", "port", "timeout"]

    public static func configPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["AD4CONNECT_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: (xdg as NSString).expandingTildeInPath)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return base.appendingPathComponent(appName).appendingPathComponent("config.ini")
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let path = configPath(environment: environment)
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [:] }

        var values: [String: String] = [:]
        var inSection = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inSection = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces) == section
                continue
            }
            guard inSection, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if keys.contains(key) {
                values[key] = value
            }
        }
        return values
    }

    /// Merge `updates` into the stored `[connection]` values and write the file.
    /// Written in the same `key = value` shape Python's configparser emits.
    public static func save(
        _ updates: [String: String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        var merged = load(environment: environment)
        for (key, value) in updates where keys.contains(key) {
            merged[key] = value
        }

        var lines = ["[\(section)]"]
        for key in keys {
            if let value = merged[key] {
                lines.append("\(key) = \(value)")
            }
        }
        let contents = lines.joined(separator: "\n") + "\n"

        let path = configPath(environment: environment)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: path, atomically: true, encoding: .utf8)
    }
}
