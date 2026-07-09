from __future__ import annotations

import os
import socket
import time
from pathlib import Path
from typing import Callable

from .models import PrinterStatus
from .parser import parse_file_list, parse_status

ProgressCallback = Callable[[int, int], None]


class FlashForgeClient:
    """Small TCP client for legacy FlashForge printers on port 8899.

    Confirmed against a FlashForge Adventurer 4 firmware v2.3.3-3.33.
    Commands are sent as `~GCODE\r\n`. File upload is performed on the same
    socket after `M28 /data/name.gcode` and completed with `M29`.
    """

    def __init__(self, host: str, port: int = 8899, timeout: float = 8.0) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout

    def command(self, gcode: str, read_timeout: float | None = None) -> str:
        with self._connect(timeout=read_timeout or self.timeout) as sock:
            self._send_command(sock, gcode)
            return self._read_response(sock, read_timeout or self.timeout)

    def status(self) -> PrinterStatus:
        return parse_status(
            self.command("M119"),
            self.command("M105"),
            self.command("M27"),
        )

    def files_raw(self) -> str:
        return self.command("M661", read_timeout=12.0)

    def files(self) -> list[str]:
        return parse_file_list(self.files_raw())

    def upload(
        self,
        local_file: str | os.PathLike[str],
        remote_name: str | None = None,
        progress: ProgressCallback | None = None,
        chunk_size: int = 4096,
    ) -> str:
        path = Path(local_file)
        if not path.is_file():
            raise FileNotFoundError(path)

        remote = remote_name or path.name
        remote_path = remote if remote.startswith("/data/") else f"/data/{remote}"
        total = path.stat().st_size
        sent = 0

        with self._connect(timeout=max(self.timeout, 30.0)) as sock:
            self._send_command(sock, f"M28 {remote_path}")
            # Some printers reply before data, some stay quiet until M29. Read briefly only.
            self._read_available(sock, 0.5)

            with path.open("rb") as fh:
                while True:
                    chunk = fh.read(chunk_size)
                    if not chunk:
                        break
                    sock.sendall(chunk)
                    sent += len(chunk)
                    if progress:
                        progress(sent, total)

            self._send_command(sock, "M29")
            self._read_response(sock, 20.0)

        return remote_path

    def print_file(self, remote_name: str) -> str:
        remote_path = remote_name if remote_name.startswith("/data/") else f"/data/{remote_name}"
        # Proven working on AD4: select SD file then start/resume SD print.
        select_response = self.command(f"M23 {remote_path}")
        start_response = self.command("M24")
        return select_response + "\n" + start_response

    def pause(self) -> str:
        return self.command("M25")

    def resume(self) -> str:
        return self.command("M24")

    def cancel(self) -> str:
        return self.command("M26")

    def _connect(self, timeout: float | None = None) -> socket.socket:
        sock = socket.create_connection((self.host, self.port), timeout=timeout or self.timeout)
        sock.settimeout(timeout or self.timeout)
        return sock

    @staticmethod
    def _send_command(sock: socket.socket, gcode: str) -> None:
        payload = f"~{gcode}\r\n".encode("utf-8")
        sock.sendall(payload)

    @staticmethod
    def _read_response(sock: socket.socket, timeout: float) -> str:
        sock.settimeout(timeout)
        chunks: list[bytes] = []
        end = time.time() + timeout
        while time.time() < end:
            try:
                data = sock.recv(8192)
            except socket.timeout:
                break
            if not data:
                break
            chunks.append(data)
            text = b"".join(chunks).decode("utf-8", errors="replace")
            if "\nok" in text or text.rstrip().endswith("ok"):
                break
        return b"".join(chunks).decode("utf-8", errors="replace")

    @staticmethod
    def _read_available(sock: socket.socket, timeout: float) -> str:
        previous = sock.gettimeout()
        sock.settimeout(timeout)
        chunks: list[bytes] = []
        try:
            while True:
                try:
                    data = sock.recv(8192)
                except socket.timeout:
                    break
                if not data:
                    break
                chunks.append(data)
                if b"ok" in data:
                    break
        finally:
            sock.settimeout(previous)
        return b"".join(chunks).decode("utf-8", errors="replace")
