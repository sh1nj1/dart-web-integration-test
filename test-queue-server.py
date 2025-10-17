#!/usr/bin/env python3
"""Simple HTTP server that serves queued DSL files one request at a time.

Usage:
    ./test-queue-server.py test_dsl/sample_test.yaml [more_paths...]

On each GET request to the configured endpoint (default: /next), the server
returns the next file's content as plain text (UTF-8). By default, after all
queued files have been served the server will keep responding with HTTP 204 so
the client can continue polling. Pass ``--exit`` to send the configured exit
command (default: ``exit``) instead, which lets the integration test terminate
its interactive session automatically.
"""

from __future__ import annotations

import argparse
import pathlib
import queue
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import List


def _read_files(paths: List[str]) -> queue.Queue[str]:
    items: queue.Queue[str] = queue.Queue()
    for raw_path in paths:
        path = pathlib.Path(raw_path).expanduser().resolve()
        if not path.is_file():
            raise FileNotFoundError(f"DSL file not found: {path}")
        content = path.read_text(encoding="utf-8")
        items.put(content)
    return items


def _build_handler(
    items: queue.Queue[str],
    *,
    endpoint: str,
    exit_command: str,
    auto_exit: bool,
) -> type[BaseHTTPRequestHandler]:
    endpoint = endpoint.rstrip("/") or "/"

    class _Handler(BaseHTTPRequestHandler):
        server_version = "TestQueueHTTP/0.1"

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            sys.stderr.write("[server] " + format % args + "\n")

        def _set_cors(self) -> None:
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")

        def do_GET(self) -> None:  # noqa: N802 (HTTP verb naming)
            if self.path.rstrip("/") != endpoint:
                self.send_error(HTTPStatus.NOT_FOUND, "Not Found")
                return

            try:
                payload = items.get_nowait()
            except queue.Empty:
                if not auto_exit:
                    self.send_response(HTTPStatus.NO_CONTENT)
                    self._set_cors()
                    self.end_headers()
                    return

                payload = exit_command
                self._send_payload(payload)
                return

            self._send_payload(payload)

            # Requeue payloads in cycling mode so they are served repeatedly.
            if not auto_exit:
                items.put(payload)

        def do_POST(self) -> None:  # noqa: N802
            # Optional: allow POST /exit to terminate immediately.
            if self.path.rstrip("/") == endpoint and not auto_exit:
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length).decode("utf-8") if length else ""
                if body.strip().lower() == exit_command.lower():
                    self._send_payload(exit_command)
                    return
            self.send_error(HTTPStatus.METHOD_NOT_ALLOWED, "Method not allowed")

        def do_OPTIONS(self) -> None:  # noqa: N802
            self.send_response(HTTPStatus.NO_CONTENT)
            self._set_cors()
            self.end_headers()

        def _send_payload(self, payload: str) -> None:
            data = payload.encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self._set_cors()
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def send_error(  # type: ignore[override]
            self,
            code: int,
            message: str,
            explain: str | None = None,
        ) -> None:
            self.send_response(code, message)
            self._set_cors()
            self.send_header("Content-Type", self.error_content_type)
            self.end_headers()
            if message:
                body = f"{code} {message}"
            else:
                body = str(code)
            self.wfile.write(body.encode("utf-8"))

    return _Handler


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="+",
        help="DSL files to serve in order",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Interface to bind (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=9000,
        help="Port to bind (default: 9000)",
    )
    parser.add_argument(
        "--endpoint",
        default="/next",
        help="Request path to serve payloads from (default: /next)",
    )
    parser.add_argument(
        "--exit-command",
        default="exit",
        help="Payload to send when --exit is used (default: exit)",
    )
    parser.add_argument(
        "--exit",
        action="store_true",
        help="After serving all files, send the exit command instead of HTTP 204",
    )

    args = parser.parse_args(argv)

    try:
        items = _read_files(args.paths)
    except FileNotFoundError as exc:
        parser.error(str(exc))

    handler_cls = _build_handler(
        items,
        endpoint=args.endpoint,
        exit_command=args.exit_command,
        auto_exit=args.exit,
    )

    server = HTTPServer((args.host, args.port), handler_cls)
    print(
        f"Serving {items.qsize()} DSL payload(s) on"
        f" http://{args.host}:{args.port}{args.endpoint}",
        flush=True,
    )
    print("Press Ctrl+C to stop.", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
