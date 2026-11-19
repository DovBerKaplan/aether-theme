"""Load theme/tokens.toml, the single source of design values (see docs/DESIGN-SYSTEM.md).

    from tokens import load
    T = load()
    T["role"]["dark"]["accent"]   -> "#00f2fe"  (palette names resolved to hex)
    T["radius"]["card"]           -> 24
"""
import re
import tomllib
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "tokens.toml"
HEX = re.compile(r"#[0-9a-f]{6}")
HEXA = re.compile(r"#[0-9a-f]{6}([0-9a-f]{2})?")
EASINGS = {"Linear", "InCubic", "OutCubic", "InOutCubic", "OutQuint", "InOutSine", "InOutQuad", "OutBack"}


class TokenError(ValueError):
    pass


def _check_hex(where: str, value) -> str:
    if not isinstance(value, str) or not HEX.fullmatch(value):
        raise TokenError(f"{where}: expected lowercase #rrggbb, got {value!r}")
    return value


def _numbers(where: str, table: dict) -> None:
    for key, value in table.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise TokenError(f"{where}.{key}: expected a number, got {value!r}")


def _check_names(table: dict, where: str) -> None:
    """QML reads a property named on<Upper>... as a signal handler; refuse such token names."""
    for key, value in table.items():
        if re.fullmatch(r"on-[a-z0-9].*", key):
            raise TokenError(f"{where}{key}: names starting with 'on-' clash with QML signal handlers")
        if isinstance(value, dict):
            _check_names(value, f"{where}{key}.")


def load(path: Path = PATH) -> dict:
    """Parse, validate and resolve the tokens. Raises TokenError on any malformed entry."""
    with open(path, "rb") as f:
        t = tomllib.load(f)

    palette = t.get("palette") or {}
    if not palette:
        raise TokenError("[palette] is empty")
    for key, value in palette.items():
        _check_hex(f"palette.{key}", value)

    for mode, roles in (t.get("role") or {}).items():
        for key, ref in roles.items():
            where = f"role.{mode}.{key}"
            if isinstance(ref, str) and ref in palette:
                roles[key] = palette[ref]
            elif isinstance(ref, str) and ref.startswith("#"):
                roles[key] = _check_hex(where, ref)
            else:
                raise TokenError(f"{where}: {ref!r} is neither a palette name nor #rrggbb")

    for section in ("material", "tint", "space", "radius", "type", "apps"):
        _numbers(section, t.get(section) or {})
    for key, alpha in (t.get("material") or {}).items():
        if key.endswith(("alpha", "opacity", "scrim", "frost")) or key.startswith("tint-"):
            if not 0 <= alpha <= 1:
                raise TokenError(f"material.{key}: {alpha} is outside 0..1")

    for key, alpha in (t.get("apps") or {}).items():
        if key.endswith("alpha") and not 0 <= alpha <= 1:
            raise TokenError(f"apps.{key}: {alpha} is outside 0..1")

    for key, alpha in (t.get("tint") or {}).items():
        if not 0 <= alpha <= 1:
            raise TokenError(f"tint.{key}: {alpha} is outside 0..1")

    motion = t.get("motion") or {}
    _numbers("motion.duration", motion.get("duration") or {})
    for key, name in (motion.get("easing") or {}).items():
        if name not in EASINGS:
            raise TokenError(f"motion.easing.{key}: unknown curve {name!r} (known: {sorted(EASINGS)})")

    _check_names(t, "")

    # Generator inputs: any string that is a palette name becomes its hex; other "#..." must be valid hex.
    def resolve(node, where):
        for key, value in node.items():
            here = f"{where}.{key}"
            if isinstance(value, dict):
                resolve(value, here)
            elif isinstance(value, list):
                node[key] = [palette.get(v, v) if isinstance(v, str) else v for v in value]
                for v in node[key]:
                    if isinstance(v, str) and v.startswith("#") and not HEXA.fullmatch(v):
                        raise TokenError(f"{here}: bad color {v!r}")
            elif isinstance(value, str):
                node[key] = palette.get(value, value)
                if node[key].startswith("#") and not HEXA.fullmatch(node[key]):
                    raise TokenError(f"{here}: bad color {value!r}")

    for section in ("scheme", "terminal", "kvantum"):
        resolve(t.get(section) or {}, section)

    for key, value in (t.get("font") or {}).items():
        if not isinstance(value, str) or not value:
            raise TokenError(f"font.{key}: expected a family name")
    return t


def camel(key: str) -> str:
    """kebab-case token name -> camelCase QML name ("text-muted" -> "textMuted", "cyan-400" -> "cyan400")."""
    head, *rest = key.split("-")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)
