import SwiftUI
import WebKit
import AD4ConnectKit

/// Renders the printer's MJPEG stream. WKWebView handles the
/// `multipart/x-mixed-replace` stream natively (as a browser would).
struct CameraWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
    }
}

/// Camera panel: settings (port/path) plus the live view, shown as a sheet.
struct CameraPanel: View {
    let host: String
    @Environment(\.dismiss) private var dismiss

    @AppStorage("cameraPort") private var cameraPort: Int = CameraStream.defaultPort
    @AppStorage("cameraPath") private var cameraPath: String = CameraStream.defaultPath
    @State private var reloadToken = 0

    private var streamURL: URL? {
        CameraStream.streamURL(host: host, port: cameraPort, path: cameraPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Camera").font(.headline)
                Spacer()
                Text("Port").foregroundStyle(.secondary)
                TextField("8080", value: $cameraPort, format: .number.grouping(.never))
                    .frame(width: 64).textFieldStyle(.roundedBorder)
                Text("Path").foregroundStyle(.secondary)
                TextField("/?action=stream", text: $cameraPath)
                    .frame(width: 160).textFieldStyle(.roundedBorder)
                Button("Reload") { reloadToken += 1 }
                if let url = streamURL {
                    Button("Open in Browser") { NSWorkspace.shared.open(url) }
                }
            }
            .padding(10)
            Divider()

            Group {
                if let url = streamURL {
                    CameraWebView(url: url)
                        .id("\(url.absoluteString)#\(reloadToken)")
                } else {
                    ContentUnavailableViewCompat(
                        title: "No host",
                        message: "Connect to a printer first.")
                }
            }
            .frame(minWidth: 640, minHeight: 480)

            Divider()
            HStack {
                if let url = streamURL {
                    Text(url.absoluteString)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(minWidth: 680, minHeight: 560)
    }
}

/// Tiny fallback so we don't depend on macOS 14's ContentUnavailableView.
private struct ContentUnavailableViewCompat: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
