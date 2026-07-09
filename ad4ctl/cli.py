from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from ad4core import FlashForgeClient


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ad4ctl")
    parser.add_argument("--host", required=True, help="Printer IP address or hostname")
    parser.add_argument("--port", type=int, default=8899, help="Printer TCP port, default 8899")
    parser.add_argument("--timeout", type=float, default=8.0)

    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("files")
    sub.add_parser("files-raw")

    watch = sub.add_parser("watch")
    watch.add_argument("--interval", type=float, default=5.0)

    upload = sub.add_parser("upload")
    upload.add_argument("file")
    upload.add_argument("--remote-name")
    upload.add_argument("--start", action="store_true")
    upload.add_argument("--force", action="store_true", help="Allow upload while printer reports printing")

    print_cmd = sub.add_parser("print")
    print_cmd.add_argument("remote_name")
    print_cmd.add_argument("--force", action="store_true", help="Allow print command while printer reports printing")

    sub.add_parser("pause")
    sub.add_parser("resume")
    sub.add_parser("cancel")

    args = parser.parse_args(argv)
    client = FlashForgeClient(args.host, args.port, timeout=args.timeout)

    try:
        if args.command == "status":
            _print_status(client.status())
        elif args.command == "watch":
            _watch(client, args.interval)
        elif args.command == "files":
            for file in client.files():
                print(file)
        elif args.command == "files-raw":
            print(client.files_raw())
        elif args.command == "upload":
            status = client.status()
            if status.is_printing and not args.force:
                print(
                    "Printer appears to be printing. Use --force to upload anyway.",
                    file=sys.stderr,
                )
                return 2
            remote = client.upload(args.file, args.remote_name, progress=_progress)
            print(f"\nUploaded: {remote}")
            if args.start:
                print(client.print_file(remote))
        elif args.command == "print":
            status = client.status()
            if status.is_printing and not args.force:
                print(
                    "Printer appears to be printing. Use --force to start another job anyway.",
                    file=sys.stderr,
                )
                return 2
            print(client.print_file(args.remote_name))
        elif args.command == "pause":
            print(client.pause())
        elif args.command == "resume":
            print(client.resume())
        elif args.command == "cancel":
            print(client.cancel())
    except KeyboardInterrupt:
        return 130
    except Exception as exc:  # noqa: BLE001 - CLI should show clear errors
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


def _print_status(status) -> None:
    print("AD4Connect status")
    print(f"Machine: {status.machine_status or '-'}")
    print(f"Move:    {status.move_mode or '-'}")
    print(f"File:    {status.current_file or '-'}")
    if status.nozzle_current is not None:
        print(f"Nozzle:  {status.nozzle_current}/{status.nozzle_target} °C")
    if status.bed_current is not None:
        print(f"Bed:     {status.bed_current}/{status.bed_target} °C")
    if status.sd_current is not None:
        pct = status.progress_percent
        pct_text = f" ({pct:.1f}%)" if pct is not None else ""
        print(f"Bytes:   {status.sd_current}/{status.sd_total}{pct_text}")
    if status.layer_current is not None:
        print(f"Layer:   {status.layer_current}/{status.layer_total}")


def _watch(client: FlashForgeClient, interval: float) -> None:
    while True:
        print("\033[2J\033[H", end="")
        _print_status(client.status())
        print("\nCtrl+C to stop watching.")
        time.sleep(interval)


def _progress(done: int, total: int) -> None:
    width = 30
    ratio = done / total if total else 0
    filled = int(width * ratio)
    bar = "#" * filled + "-" * (width - filled)
    print(f"\rUploading [{bar}] {ratio * 100:5.1f}%", end="", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
