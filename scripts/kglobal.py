"""Helpers to read/write KDE global shortcuts through kglobalaccel's DBus API."""
import dbus
from PySide6.QtCore import Qt

MODS = [("Meta", 0x10000000), ("Ctrl", 0x04000000), ("Alt", 0x08000000), ("Shift", 0x02000000)]
_KEYS = {k.name.replace("Key_", ""): k.value for k in Qt.Key}
_NAMES = {v: k for k, v in _KEYS.items()}
ALIASES = {"PgUp": "PageUp", "PgDown": "PageDown", "Esc": "Escape", "Del": "Delete",
           "Print": "Print", ".": "Period", ",": "Comma", "=": "Equal", "-": "Minus", "+": "Plus"}


def encode(seq: str) -> int:
    """'Meta+Shift+S' -> Qt combined int."""
    parts = seq.split("+") if seq != "+" else ["+"]
    if seq.endswith("++"):
        parts = seq[:-2].split("+") + ["+"]
    val = 0
    for p in parts[:-1]:
        val |= dict(MODS)[p]
    key = ALIASES.get(parts[-1], parts[-1])
    if len(key) == 1 and key.isalpha():
        key = key.upper()
    return val | _KEYS[key]


def decode(code: int) -> str:
    code = int(code)
    out = [n for n, m in MODS if code & m]
    key = code & ~(0x10000000 | 0x04000000 | 0x08000000 | 0x02000000 | 0x20000000)
    out.append(_NAMES.get(key, hex(key)))
    return "+".join(out)


def bus():
    b = dbus.SessionBus()
    return b, dbus.Interface(b.get_object("org.kde.kglobalaccel", "/kglobalaccel"), "org.kde.KGlobalAccel")


def infos(component: str):
    b, _ = bus()
    o = dbus.Interface(b.get_object("org.kde.kglobalaccel", "/component/" + component),
                       "org.kde.kglobalaccel.Component")
    return list(o.allShortcutInfos())


def keys_arg(seqs):
    # a(ai): each QKeySequence is a struct of up to 4 combined ints
    return dbus.Array([dbus.Struct([dbus.Array([dbus.Int32(encode(s))], signature="i")], signature=None)
                       for s in seqs], signature="(ai)")
