#!/bin/sh
set -eu

CONFIG_DIR="${1:-/usr/data/printer_data/config}"
TARGET_DIR="$CONFIG_DIR/GuppyScreen"
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root on the printer: sudo $0"
    exit 1
fi

if [ ! -f "$CONFIG_DIR/printer.cfg" ]; then
    echo "Cannot find $CONFIG_DIR/printer.cfg" >&2
    exit 1
fi

mkdir -p "$TARGET_DIR"
cp "$SOURCE_DIR/klipper/filament-change.cfg" "$TARGET_DIR/filament-change.cfg"

if ! grep -q '^\[include GuppyScreen/\*\.cfg\]' "$CONFIG_DIR/printer.cfg"; then
    printf '\n[include GuppyScreen/*.cfg]\n' >> "$CONFIG_DIR/printer.cfg"
fi

chown --reference="$CONFIG_DIR/printer.cfg" "$TARGET_DIR/filament-change.cfg" 2>/dev/null || true

echo "Installed $TARGET_DIR/filament-change.cfg"
echo "Restart Klipper, then use the Filament Change button while the slicer pause is active."
