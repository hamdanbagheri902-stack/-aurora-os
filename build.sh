#!/usr/bin/env bash
# build.sh — one command to build the ISO described by os.conf + config-src/.
# Safe to re-run: every run unmounts leftovers, wipes build/, and rebuilds.
# Downloaded .debs are kept between runs (in .lb-cache/) unless --purge-cache.
set -Eeuo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$KIT_DIR/build"
OUT_DIR="$KIT_DIR/out"
LOG_DIR="$KIT_DIR/logs"
CACHE_KEEP="$KIT_DIR/.lb-cache"

INSTALL_DEPS=1
PREPARE_ONLY=0
CLEAN_ONLY=0
PURGE_CACHE=0
CHECK_PACKAGES=1

usage() {
    cat <<USAGE
Usage: sudo ./build.sh [options]

  (no options)     install build tools, check packages, clean, build the ISO
  --no-deps        do not apt-get install the build tools
  --no-check       skip the package-name preflight check
  --prepare-only   only create build/ with rendered config (no root needed, no lb)
  --clean          only remove build/ (keeps the package cache)
  --purge-cache    also delete the downloaded package cache
  -h, --help       this help
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --no-deps)      INSTALL_DEPS=0 ;;
        --no-check)     CHECK_PACKAGES=0 ;;
        --prepare-only) PREPARE_ONLY=1; INSTALL_DEPS=0; CHECK_PACKAGES=0 ;;
        --clean)        CLEAN_ONLY=1 ;;
        --purge-cache)  PURGE_CACHE=1 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage; exit 2 ;;
    esac
done

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# shellcheck source=os.conf
. "$KIT_DIR/os.conf"

[[ "$OS_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]]      || die "OS_ID must be lowercase letters, digits, dashes"
[[ "$LIVE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]   || die "LIVE_USER is not a valid user name"
[[ "$VBOX_GUEST" == yes || "$VBOX_GUEST" == no ]] || die "VBOX_GUEST must be yes or no"
VOLUME="$OS_NAME $OS_VERSION"
[[ ${#VOLUME} -le 32 ]] || die "\"$VOLUME\" is longer than 32 characters (ISO volume label limit); shorten OS_NAME"
[[ "$KIT_DIR" != *" "* ]] || die "The kit path contains a space; live-build cannot handle that. Move it (e.g. ~/os-kit)."

if [[ $PREPARE_ONLY -eq 0 && $EUID -ne 0 ]]; then
    die "Run as root: sudo ./build.sh"
fi

host_check() {
    local codename=""
    codename="$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}")"
    if [[ "$codename" != "trixie" ]]; then
        warn "Build host is '${codename:-unknown}', not Debian 13 (trixie). This kit is written for a Debian 13 host."
    fi
    local free_gb
    free_gb="$(df -BG --output=avail "$KIT_DIR" | tail -1 | tr -dc '0-9')"
    if [[ -n "$free_gb" && "$free_gb" -lt 25 ]]; then
        warn "Only ${free_gb} GB free next to the kit; a build needs about 25 GB."
    fi
}

install_deps() {
    log "Installing build tools"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        live-build debootstrap debian-archive-keyring ca-certificates \
        xorriso squashfs-tools mtools dosfstools \
        isolinux syslinux syslinux-common syslinux-utils \
        grub-common grub-pc-bin grub-efi-amd64-bin \
        python3 python3-pil fonts-dejavu-core
}

unmount_leftovers() {
    # An interrupted build can leave /proc, /sys, /dev/pts... mounted inside build/chroot.
    [[ -d "$BUILD_DIR/chroot" ]] || return 0
    local m
    { findmnt -rn -o TARGET | grep -F "$BUILD_DIR/" || true; } | sort -r | while read -r m; do
        warn "Unmounting leftover mount $m"
        umount -l "$m" || true
    done
}

clean() {
    log "Cleaning previous build"
    unmount_leftovers
    if [[ -d "$BUILD_DIR" ]]; then
        if [[ -d "$BUILD_DIR/cache" && $PURGE_CACHE -eq 0 ]]; then
            rm -rf "$CACHE_KEEP"
            mv "$BUILD_DIR/cache" "$CACHE_KEEP"
        fi
        if [[ $EUID -eq 0 && -d "$BUILD_DIR/config" ]] && command -v lb >/dev/null; then
            (cd "$BUILD_DIR" && lb clean --purge) >/dev/null 2>&1 || true
        fi
        unmount_leftovers
        rm -rf --one-file-system "$BUILD_DIR"
    fi
    if [[ $PURGE_CACHE -eq 1 ]]; then
        rm -rf "$CACHE_KEEP"
    fi
}

prepare() {
    log "Preparing build/ from config-src/ for $OS_NAME $OS_VERSION"
    mkdir -p "$BUILD_DIR"
    cp -a "$KIT_DIR/config-src/." "$BUILD_DIR/"

    python3 "$KIT_DIR/tools/render.py" "$BUILD_DIR" \
        "OS_NAME=$OS_NAME" "OS_ID=$OS_ID" "OS_VERSION=$OS_VERSION" \
        "LIVE_USER=$LIVE_USER" "DEBIAN_MIRROR=$DEBIAN_MIRROR" "VBOX_GUEST=$VBOX_GUEST"

    python3 "$KIT_DIR/tools/make-branding.py" \
        --name "$OS_NAME" --version "$OS_VERSION" \
        --out "$BUILD_DIR/config/includes.chroot/etc/calamares/branding/$OS_ID"

    # Make sure everything that must be executable is (zip/USB copies can lose the bit).
    chmod 0755 "$BUILD_DIR"/auto/* "$BUILD_DIR"/config/hooks/normal/*.hook.*
    chmod 0755 "$BUILD_DIR/config/includes.chroot/usr/bin/$OS_ID-install"
    chmod 0755 "$BUILD_DIR/config/includes.chroot/usr/lib/$OS_ID-installer/"*

    if [[ -d "$CACHE_KEEP" ]]; then
        mv "$CACHE_KEEP" "$BUILD_DIR/cache"
    fi
}

build_iso() {
    mkdir -p "$LOG_DIR" "$OUT_DIR"
    local logfile
    logfile="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
    local started=$SECONDS

    log "Running lb config + lb build (log: $logfile)"
    cd "$BUILD_DIR"
    lb config 2>&1 | tee -a "$logfile"
    lb build  2>&1 | tee -a "$logfile"

    local iso
    iso="$(find "$BUILD_DIR" -maxdepth 1 -name '*.iso' -print -quit)"
    [[ -n "$iso" ]] || die "No ISO was produced. Search the log for lines starting with 'E:' : $logfile"

    local dest="$OUT_DIR/${OS_ID}-${OS_VERSION}-amd64.iso"
    mv -f "$iso" "$dest"
    (cd "$OUT_DIR" && sha256sum "$(basename "$dest")" > "$(basename "$dest").sha256")
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown "$SUDO_USER": "$dest" "$dest.sha256" "$logfile" || true
    fi

    local mins=$(( (SECONDS - started) / 60 ))
    log "Done in ${mins} min: $dest ($(du -h "$dest" | cut -f1))"
}

host_check
if [[ $CLEAN_ONLY -eq 1 ]]; then clean; exit 0; fi
if [[ $INSTALL_DEPS -eq 1 ]]; then install_deps; fi
if [[ $CHECK_PACKAGES -eq 1 ]]; then
    log "Checking that every listed package exists in Debian 13"
    "$KIT_DIR/check-packages.sh" || die "Fix the package lists (see above) or re-run with --no-check"
fi
clean
prepare
if [[ $PREPARE_ONLY -eq 1 ]]; then
    log "Prepared $BUILD_DIR (no ISO built because of --prepare-only)"
    exit 0
fi
build_iso
