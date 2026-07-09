import SwiftUI
import AppKit
import AD4ConnectKit

struct ContentView: View {
    @EnvironmentObject var vm: PrinterViewModel

    var body: some View {
        VStack(spacing: 0) {
            connectionBar
            Divider()
            HStack(spacing: 0) {
                statusPanel
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                filesPanel
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            logConsole
        }
    }

    // MARK: - Connection bar

    private var connectionBar: some View {
        HStack(spacing: 10) {
            LabeledField(label: "Host", text: $vm.host, width: 150,
                         placeholder: "192.168.1.50")
            LabeledField(label: "Port", text: $vm.port, width: 64)
            LabeledField(label: "Timeout", text: $vm.timeout, width: 56)

            Button("Save") { vm.saveConnection() }
                .help("Store these as defaults (shared with the ad4ctl CLI)")

            Divider().frame(height: 20)

            Button {
                vm.refreshStatus()
                vm.refreshFiles()
            } label: {
                Label("Connect", systemImage: "arrow.triangle.2.circlepath")
            }
            .keyboardShortcut("r")
            .disabled(!vm.isConnectable || vm.isBusy)

            Toggle("Auto", isOn: Binding(
                get: { vm.autoRefresh },
                set: { vm.setAutoRefresh($0) }))
                .toggleStyle(.switch)
                .help("Refresh status every 5 seconds")

            Spacer()

            if vm.isBusy { ProgressView().scaleEffect(0.6).frame(width: 20, height: 20) }
        }
        .padding(10)
    }

    // MARK: - Status panel

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status").font(.headline)

            if let status = vm.status {
                StatusRow(label: "Machine", value: status.machineStatus ?? "—")
                StatusRow(label: "Move", value: status.moveMode ?? "—")
                StatusRow(label: "File", value: status.currentFile ?? "—")

                if let nozzle = status.nozzleCurrent {
                    StatusRow(label: "Nozzle",
                              value: "\(nozzle) / \(status.nozzleTarget ?? 0) °C")
                }
                if let bed = status.bedCurrent {
                    StatusRow(label: "Bed",
                              value: "\(bed) / \(status.bedTarget ?? 0) °C")
                }
                if let layer = status.layerCurrent {
                    StatusRow(label: "Layer",
                              value: "\(layer) / \(status.layerTotal ?? 0)")
                }

                if let percent = status.progressPercent {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Progress \(percent, specifier: "%.1f")%")
                            .font(.subheadline)
                        ProgressView(value: percent, total: 100)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("Not connected. Enter a host and press Connect.")
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 4)

            Text("Controls").font(.headline)
            HStack {
                Button("Pause") { vm.pause() }
                Button("Resume") { vm.resume() }
                Button("Cancel", role: .destructive) { vm.cancel() }
            }
            .disabled(vm.status == nil || vm.isBusy)

            Toggle("Force (act even while printing)", isOn: $vm.force)
                .font(.caption)

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Files panel

    private var filesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Files on printer").font(.headline)
                Spacer()
                Button {
                    vm.refreshFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!vm.isConnectable || vm.isBusy)
                .help("Refresh file list")
            }

            List(vm.files, id: \.self, selection: $vm.selectedFile) { file in
                Text(file).font(.system(.body, design: .monospaced))
                    .tag(file)
            }
            .frame(minHeight: 160)
            .border(Color.secondary.opacity(0.2))

            HStack {
                Button("Print Selected") { vm.printSelected() }
                    .disabled(vm.selectedFile == nil || vm.isBusy)
                Spacer()
            }

            Divider().padding(.vertical, 2)

            HStack {
                Button {
                    chooseAndUpload(start: false)
                } label: {
                    Label("Upload…", systemImage: "square.and.arrow.up")
                }
                Button {
                    chooseAndUpload(start: true)
                } label: {
                    Label("Upload & Print…", systemImage: "printer")
                }
                Spacer()
            }
            .disabled(!vm.isConnectable || vm.isBusy)

            if let progress = vm.uploadProgress {
                ProgressView(value: progress) {
                    Text("Uploading \(progress * 100, specifier: "%.0f")%").font(.caption)
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Log console

    private var logConsole: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vm.log.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .frame(height: 130)
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: vm.log.count) { _ in
                if let last = vm.log.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - File picker

    private func chooseAndUpload(start: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        panel.message = "Choose a G-code or GX file to upload"
        if panel.runModal() == .OK, let url = panel.url {
            vm.upload(fileURL: url, start: start)
        }
    }
}

// MARK: - Small subviews

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var width: CGFloat
    var placeholder: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }
}

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }
}
