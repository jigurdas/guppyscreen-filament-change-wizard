#!/bin/sh
set -eu

CONFIG_DIR="${1:-/usr/data/printer_data/config}"
TARGET="$CONFIG_DIR/GuppyScreen/filament-change.cfg"
MOONRAKER_CFG="$CONFIG_DIR/moonraker.conf"
UPDATE_DIR="$CONFIG_DIR/GuppyScreen/filament-change-wizard"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root on the printer: sudo $0" >&2
    exit 1
fi

[ -f "$CONFIG_DIR/printer.cfg" ] || { echo "Cannot find $CONFIG_DIR/printer.cfg" >&2; exit 1; }
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_DIR/filament-change-backup-$STAMP-$$"
mkdir -p "$BACKUP_DIR"
cp -p "$CONFIG_DIR/printer.cfg" "$BACKUP_DIR/printer.cfg"
[ ! -f "$TARGET" ] || cp -p "$TARGET" "$BACKUP_DIR/filament-change.cfg"
[ ! -f "$MOONRAKER_CFG" ] || cp -p "$MOONRAKER_CFG" "$BACKUP_DIR/moonraker.conf"

if [ -f "$TARGET" ]; then
    rm -f "$TARGET"
    echo "Removed $TARGET"
else
    echo "Klipper macro file was already absent"
fi

if [ -f "$MOONRAKER_CFG" ] && grep -q '^\[update_manager filament-change-wizard\]' "$MOONRAKER_CFG"; then
    TMP_MOONRAKER="$MOONRAKER_CFG.$$"
    awk '
        $0 == "[update_manager filament-change-wizard]" { skip=1; next }
        skip && $0 ~ /^\[/ { skip=0 }
        !skip { print }
    ' "$MOONRAKER_CFG" > "$TMP_MOONRAKER"
    mv "$TMP_MOONRAKER" "$MOONRAKER_CFG"
    echo "Removed Update Manager entry"
fi

if [ -d "$UPDATE_DIR" ]; then
    rm -rf "$UPDATE_DIR"
    echo "Removed $UPDATE_DIR"
fi

echo "The shared [include GuppyScreen/*.cfg] line was left untouched."
echo "Backup: $BACKUP_DIR"
echo "Restart Klipper and Moonraker manually if they are running."
