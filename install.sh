#!/usr/bin/env bash
# Installs Rizoma for this user (~/.local), without root. It becomes nobody's
# default: that is a switch in Rizoma itself.
#
#   ./install.sh           a copy of it
#   ./install.sh --here    runs from this checkout (GENOMA=<genoma to run it with>)
set -euo pipefail
cd "$(dirname "$0")"

id=dev.akusen.rizoma
bin="$HOME/.local/bin"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
run="${GENOMA:-genoma}"
command -v "$run" >/dev/null || { echo "Rizoma needs genoma in PATH."; exit 1; }

if [[ "${1:-}" == --here ]]; then
    dir="$PWD/genoma"
else
    dir="$data/rizoma/app"
    rm -rf "$dir"
    mkdir -p "$dir"
    cp -r genoma/. "$dir/"
fi
mkdir -p "$bin"
sed "s|/usr/share/rizoma|$dir|; s|\${GENOMA:-genoma}|\${GENOMA:-$run}|" rizoma > "$bin/rizoma"
chmod 755 "$bin/rizoma"
install -Dm644 "$id.desktop" "$data/applications/$id.desktop"
install -Dm644 assets/rizoma.svg "$data/icons/hicolor/scalable/apps/$id.svg"
update-desktop-database "$data/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$data/icons/hicolor" 2>/dev/null || true
echo "Installed: $bin/rizoma"
