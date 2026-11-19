#!/usr/bin/env python3
"""XTEST key driver aimed at ONE X display.

Safe inside an aether-agent-run sandbox (same scope rule as xtest-pointer.py).

    xtest-keys.py --display :N super_w
"""
import argparse
import time

from Xlib import X, XK, display
from Xlib.ext import xtest


def keycode(d, name):
    return d.keysym_to_keycode(XK.string_to_keysym(name))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--display", required=True)
    p.add_argument("combo", choices=["super_w", "super_g"])
    a = p.parse_args()

    d = display.Display(a.display)
    mod = keycode(d, "Super_L")
    key = keycode(d, a.combo.split("_")[1])

    xtest.fake_input(d, X.KeyPress, mod)
    d.sync(); time.sleep(0.05)
    xtest.fake_input(d, X.KeyPress, key)
    d.sync(); time.sleep(0.05)
    xtest.fake_input(d, X.KeyRelease, key)
    d.sync(); time.sleep(0.05)
    xtest.fake_input(d, X.KeyRelease, mod)
    d.sync()


if __name__ == "__main__":
    main()
