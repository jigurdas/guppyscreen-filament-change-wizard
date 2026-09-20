#!/bin/sh
set -eu

CONFIG_DIR="${1:-/usr/data/printer_data/config}"
TARGET="$CONFIG_DIR/GuppyScreen/filament-change.cfg"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root on the printer: sudo $0"
    exit 1
fi

if [ -f "$TARGET" ]; then
    rm -f "$TARGET"
    echo "Removed $TARGET"
else
    echo "Nothing to remove"
fi

echo "The existing GuppyScreen/*.cfg include was left untouched."
