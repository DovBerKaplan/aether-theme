#!/usr/bin/env bash
# Snapshot the KDE config files this theme touches, so restore.sh can undo it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/backups/kde-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
mkdir -p "$ROOT/backups"
cd "$HOME"
files=()
for f in .config/kdeglobals .config/kwinrc .config/plasmarc .config/plasmashellrc \
         .config/plasma-org.kde.plasma.desktop-appletsrc .config/Kvantum \
         .config/konsolerc .local/share/konsole .config/kcminputrc .config/gtk-3.0 .config/gtk-4.0; do
  [[ -e $f ]] && files+=("$f")
done
tar czf "$OUT" "${files[@]}"
echo "$OUT"
