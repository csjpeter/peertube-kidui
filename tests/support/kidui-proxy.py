#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Peter Csaszar (Császár Péter)
# Created: 2026-10-12
# Test front end: serves this checkout under /kidui and proxies every other path to PeerTube.
"""Usage: kidui-proxy.py LISTEN_PORT PEERTUBE_PORT

Plays the role of nginx for the E2E tests: one origin for the page, the API and
the embedded player, as in production. Standard library only; loopback only.
"""
import http.client
import http.server
import os
import sys

ROOT = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", ".."))
HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
       "te", "trailers", "transfer-encoding", "upgrade"}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    upstream_port = 0

    def log_message(self, fmt, *args):
        sys.stderr.write("kidui-proxy: " + fmt % args + "\n")

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/kidui" or path.startswith("/kidui/"):
            return self.serve_static(path)
        return self.proxy()

    do_HEAD = do_GET
    do_POST = do_GET

    def serve_static(self, path):
        rel = path[len("/kidui"):].lstrip("/") or "index.html"
        full = os.path.realpath(os.path.join(ROOT, rel))
        if not (full == ROOT or full.startswith(ROOT + os.sep)) or not os.path.isfile(full):
            self.send_error(404)
            return
        with open(full, "rb") as f:
            body = f.read()
        ctype = "text/html; charset=utf-8" if full.endswith(".html") else "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        conn = http.client.HTTPConnection("127.0.0.1", self.upstream_port, timeout=60)
        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            data = resp.read()
        except OSError as e:
            self.send_error(502, str(e))
            return
        finally:
            conn.close()
        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() not in HOP and k.lower() not in ("content-length", "content-security-policy"):
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)


def main():
    listen, upstream = int(sys.argv[1]), int(sys.argv[2])
    Handler.upstream_port = upstream
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", listen), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
