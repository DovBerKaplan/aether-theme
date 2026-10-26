#!/usr/bin/env python3
"""Test helper: a temporary virtual absolute pointer (via /dev/uinput) for driving UI tests.

    pointer-test.py move X Y [--hold SECONDS]    warp the pointer to X,Y (screen pixels)
    pointer-test.py click X Y                    warp there and left-click

The virtual device exists only while this process runs, so --hold keeps it (and the
pointer position) alive. Screen size defaults to 1920x1080; override with --size WxH.
"""
import argparse
import fcntl
import os
import struct
import time

EV_SYN, EV_KEY, EV_ABS = 0x00, 0x01, 0x03
ABS_X, ABS_Y = 0x00, 0x01
BTN_LEFT = 0x110
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502


def ioctl_ptr(fd, req, val):
    fcntl.ioctl(fd, req, val)


class Pointer:
    def __init__(self, w, h):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        for ev in (EV_KEY, EV_ABS, EV_SYN):
            ioctl_ptr(self.fd, UI_SET_EVBIT, ev)
        ioctl_ptr(self.fd, UI_SET_KEYBIT, BTN_LEFT)
        for ax in (ABS_X, ABS_Y):
            ioctl_ptr(self.fd, UI_SET_ABSBIT, ax)
        name = b"aether-pointer-test"
        absmax = [0] * 64
        absmax[ABS_X], absmax[ABS_Y] = w - 1, h - 1
        dev = struct.pack("80sHHHHi", name, 0x03, 0x1, 0x1, 1, 0)   # BUS_USB-ish ids, ff_effects_max
        dev += struct.pack("64i", *absmax) + struct.pack("64i", *([0] * 64))
        dev += struct.pack("64i", *([0] * 64)) + struct.pack("64i", *([0] * 64))
        os.write(self.fd, dev)
        ioctl_ptr(self.fd, UI_DEV_CREATE, 0)
        time.sleep(1.0)   # let the compositor pick the device up

    def emit(self, t, c, v):
        os.write(self.fd, struct.pack("llHHi", 0, 0, t, c, v))

    def move(self, x, y):
        self.emit(EV_ABS, ABS_X, x)
        self.emit(EV_ABS, ABS_Y, y)
        self.emit(EV_SYN, 0, 0)

    def click(self):
        self.emit(EV_KEY, BTN_LEFT, 1)
        self.emit(EV_SYN, 0, 0)
        time.sleep(0.06)
        self.emit(EV_KEY, BTN_LEFT, 0)
        self.emit(EV_SYN, 0, 0)

    def close(self):
        ioctl_ptr(self.fd, UI_DEV_DESTROY, 0)
        os.close(self.fd)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["move", "click"])
    ap.add_argument("x", type=int)
    ap.add_argument("y", type=int)
    ap.add_argument("--hold", type=float, default=0.5)
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--via-top", type=float, default=0.0, metavar="SECONDS",
                    help="first rest at y=1 for this long")
    a = ap.parse_args()
    w, h = map(int, a.size.split("x"))
    p = Pointer(w, h)
    try:
        if a.via_top:               # arrive the way a hand does: through the top edge
            p.move(a.x, 1)
            time.sleep(a.via_top)
        p.move(a.x, a.y)
        time.sleep(0.2)
        if a.action == "click":
            p.click()
        time.sleep(a.hold)
    finally:
        p.close()
