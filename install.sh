#!/bin/sh
set -eu

# One-command installer for Guppy Screen Filament Change Wizard.
# Run on the Ender-3 V3 KE over SSH as root.

REPO_RAW="https://raw.githubusercontent.com/jigurdas/guppyscreen-filament-change-wizard/main"
DEFAULT_CONFIG_DIR="/usr/data/printer_data/config"
CONFIG_DIR="${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
BACKUP_DIR=""
TMP_CFG="/tmp/filament-change.cfg.$$"

cleanup() {
    rm -f "$TMP_CFG"
}
trap cleanup EXIT INT TERM

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail "Run as root: sudo sh install.sh"

if command -v curl >/dev/null 2>&1; then
    PRINTER_INFO="$(curl -fsS http://127.0.0.1:7125/printer/info 2>/dev/null || true)"
else
    PRINTER_INFO=""
fi

if command -v jq >/dev/null 2>&1 && [ -n "$PRINTER_INFO" ]; then
    DETECTED_CONFIG="$(printf '%s' "$PRINTER_INFO" | jq -r '.result.config_file // empty' 2>/dev/null || true)"
    if [ -n "$DETECTED_CONFIG" ] && [ -f "$DETECTED_CONFIG" ]; then
        CONFIG_DIR="$(dirname "$DETECTED_CONFIG")"
    fi
fi

PRINTER_CFG="$CONFIG_DIR/printer.cfg"
GUPPY_DIR="$CONFIG_DIR/GuppyScreen"
TARGET="$GUPPY_DIR/filament-change.cfg"

[ -f "$PRINTER_CFG" ] || fail "Cannot find $PRINTER_CFG"
mkdir -p "$GUPPY_DIR"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_RAW/klipper/filament-change.cfg" -o "$TMP_CFG" || fail "Cannot download filament-change.cfg"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_CFG" "$REPO_RAW/klipper/filament-change.cfg" || fail "Cannot download filament-change.cfg"
else
    fail "curl or wget is required"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_DIR/filament-change-backup-$STAMP"
mkdir -p "$BACKUP_DIR"
cp -p "$PRINTER_CFG" "$BACKUP_DIR/printer.cfg"
[ ! -f "$TARGET" ] || cp -p "$TARGET" "$BACKUP_DIR/filament-change.cfg"

cp "$TMP_CFG" "$TARGET"

if ! grep -q '^\[include GuppyScreen/\*\.cfg\]' "$PRINTER_CFG"; then
    printf '\n[include GuppyScreen/*.cfg]\n' >> "$PRINTER_CFG"
fi

if grep -q '^\[spoolman\]' "$CONFIG_DIR/../printer_data/config/moonraker.conf" 2>/dev/null; then
    SPOOLMAN_STATUS="Spoolman section found"
elif grep -q '^\[spoolman\]' "$CONFIG_DIR/moonraker.conf" 2>/dev/null; then
    SPOOLMAN_STATUS="Spoolman section found"
else
    SPOOLMAN_STATUS="WARNING: [spoolman] was not found; active spool tracking will not work"
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart klipper 2>/dev/null || true
elif [ -x /etc/init.d/S55klipper_service ]; then
    /etc/init.d/S55klipper_service restart >/dev/null 2>&1 || true
fi

echo "Filament Change installed"
echo "Config: $TARGET"
echo "Backup: $BACKUP_DIR"
echo "$SPOOLMAN_STATUS"
echo "Use the FILAMENT_CHANGE macro while a slicer pause is active."
echo "The printer-side wizard is installed; the native Guppy UI patch requires a patched Guppy Screen build."
