#!/usr/bin/env python3
"""OrcaSlicer post-processing helper.

Usage from OrcaSlicer post-processing command:
  /path/to/python /path/to/scripts/orca_ad4_upload.py --host 192.168.1.50 --start

Orca passes the generated G-code path as the final argument in many configurations.
If your Orca build does not, use the CLI manually for now.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from ad4core import FlashForgeClient


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("gcode", nargs="?", help="Generated G-code file path")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=8899)
    parser.add_argument("--start", action="store_true")
    args = parser.parse_args()

    if not args.gcode:
        print("No G-code path supplied by slicer.", file=sys.stderr)
        return 2

    file_path = Path(args.gcode)
    client = FlashForgeClient(args.host, args.port)
    remote = client.upload(file_path)
    print(f"Uploaded {remote}")
    if args.start:
        print(client.print_file(remote))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
