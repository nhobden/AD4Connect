from __future__ import annotations

import argparse
import sys
import time

from ad4core import FlashForgeClient
from ad4ctl import config as config_store

DEFAULT_PORT = 8899
DEFAULT_TIMEOUT = 8.0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ad4ctl")
    # Defaults are None so we can tell an explicit flag apart from "fall back to
    # the stored config". Resolution happens after parsing in _resolve_connection.
    parser.add_argument("--host", help="Printer IP address or hostname (or store it with 'ad4ctl config set')")
    parser.add_argument("--port", type=int, help=f"Printer TCP port, default {DEFAULT_PORT}")
    parser.add_argument("--timeout", type=float, help=f"Socket timeout in seconds, default {DEFAULT_TIMEOUT}")

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

    config_cmd = sub.add_parser("config", help="View or edit stored connection defaults")
    config_sub = config_cmd.add_subparsers(dest="config_action", required=True)
    config_sub.add_parser("show", help="Print the stored config")
    config_sub.add_parser("path", help="Print the config file location")
    set_cmd = config_sub.add_parser("set", help="Store one or more connection defaults")
    set_cmd.add_argument("--host", help="Printer IP address or hostname")
    set_cmd.add_argument("--port", type=int)
    set_cmd.add_argument("--timeout", type=float)
    unset_cmd = config_sub.add_parser("unset", help="Remove stored keys")
    unset_cmd.add_argument("keys", nargs="+", choices=config_store.KEYS)

    args = parser.parse_args(argv)

    if args.command == "config":
        return _handle_config(args)

    host, port, timeout = _resolve_connection(args, parser)
    client = FlashForgeClient(host, port, timeout=timeout)

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


def _resolve_connection(args, parser) -> tuple[str, int, float]:
    """Combine CLI flags with the stored config: flag > config file > default."""
    stored = config_store.load_config()
    host = args.host or stored.get("host")
    if not host:
        parser.error(
            "no host given: pass --host <ip> or store one with "
            "'ad4ctl config set --host <ip>'"
        )
    port = args.port if args.port is not None else int(stored.get("port", DEFAULT_PORT))
    timeout = (
        args.timeout if args.timeout is not None else float(stored.get("timeout", DEFAULT_TIMEOUT))
    )
    return host, port, timeout


def _handle_config(args) -> int:
    path = config_store.config_path()

    if args.config_action == "path":
        print(path)
        return 0

    if args.config_action == "show":
        stored = config_store.load_config()
        if not stored:
            print(f"No config stored yet ({path}).")
            print("Set one with: ad4ctl config set --host <ip>")
            return 0
        print(f"# {path}")
        for key in config_store.KEYS:
            if key in stored:
                print(f"{key} = {stored[key]}")
        return 0

    if args.config_action == "set":
        updates = {key: getattr(args, key) for key in config_store.KEYS if getattr(args, key) is not None}
        if not updates:
            print("Nothing to set. Pass --host, --port, and/or --timeout.", file=sys.stderr)
            return 2
        saved = config_store.save_config(updates)
        print(f"Saved to {saved}")
        for key, value in updates.items():
            print(f"{key} = {value}")
        return 0

    if args.config_action == "unset":
        removed = config_store.unset_config(args.keys)
        if removed:
            print(f"Removed: {', '.join(removed)}")
        else:
            print("Nothing removed (keys were not set).")
        return 0

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
