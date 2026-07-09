# AD4Connect

AD4Connect is an open-source replacement tooling project for legacy FlashForge printers that are no longer well supported by current FlashForge desktop software on modern macOS.

The first target is the **FlashForge Adventurer 4**, confirmed working against firmware `v2.3.3-3.33` on TCP port `8899`.

## Current status

Working today:

- Printer status
- Temperature readout
- Print progress readout
- File listing
- Upload G-code/GX files
- Start prints remotely
- Pause/resume/cancel commands
- Live `watch` mode

Planned:

- Native macOS SwiftUI app
- OrcaSlicer integration
- Webcam view if exposed by firmware
- Printer discovery
- Safer upload verification
- Support for related FlashForge models

## Install for development

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e .
```

## macOS app

A native SwiftUI app lives in [`macos/`](macos/). It reimplements the printer
protocol in Swift (no Python runtime needed) and shares the CLI's stored config.
Build it with `cd macos && ./build_app.sh`, or open `macos/Package.swift` in Xcode.

## Configuration

Rather than passing `--host` on every command, store connection defaults once:

```bash
ad4ctl config set --host 192.168.68.119
ad4ctl config set --host 192.168.68.119 --port 8899 --timeout 8
```

Then commands can be run without flags:

```bash
ad4ctl status
ad4ctl files
```

A flag always overrides the stored value, so you can point at a different printer
temporarily:

```bash
ad4ctl --host 192.168.68.200 status
```

Inspect or clear the stored config:

```bash
ad4ctl config show
ad4ctl config path
ad4ctl config unset port
```

The config lives at `~/.config/ad4connect/config.ini` (respecting `XDG_CONFIG_HOME`).
Set `AD4CONNECT_CONFIG` to point at a different file.

## Usage

```bash
ad4ctl --host 192.168.68.119 status
ad4ctl --host 192.168.68.119 files
ad4ctl --host 192.168.68.119 watch
```

Upload only:

```bash
ad4ctl --host 192.168.68.119 upload ~/Downloads/model.gcode --remote-name model.gcode
```

Upload and start:

```bash
ad4ctl --host 192.168.68.119 upload ~/Downloads/model.gcode --remote-name model.gcode --start
```

Print an existing printer-side file:

```bash
ad4ctl --host 192.168.68.119 print model.gcode
```

Pause/resume/cancel:

```bash
ad4ctl --host 192.168.68.119 pause
ad4ctl --host 192.168.68.119 resume
ad4ctl --host 192.168.68.119 cancel
```

## Protocol notes

The Adventurer 4 exposes a legacy FlashForge TCP service on port `8899`. Commands are sent as:

```text
~M119\r\n
```

Useful commands confirmed:

| Command | Purpose |
| --- | --- |
| `M119` | Printer state / current file |
| `M105` | Temperature state |
| `M27` | Print progress |
| `M661` | File listing |
| `M28 /data/file.gcode` | Begin file upload |
| `M29` | Finish file upload |
| `M23 /data/file.gcode` | Select file |
| `M24` | Start/resume print |
| `M25` | Pause print |
| `M26` | Cancel/reset SD print state |

## Safety

This is early alpha software. Watch the printer when starting prints remotely. Use at your own risk.
