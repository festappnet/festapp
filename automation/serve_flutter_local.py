#!/usr/bin/env python3
"""Serve the built Flutter app locally with SPA routing and no directory listing."""

from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlparse, urlunsplit
from urllib.request import Request, urlopen


class FlutterHandler(SimpleHTTPRequestHandler):
    build_dir: Path

    _sync_proxy_prefix = "/__festapp_sync_asset__/"

    def _proxy_sync_asset(self, *, include_body: bool) -> bool:
        parsed = urlparse(self.path)
        if not parsed.path.startswith(self._sync_proxy_prefix):
            return False

        upstream_path = parsed.path.removeprefix(self._sync_proxy_prefix)
        if not upstream_path.startswith("client-sync/") or ".." in upstream_path:
            self.send_error(403, "Only public client-sync assets may be proxied")
            return True

        upstream_url = urlunsplit(
            ("https", "assets.festapp.net", f"/{upstream_path}", parsed.query, "")
        )
        request = Request(
            upstream_url,
            method="GET" if include_body else "HEAD",
            headers={
                "Accept": self.headers.get("Accept", "application/json"),
                "User-Agent": "Mozilla/5.0 FestappLocalDevelopment/1.0",
            },
        )
        try:
            with urlopen(request, timeout=30) as response:
                self.send_response(response.status)
                for header in ("Content-Type", "Content-Length", "ETag", "Last-Modified"):
                    if value := response.headers.get(header):
                        self.send_header(header, value)
                self.end_headers()
                if include_body:
                    while chunk := response.read(64 * 1024):
                        self.wfile.write(chunk)
        except HTTPError as error:
            self.send_error(error.code, "Public sync asset request failed")
        except URLError:
            self.send_error(502, "Public sync asset is unavailable")
        return True

    def guess_type(self, path: str) -> str:
        # Cloudflare serves these extensionless entrypoints as HTML. Python's
        # static handler otherwise labels them application/octet-stream, which
        # makes browsers abort the navigation instead of rendering the app.
        if Path(path).name in {"flutter", "webclient"}:
            return "text/html"
        return super().guess_type(path)

    def _prepare_path(self) -> None:
        request_path = unquote(urlparse(self.path).path)
        target = self.build_dir / request_path.lstrip("/")

        # A plain Flutter build uses index.html. Festapp's Cloudflare build
        # renames that file to `flutter`, so support both layouts.
        if request_path == "/" or (
            not target.exists() and not Path(request_path).suffix
        ):
            entrypoint = (
                "index.html"
                if (self.build_dir / "index.html").is_file()
                else "flutter"
            )
            self.path = f"/{entrypoint}"

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        if self._proxy_sync_asset(include_body=True):
            return
        self._prepare_path()
        super().do_GET()

    def do_HEAD(self) -> None:  # noqa: N802 - stdlib handler API
        if self._proxy_sync_asset(include_body=False):
            return
        self._prepare_path()
        super().do_HEAD()

    def end_headers(self) -> None:
        # Local development must never retain an obsolete entrypoint or route.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def list_directory(self, path: str):
        self.send_error(404, "Directory listing is disabled")
        return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", default="build/web")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    build_dir = Path(args.directory).resolve()
    if not (build_dir / "index.html").is_file() and not (
        build_dir / "flutter"
    ).is_file():
        parser.error(
            f"{build_dir} contains neither index.html nor the Festapp flutter entrypoint"
        )

    FlutterHandler.build_dir = build_dir
    handler = partial(FlutterHandler, directory=str(build_dir))
    server = ThreadingHTTPServer(("", args.port), handler)
    print(f"Festapp Flutter: http://localhost:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
