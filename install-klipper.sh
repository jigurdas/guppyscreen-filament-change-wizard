#!/bin/sh
set -eu

CONFIG_DIR="${1:-/usr/data/printer_data/config}"
TARGET_DIR="$CONFIG_DIR/GuppyScreen"
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root on the printer: sudo $0" >&2
    exit 1
fi

[ -f "$CONFIG_DIR/printer.cfg" ] || { echo "Cannot find $CONFIG_DIR/printer.cfg" >&2; exit 1; }
[ -f "$SOURCE_DIR/klipper/filament-change.cfg" ] || { echo "Cannot find the bundled Klipper config" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_DIR/filament-change-backup-$STAMP"
mkdir -p "$TARGET_DIR" "$BACKUP_DIR"
cp -p "$CONFIG_DIR/printer.cfg" "$BACKUP_DIR/printer.cfg"
[ ! -f "$TARGET_DIR/filament-change.cfg" ] || cp -p "$TARGET_DIR/filament-change.cfg" "$BACKUP_DIR/filament-change.cfg"

TMP_TARGET="$TARGET_DIR/filament-change.cfg.$$"
cp "$SOURCE_DIR/klipper/filament-change.cfg" "$TMP_TARGET"
mv "$TMP_TARGET" "$TARGET_DIR/filament-change.cfg"

if ! grep -Eq '^[[:space:]]*\[include[[:space:]]+GuppyScreen/\*\.cfg\][[:space:]]*$' "$CONFIG_DIR/printer.cfg"; then
    printf '\n[include GuppyScreen/*.cfg]\n' >> "$CONFIG_DIR/printer.cfg"
fi

chown --reference="$CONFIG_DIR/printer.cfg" "$TARGET_DIR/filament-change.cfg" 2>/dev/null || true

echo "Installed $TARGET_DIR/filament-change.cfg"
echo "Backup: $BACKUP_DIR"
echo "Restart Klipper, then use the Filament Change button while the slicer pause is active."
