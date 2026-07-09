# AD4Connect (macOS app)

A native SwiftUI app for controlling legacy FlashForge printers, built on a Swift
port of the `ad4core` protocol. No Python runtime required — the printer protocol
is reimplemented in `AD4ConnectKit`.

## Layout

```
Sources/
  AD4ConnectKit/      Protocol + config library (no UI, unit-testable)
    PrinterStatus.swift    Parsed status model
    StatusParser.swift     Port of ad4core.parser (regex parsing)
    TCPSocket.swift        Blocking BSD-socket wrapper w/ bounded connect timeout
    FlashForgeClient.swift Port of ad4core.FlashForgeClient (M119/M105/M27, upload, print…)
    ConfigStore.swift      Reads/writes the SAME ~/.config/ad4connect/config.ini as ad4ctl
  AD4Connect/         SwiftUI app
    AD4ConnectApp.swift    @main entry point
    PrinterViewModel.swift Background I/O + published UI state
    ContentView.swift      Full window: status, controls, file list, upload, log
Tests/                XCTest suite for the Kit (run in Xcode)
```

## Features (v0.1)

- Connect by host/port (prefilled from the CLI's stored config)
- Live status: machine state, nozzle/bed temps, layer, progress bar
- Auto-refresh (5s)
- File list from the printer
- Upload a file, or upload & start printing (with a file picker)
- Print selected / pause / resume / cancel
- "Force" toggle to act while the printer reports it is printing
- Activity log

Connection defaults are shared with the `ad4ctl` CLI — set `--host` once in either
place (`ad4ctl config set --host …` or the app's **Save** button) and both use it.

## Build & run

Requires the Swift toolchain (Command Line Tools are enough).

```bash
# Run the library tests (needs Xcode's XCTest; run from Xcode if CLT-only)
swift test

# Build and launch the app bundle (works with Command Line Tools alone)
./build_app.sh
open build/AD4Connect.app
```

## Distributable build

For a signed / notarized `.app`, open `Package.swift` in **Xcode**
(`xed .` or File ▸ Open), select the `AD4Connect` scheme, then **Product ▸ Archive**.
