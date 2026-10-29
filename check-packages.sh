#!/usr/bin/env bash
# check-packages.sh — verify every package in config-src/config/package-lists
# exists in Debian 13 (trixie) incl. contrib/non-free/non-free-firmware.
# Uses a private apt state dir, so your host's apt sources are not touched.
# Usage: ./check-packages.sh            (check all lists)
#        ./check-packages.sh pkg1 pkg2  (check just these names)
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=os.conf
. "$KIT_DIR/os.conf"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/lists/partial" "$TMP/cache/archives/partial" "$TMP/etc/preferences.d" "$TMP/etc/sources.list.d"
cat > "$TMP/etc/sources.list" <<SRC
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] ${DEBIAN_MIRROR} trixie main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] ${DEBIAN_MIRROR} trixie-updates main contrib non-free non-free-firmware
SRC

APT_OPTS=(
    -o "Dir::Etc::sourcelist=$TMP/etc/sources.list"
    -o "Dir::Etc::sourceparts=$TMP/etc/sources.list.d"
    -o "Dir::Etc::preferencesparts=$TMP/etc/preferences.d"
    -o "Dir::State::Lists=$TMP/lists"
    -o "Dir::Cache=$TMP/cache"
    -o "Dir::State::status=/dev/null"
    -o "APT::Architecture=amd64"
    -o "Debug::NoDropPrivs=1"
    -o "APT::Sandbox::User=$(id -un)"
)

[[ -f /usr/share/keyrings/debian-archive-keyring.gpg ]] || {
    echo "Install debian-archive-keyring first: sudo apt install debian-archive-keyring" >&2; exit 2; }

echo "Downloading trixie package indices (private temp dir)..."
apt-get "${APT_OPTS[@]}" -qq update

if [[ $# -gt 0 ]]; then
    pkgs=("$@")
else
    mapfile -t pkgs < <(cat "$KIT_DIR"/config-src/config/package-lists/*.list.chroot \
        | sed -e 's/#.*//' | tr -s ' \t' '\n' | sed '/^$/d' | sort -u)
fi

missing=0
for p in "${pkgs[@]}"; do
    if apt-cache "${APT_OPTS[@]}" show "$p" >/dev/null 2>&1; then
        printf '  ok       %s\n' "$p"
    else
        printf '  MISSING  %s\n' "$p"
        missing=$((missing + 1))
    fi
done

if [[ $missing -gt 0 ]]; then
    echo "$missing package(s) not found in trixie. Remove or rename them in config-src/config/package-lists/."
    exit 1
fi
echo "All ${#pkgs[@]} packages exist in Debian 13."
