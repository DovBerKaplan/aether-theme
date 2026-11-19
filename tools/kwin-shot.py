#!/usr/bin/env python3
"""Capture the composited KWin scene through the ScreenShot2 dbus API.

Unlike `import -window root` — which only sees raw X11 clients on the
rootful sandbox Xwayland — this returns what KWin actually composites
(effects, wayland windows, theme). Works against any bus where a KWin with
ScreenShot2 lives; inside an aether-agent-run sandbox that is the fresh
dbus-run-session bus, which also grants the call.

    kwin-shot.py OUT.png
"""
import argparse
import os
import subprocess
import tempfile

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


def capture(out_path):
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    r_fd, w_fd = os.pipe()
    fd_list = Gio.UnixFDList()
    idx = fd_list.append(w_fd)
    try:
        res = conn.call_with_unix_fd_list_sync(
            "org.kde.KWin.ScreenShot2",
            "/org/kde/KWin/ScreenShot2",
            "org.kde.KWin.ScreenShot2",
            "CaptureActiveScreen",
            GLib.Variant("(a{sv}h)", ({"include-cursor": GLib.Variant("b", False)}, idx)),
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            fd_list,
        )
    finally:
        os.close(w_fd)

    meta, = res[0]
    if not isinstance(meta, dict) or "width" not in meta:
        raise SystemExit(f"kwin-shot: unexpected reply: {meta}")
    # the a{sv} arrives auto-unpacked: plain ints, or Variants on older GLib
    def _num(v):
        return v if isinstance(v, int) else v.get_uint32()
    width = _num(meta["width"])
    height = _num(meta["height"])
    keys = {k: _num(v) for k, v in meta.items() if k != "data" and isinstance(v, (int,))}
    print(f"kwin-shot: meta={keys}", flush=True)

    import select
    chunks = []
    deadline = 20
    while True:
        ready, _, _ = select.select([r_fd], [], [], deadline)
        if not ready:
            raise SystemExit("kwin-shot: kwin never wrote to the pipe (frame never came)")
        chunk = os.read(r_fd, 1 << 20)
        if not chunk:
            break
        chunks.append(chunk)
    os.close(r_fd)
    print(f"kwin-shot: read {sum(map(len, chunks))} bytes", flush=True)
    if not chunks:
        raise SystemExit("kwin-shot: empty pipe")

    with tempfile.NamedTemporaryFile(suffix=".raw", delete=False) as raw:
        raw.write(b"".join(chunks))
        raw_path = raw.name
    try:
        # the pipe carries 32bpp BGRA pixels
        subprocess.run(["convert", "-size", f"{width}x{height}", "-depth", "8",
                        f"bgra:{raw_path}", out_path], check=True)
    finally:
        os.unlink(raw_path)
    print(f"kwin-shot: {width}x{height} -> {out_path}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("out")
    capture(p.parse_args().out)
