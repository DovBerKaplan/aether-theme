#!/usr/bin/env bash
# Install the aether-direction layer: per-app RTL/LTR launch rules.
# Installs the CLI and the launch wrapper into ~/.local/bin and syncs
# any existing rules. Nothing global changes — apps without a rule
# launch exactly as the system launches them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

command -v python3 >/dev/null || { echo "missing: python3" >&2; exit 1; }

install -Dm755 "$ROOT/system/direction/aether-direction" "$HOME/.local/bin/aether-direction"
install -Dm755 "$ROOT/system/direction/aether-direction-run" "$HOME/.local/bin/aether-direction-run"

"$HOME/.local/bin/aether-direction" sync

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "note: add $HOME/.local/bin to PATH to use aether-direction in a terminal" >&2 ;;
esac
echo "direction layer installed — try: aether-direction set dolphin rtl"
