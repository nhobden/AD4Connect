import Foundation

/// Port of `ad4core.parser`: turns raw printer responses into structured values.
public enum StatusParser {
    private static let tempRE = try! NSRegularExpression(
        pattern: #"T0:(-?\d+)/(\d+)\s+B:(-?\d+)/(\d+)"#)
    private static let sdRE = try! NSRegularExpression(
        pattern: #"SD printing byte\s+(\d+)/(\d+)"#)
    private static let layerRE = try! NSRegularExpression(
        pattern: #"Layer:\s*(\d+)/(\d+)"#)

    public static func parseStatus(_ responses: String?...) -> PrinterStatus {
        let raw = responses.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")

        var status = PrinterStatus(raw: raw)
        status.machineStatus = valueAfter(raw, prefix: "MachineStatus:")
        status.moveMode = valueAfter(raw, prefix: "MoveMode:")
        status.currentFile = valueAfter(raw, prefix: "CurrentFile:")

        if let groups = firstMatch(tempRE, in: raw), groups.count == 4 {
            status.nozzleCurrent = Int(groups[0])
            status.nozzleTarget = Int(groups[1])
            status.bedCurrent = Int(groups[2])
            status.bedTarget = Int(groups[3])
        }
        if let groups = firstMatch(sdRE, in: raw), groups.count == 2 {
            status.sdCurrent = Int(groups[0])
            status.sdTotal = Int(groups[1])
        }
        if let groups = firstMatch(layerRE, in: raw), groups.count == 2 {
            status.layerCurrent = Int(groups[0])
            status.layerTotal = Int(groups[1])
        }
        return status
    }

    public static func parseFileList(_ response: String) -> [String] {
        // The printer wraps `/data/file.ext` entries in binary-ish separators.
        let re = try! NSRegularExpression(pattern: #"/data/[^:\x00\r\n]+"#)
        let ns = response as NSString
        let matches = re.matches(in: response, range: NSRange(location: 0, length: ns.length))
        var cleaned: [String] = []
        for match in matches {
            let name = ns.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !cleaned.contains(name) {
                cleaned.append(name)
            }
        }
        return cleaned
    }

    // MARK: - Helpers

    private static func valueAfter(_ text: String, prefix: String) -> String? {
        // Split on any newline. NB: printer responses use CRLF, and Swift treats
        // "\r\n" as a SINGLE Character, so split(separator: "\n") would not match.
        // Character.isNewline correctly recognises the CRLF grapheme cluster.
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(prefix) {
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Returns the capture groups (excluding group 0) of the first match, or nil.
    private static func firstMatch(_ re: NSRegularExpression, in text: String) -> [String]? {
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        return groups
    }
}
