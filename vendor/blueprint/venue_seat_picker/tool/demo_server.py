#!/usr/bin/env python3
"""Loopback-only owned demo server with atomic lifecycle metadata."""
import http.server, json, os, pathlib, signal, sys
root = pathlib.Path(sys.argv[1]).resolve()
state = pathlib.Path(sys.argv[2]).resolve()
os.chdir(root)
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), http.server.SimpleHTTPRequestHandler)
state.write_text(json.dumps({'pid': os.getpid(), 'port': server.server_port, 'root': str(root)}))
def close(*_):
    state.unlink(missing_ok=True)
    sys.exit(0)
signal.signal(signal.SIGTERM, close)
signal.signal(signal.SIGINT, close)
try:
    server.serve_forever()
finally:
    state.unlink(missing_ok=True)
    server.server_close()
