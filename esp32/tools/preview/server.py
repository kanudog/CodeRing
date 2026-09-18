#!/usr/bin/env python3
"""Serves the engine preview: a local page driven by the real C engine.

The engine runs as compiled C in a shared library loaded here — this is not
a re-implementation in Python. The browser polls /api/snapshot, which is the
same JSON cr_snapshot_json() will push to the trauma-bay TV.

    cd esp32 && make preview      # builds the library and starts this

Mac/Linux, Python 3 standard library only. Nothing here ships to the watch.
"""

import ctypes
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
ESP32 = os.path.abspath(os.path.join(HERE, "..", ".."))
LIB = os.path.join(ESP32, "build", "libcodering.dylib")
if not os.path.exists(LIB):
    LIB = os.path.join(ESP32, "build", "libcodering.so")
PORT = int(os.environ.get("CR_PREVIEW_PORT", "8765"))

if not os.path.exists(LIB):
    sys.exit("engine library not built — run `make preview` from esp32/")

lib = ctypes.CDLL(LIB)
lib.crp_reset.argtypes = [ctypes.c_int64, ctypes.c_double]
lib.crp_command.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p,
                            ctypes.c_double, ctypes.c_int64]
lib.crp_command.restype = ctypes.c_int
lib.crp_snapshot.argtypes = [ctypes.c_int64, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
lib.crp_snapshot.restype = ctypes.c_int
lib.crp_catalog.argtypes = [ctypes.c_char_p, ctypes.c_int]
lib.crp_catalog.restype = ctypes.c_int

# The engine is a single fixed-size struct with no locking of its own, so
# serialise every call — the same discipline the firmware will need when the
# UI task and the web-push task both touch it.
engine_lock = threading.Lock()
BUF = ctypes.create_string_buffer(256 * 1024)


def now_ms():
    return int(time.time() * 1000)


def snapshot(first_event=0):
    with engine_lock:
        needed = lib.crp_snapshot(now_ms(), first_event, BUF, len(BUF))
        if needed >= len(BUF):          # truncated — never send a half object
            return b'{"error":"snapshot too large"}'
        return BUF.value


def catalog():
    with engine_lock:
        needed = lib.crp_catalog(BUF, len(BUF))
        if needed >= len(BUF):
            return b'{"drugs":[],"events":[]}'
        return BUF.value


def command(name, arg1, arg2, value):
    with engine_lock:
        changed = lib.crp_command(name.encode(), arg1.encode(), arg2.encode(),
                                  float(value), now_ms())
    return changed == 1


class Handler(BaseHTTPRequestHandler):
    def _send(self, body, content_type="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)

        if url.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as handle:
                return self._send(handle.read(), "text/html; charset=utf-8")
        # The trauma-bay display, served from esp32/tv so it can be developed
        # against this engine long before the watch can serve it itself. That
        # file is the one the ESP32 will hold in flash at M5 — it is not a
        # copy, and nothing about it may depend on this server.
        if url.path in ("/tv", "/tv/"):
            with open(os.path.join(HERE, "..", "..", "tv", "index.html"), "rb") as handle:
                return self._send(handle.read(), "text/html; charset=utf-8")
        if url.path == "/api/snapshot":
            first = int(query.get("from", ["0"])[0])
            return self._send(snapshot(first))
        if url.path == "/api/catalog":
            return self._send(catalog())
        if url.path == "/api/command":
            changed = command(query.get("name", [""])[0],
                              query.get("arg1", [""])[0],
                              query.get("arg2", [""])[0],
                              query.get("value", ["-1"])[0])
            return self._send(json.dumps({"changed": changed}))

        self.send_error(404)

    def log_message(self, *args):
        pass            # the poll loop would drown the terminal


if __name__ == "__main__":
    with engine_lock:
        lib.crp_reset(now_ms(), 10.0)
    print("CodeRing engine preview — the real C engine, in a browser")
    print(f"  http://localhost:{PORT}")
    print("  Ctrl-C to stop")
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
