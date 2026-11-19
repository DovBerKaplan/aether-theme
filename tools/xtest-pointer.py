#!/usr/bin/env python3
"""XTEST pointer driver aimed at ONE X display.

Safe inside an aether-agent-run sandbox: XTEST through the sandbox's own
rootful Xwayland is scoped to that display and never touches the real seat.
For driving the live desktop use pointer-test.py (uinput) instead.

    xtest-pointer.py --display :N move X Y
    xtest-pointer.py --display :N click X Y
"""
import argparse

from Xlib import X, display
from Xlib.ext import xtest


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--display", required=True, help="X display to drive, e.g. :42")
    p.add_argument("action", choices=["move", "click"])
    p.add_argument("x", type=int)
    p.add_argument("y", type=int)
    a = p.parse_args()

    d = display.Display(a.display)
    xtest.fake_input(d, X.MotionNotify, x=a.x, y=a.y)
    if a.action == "click":
        xtest.fake_input(d, X.ButtonPress, 1)
        xtest.fake_input(d, X.ButtonRelease, 1)
    d.sync()


if __name__ == "__main__":
    main()
