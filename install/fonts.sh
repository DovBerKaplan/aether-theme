#!/usr/bin/env bash
# Fetch the fonts Aether expects into ~/.local/share/fonts: Inter and
# JetBrainsMono Nerd Font. Families already on the system are skipped, so on a
# configured machine this is a no-op and nothing needs the network.
set -euo pipefail
FDIR="$HOME/.local/share/fonts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v fc-list >/dev/null 2>&1 || { echo "missing: fc-list (fontconfig)" >&2; exit 1; }
fetch() {
  if command -v curl >/dev/null 2>&1; then curl -fL --retry 2 --progress-bar -o "$2" "$1"
  else wget -q -O "$2" "$1"; fi
}
have_font() { [ -n "$(fc-list ":family=$1" 2>/dev/null)" ]; }
# Copy files matching a glob out of the zip into place, plus the license.
unpack() { # <zip> <glob> <license-prefix>
  python3 - "$1" "$2" "$3" "$FDIR" <<'PY'
import fnmatch, sys, zipfile
zip_path, pattern, prefix, dest = sys.argv[1:5]
with zipfile.ZipFile(zip_path) as z:
    for name in z.namelist():
        base = name.rsplit("/", 1)[-1]
        if fnmatch.fnmatch(base, pattern):
            with z.open(name) as src, open(f"{dest}/{base}", "wb") as out:
                out.write(src.read())
            print("  +", base)
        elif base in ("LICENSE.txt", "LICENSE.md", "OFL.txt"):
            with z.open(name) as src, open(f"{dest}/licenses/{prefix}-{base}", "wb") as out:
                out.write(src.read())
PY
}

mkdir -p "$FDIR/licenses"

if have_font "Inter"; then
  echo "== Inter: already installed"
else
  echo "== Inter (github.com/rsms/inter, OFL-1.1)"
  fetch https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip "$TMP/inter.zip"
  unpack "$TMP/inter.zip" "InterVariable*.ttf" Inter
fi

if have_font "JetBrainsMono Nerd Font"; then
  echo "== JetBrainsMono Nerd Font: already installed"
else
  echo "== JetBrainsMono Nerd Font (github.com/ryanoasis/nerd-fonts)"
  fetch https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip "$TMP/nerd.zip"
  unpack "$TMP/nerd.zip" "JetBrainsMonoNerdFont-*.ttf" JetBrainsMonoNerdFont
fi

fc-cache -f "$FDIR" >/dev/null 2>&1 || true
echo "Fonts ready in $FDIR"
