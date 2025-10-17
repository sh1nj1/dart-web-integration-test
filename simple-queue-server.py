#!/usr/bin/env python3
"""Interactive DSL queue server with a simple browser UI.

Run this script and open the printed URL in a browser. Use the textarea to
paste a DSL payload (YAML or JSON) and press "Submit" to enqueue it. The
integration test runner can poll the `/next` endpoint to retrieve queued
payloads one at a time.
"""

from __future__ import annotations

import argparse
import queue
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import List
from urllib.parse import parse_qs

_HTML_PAGE = """<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <title>DSL Queue Server</title>
  <style>
    body { font-family: sans-serif; margin: 2rem auto; max-width: 720px; }
    textarea { width: 100%; min-height: 320px; font-family: monospace; }
    .status { margin-top: 1rem; }
    button { padding: 0.6rem 1.2rem; font-size: 1rem; cursor: pointer; }
  </style>
</head>
<body>
  <h1>Interactive DSL Queue</h1>
  <p>Paste a DSL payload (YAML or JSON) and click <strong>Submit</strong> to enqueue it.</p>
  <form id=\"enqueue-form\" method=\"post\" action=\"/enqueue\">
    <textarea name=\"payload\" placeholder=\"# YAML or JSON test definition\"></textarea>
    <div class=\"status\">
      <button type=\"submit\">Submit</button>
      <span id=\"queue-size\"></span>
    </div>
  </form>
  <script>
    const form = document.getElementById('enqueue-form');
    const queueLabel = document.getElementById('queue-size');

    async function refreshStatus() {
      try {
        const response = await fetch('/status');
        if (!response.ok) return;
        const data = await response.json();
        queueLabel.textContent = `Queued: ${data.size}`;
      } catch (err) {
        console.error('Failed to fetch status', err);
      }
    }

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const formData = new FormData(form);
      const payload = formData.get('payload');
      if (!payload || !payload.trim()) {
        alert('Please provide a DSL payload before submitting.');
        return;
      }

      try {
        const response = await fetch('/enqueue', {
          method: 'POST',
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
          body: payload,
        });
        if (response.ok) {
          form.reset();
          await refreshStatus();
        } else {
          alert('Failed to enqueue payload.');
        }
      } catch (err) {
        alert('Request failed: ' + err);
      }
    });

    setInterval(refreshStatus, 1500);
    refreshStatus();
  </script>
</body>
</html>
"""


def _build_handler(
    items: queue.Queue[str],
    *,
    endpoint: str,
) -> type[BaseHTTPRequestHandler]:
    endpoint = endpoint.rstrip("/") or "/"

    class _Handler(BaseHTTPRequestHandler):
        server_version = "SimpleDSLQueue/0.1"

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            sys.stderr.write("[server] " + format % args + "\n")

        def _set_cors(self) -> None:
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")

        def do_GET(self) -> None:  # noqa: N802
            normalized_path = self.path.split("?", 1)[0].rstrip("/") or "/"

            if normalized_path == endpoint:
                self._handle_next()
                return

            if normalized_path == "/status":
                self._handle_status()
                return

            if normalized_path == "/":
                self._send_html(_HTML_PAGE)
                return

            self.send_error(HTTPStatus.NOT_FOUND, "Not Found")

        def do_POST(self) -> None:  # noqa: N802
            normalized_path = self.path.split("?", 1)[0].rstrip("/") or "/"

            if normalized_path == "/enqueue":
                self._handle_enqueue()
                return

            if normalized_path == endpoint:
                self._handle_next()
                return

            self.send_error(HTTPStatus.METHOD_NOT_ALLOWED, "Method not allowed")

        def do_OPTIONS(self) -> None:  # noqa: N802
            self.send_response(HTTPStatus.NO_CONTENT)
            self._set_cors()
            self.end_headers()

        def _handle_next(self) -> None:
            user_agent = self.headers.get("User-Agent", "")
            if "HeadlessChrome" in user_agent:
                self.send_response(HTTPStatus.NO_CONTENT)
                self._set_cors()
                self.end_headers()
                return

            try:
                payload = items.get_nowait()
            except queue.Empty:
                self.send_response(HTTPStatus.NO_CONTENT)
                self._set_cors()
                self.end_headers()
                return

            data = payload.encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self._set_cors()
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _handle_status(self) -> None:
            size = items.qsize()
            body = f"{{\"size\": {size}}}".encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self._set_cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _handle_enqueue(self) -> None:
            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length).decode("utf-8") if length else ""

            content_type = self.headers.get("Content-Type", "").split(";")[0].strip()
            if content_type in {"application/x-www-form-urlencoded", "multipart/form-data"}:
                payloads = parse_qs(raw_body).get("payload", [])
                payload = payloads[0] if payloads else ""
            else:
                payload = raw_body

            payload = payload.strip()
            if not payload:
                self.send_error(HTTPStatus.BAD_REQUEST, "Empty payload")
                return

            items.put(payload)
            self.send_response(HTTPStatus.CREATED)
            self._set_cors()
            self.end_headers()

        def _send_html(self, html: str) -> None:
            data = html.encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
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
            body = f"{code} {message}" if message else str(code)
            self.wfile.write(body.encode("utf-8"))

    return _Handler


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Interface to bind (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=9001,
        help="Port to bind (default: 9001)",
    )
    parser.add_argument(
        "--endpoint",
        default="/next",
        help="Endpoint the integration test polls for DSL payloads (default: /next)",
    )

    args = parser.parse_args(argv)

    items: queue.Queue[str] = queue.Queue()
    handler_cls = _build_handler(items, endpoint=args.endpoint)
    server = HTTPServer((args.host, args.port), handler_cls)

    print(
        "DSL queue server running at http://{host}:{port}/".format(
            host=args.host, port=args.port
        ),
        flush=True,
    )
    print(
        "Integration tests should poll http://{host}:{port}{endpoint}".format(
            host=args.host, port=args.port, endpoint=args.endpoint
        ),
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
