# Roadmap

## v0.2 CLI foundation

- [x] Stable installable CLI
- [x] Status
- [x] Files
- [x] Upload
- [x] Print
- [x] Pause/resume/cancel
- [x] Watch mode
- [x] Safer printing checks

## v0.3 Protocol hardening

- [ ] Better parser for binary-ish file list response
- [ ] Delete file command discovery
- [ ] Firmware/version info
- [ ] Printer capability detection
- [ ] Upload verification
- [ ] Integration test harness using captured printer responses

## v0.4 Orca integration

- [ ] Document OrcaSlicer post-processing setup
- [ ] Export helper with config file
- [ ] Optional automatic upload/start
- [ ] Safe prompt mode before start

## v1.0 macOS app

See `macos/` for the native SwiftUI app (protocol ported to Swift in `AD4ConnectKit`).

- [x] SwiftUI app shell
- [x] Status panel
- [x] File browser
- [x] Upload (file picker; drag/drop still to do)
- [x] Start/pause/resume/cancel
- [x] Preference storage (shares `~/.config/ad4connect/config.ini` with the CLI)
- [x] Packaged `.app` (via `macos/build_app.sh`; Xcode Archive for signed builds)
- [ ] Drag/drop upload
- [ ] App icon
- [ ] Code signing / notarization
