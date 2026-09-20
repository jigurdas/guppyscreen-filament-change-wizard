#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH="$ROOT/ui/patches/0001-filament-change-wizard.patch"
UPSTREAM_DIR="${1:-}"

sh -n "$ROOT/install.sh" "$ROOT/install-klipper.sh" "$ROOT/uninstall-klipper.sh"
git -C "$ROOT" diff --check -- . ':!ui/patches/0001-filament-change-wizard.patch'

if LC_ALL=C grep -n "$(printf '\033')" "$PATCH" >/dev/null 2>&1; then
    echo "ERROR: patch contains ANSI escape codes" >&2
    exit 1
fi

if [ -n "$UPSTREAM_DIR" ]; then
    git -C "$UPSTREAM_DIR" apply --check "$PATCH"
fi

CFG="$ROOT/klipper/filament-change.cfg"
grep -q 'SAVE_GCODE_STATE NAME=filament_change' "$CFG"
[ "$(grep -c 'RESTORE_GCODE_STATE NAME=filament_change' "$CFG")" -ge 2 ]
grep -q 'TMP_TARGET="\$TARGET_CFG.\$\$"' "$ROOT/install.sh"
grep -q 'mv "\$TMP_TARGET" "\$TARGET_CFG"' "$ROOT/install.sh"

echo "Validation passed"
