import Foundation
import SwiftUI
import AD4ConnectKit

/// Drives the UI. Network calls run on a background queue; published state is
/// only ever mutated back on the main queue.
@MainActor
final class PrinterViewModel: ObservableObject {
    // Connection
    @Published var host: String = ""
    @Published var port: String = "8899"
    @Published var timeout: String = "8"

    // Live state
    @Published var status: PrinterStatus?
    @Published var files: [String] = []
    @Published var selectedFile: String?
    @Published var log: [String] = []
    @Published var isBusy: Bool = false
    @Published var autoRefresh: Bool = false
    @Published var uploadProgress: Double?
    @Published var force: Bool = false

    // Discovery
    @Published var isDiscovering: Bool = false
    @Published var discovered: [DiscoveredPrinter] = []

    private let queue = DispatchQueue(label: "com.ad4connect.io")
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 5

    init() {
        let stored = ConfigStore.load()
        host = stored["host"] ?? ""
        port = stored["port"] ?? "8899"
        timeout = stored["timeout"] ?? "8"
    }

    var isConnectable: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && Int(port) != nil
    }

    private func makeClient() -> FlashForgeClient? {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty, let portValue = Int(port) else {
            appendLog("Enter a host and a numeric port first.")
            return nil
        }
        let timeoutValue = Double(timeout) ?? 8.0
        return FlashForgeClient(host: trimmedHost, port: portValue, timeout: timeoutValue)
    }

    // MARK: - Config

    func saveConnection() {
        do {
            try ConfigStore.save([
                "host": host.trimmingCharacters(in: .whitespaces),
                "port": port,
                "timeout": timeout,
            ])
            appendLog("Saved connection defaults to \(ConfigStore.configPath().path)")
        } catch {
            appendLog("Could not save config: \(error.localizedDescription)")
        }
    }

    // MARK: - Discovery

    func discover() {
        guard !isDiscovering else { return }
        isDiscovering = true
        discovered = []
        appendLog("Scanning local network for printers…")
        queue.async {
            let results = PrinterDiscovery.discover(timeout: 3.0)
            DispatchQueue.main.async {
                self.discovered = results
                self.isDiscovering = false
                self.appendLog("Discovery found \(results.count) printer(s).")
            }
        }
    }

    func selectDiscovered(_ printer: DiscoveredPrinter) {
        host = printer.ip
        port = String(printer.port)
        appendLog("Selected \(printer.name) at \(printer.ip):\(printer.port)")
        refreshStatus()
        refreshFiles()
    }

    // MARK: - Commands

    func refreshStatus() {
        perform("Refreshing status", work: { try $0.status() }) { [weak self] in
            self?.status = $0
        }
    }

    func refreshFiles() {
        perform("Listing files", work: { try $0.files() }) { [weak self] files in
            self?.files = files
            if let selected = self?.selectedFile, !files.contains(selected) {
                self?.selectedFile = nil
            }
        }
    }

    func printSelected() {
        guard let remote = selectedFile else { appendLog("Select a file to print."); return }
        guardPrintingThen("Printing \(remote)") { [weak self] in
            self?.perform("Printing \(remote)", work: { try $0.printFile(remote) }) { result in
                self?.appendLog(result.trimmingCharacters(in: .whitespacesAndNewlines))
                self?.refreshStatus()
            }
        }
    }

    func pause() { simple("Pausing") { try $0.pause() } }
    func resume() { simple("Resuming") { try $0.resume() } }
    func cancel() { simple("Cancelling") { try $0.cancel() } }

    func upload(fileURL: URL, start: Bool) {
        guardPrintingThen("Uploading \(fileURL.lastPathComponent)") { [weak self] in
            guard let self, let client = self.makeClient() else { return }
            self.isBusy = true
            self.uploadProgress = 0
            self.appendLog("Uploading \(fileURL.lastPathComponent)…")
            self.queue.async {
                do {
                    let remote = try client.upload(localFile: fileURL) { sent, total in
                        let ratio = total > 0 ? Double(sent) / Double(total) : 0
                        DispatchQueue.main.async { self.uploadProgress = ratio }
                    }
                    var startResult: String?
                    if start { startResult = try client.printFile(remote) }
                    DispatchQueue.main.async {
                        self.uploadProgress = nil
                        self.isBusy = false
                        self.appendLog("Uploaded \(remote)")
                        if let startResult {
                            self.appendLog(startResult.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        self.refreshFiles()
                        self.refreshStatus()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.uploadProgress = nil
                        self.isBusy = false
                        self.appendLog("Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Auto refresh

    func setAutoRefresh(_ enabled: Bool) {
        autoRefresh = enabled
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard enabled else { return }
        refreshStatus()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    // MARK: - Helpers

    /// If the printer is currently printing and Force is off, warn instead of acting.
    private func guardPrintingThen(_ label: String, _ action: @escaping () -> Void) {
        if let status, status.isPrinting, !force {
            appendLog("Printer appears to be printing. Enable Force to \(label.lowercased()) anyway.")
            return
        }
        action()
    }

    private func simple(_ label: String, _ work: @escaping (FlashForgeClient) throws -> String) {
        perform(label, work: work) { [weak self] result in
            self?.appendLog(result.trimmingCharacters(in: .whitespacesAndNewlines))
            self?.refreshStatus()
        }
    }

    private func perform<T>(
        _ label: String,
        work: @escaping (FlashForgeClient) throws -> T,
        completion: @escaping (T) -> Void
    ) {
        guard let client = makeClient() else { return }
        isBusy = true
        appendLog("\(label)…")
        queue.async {
            do {
                let result = try work(client)
                DispatchQueue.main.async {
                    completion(result)
                    self.isBusy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.appendLog("Error: \(error.localizedDescription)")
                    self.isBusy = false
                }
            }
        }
    }

    private func appendLog(_ message: String) {
        let stamp = Self.timeFormatter.string(from: Date())
        log.append("[\(stamp)] \(message)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
