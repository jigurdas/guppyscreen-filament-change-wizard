#!/bin/sh
set -eu

REPO_URL="https://github.com/jigurdas/guppyscreen-filament-change-wizard.git"
RAW_URL="https://raw.githubusercontent.com/jigurdas/guppyscreen-filament-change-wizard/main"
DEFAULT_CONFIG_DIR="/usr/data/printer_data/config"
CONFIG_DIR="${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TMP_CFG="/tmp/filament-change.cfg.$$"
TMP_REPO="${CONFIG_DIR}/GuppyScreen/filament-change-wizard.tmp.$$"

cleanup() {
    rm -f "$TMP_CFG"
    rm -rf "$TMP_REPO"
}
trap cleanup EXIT INT TERM
fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

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
MOONRAKER_CFG="$CONFIG_DIR/moonraker.conf"
GUPPY_DIR="$CONFIG_DIR/GuppyScreen"
TARGET_CFG="$GUPPY_DIR/filament-change.cfg"
UPDATE_DIR="$GUPPY_DIR/filament-change-wizard"

[ -f "$PRINTER_CFG" ] || fail "Cannot find $PRINTER_CFG"
mkdir -p "$GUPPY_DIR"

# A curl installation is converted into a real checkout for Moonraker Update Manager.
# Clone to a temporary path first so a failed network operation never deletes a working install.
case "$SELF_DIR" in
    "$UPDATE_DIR") ;;
    *)
        command -v git >/dev/null 2>&1 || fail "git is required for Moonraker Update Manager"
        rm -rf "$TMP_REPO"
        git clone --depth=1 "$REPO_URL" "$TMP_REPO"
        if [ -d "$UPDATE_DIR/.git" ]; then
            OLD_UPDATE_DIR="${UPDATE_DIR}.old.$$"
            mv "$UPDATE_DIR" "$OLD_UPDATE_DIR"
            mv "$TMP_REPO" "$UPDATE_DIR"
            rm -rf "$OLD_UPDATE_DIR"
        else
            mv "$TMP_REPO" "$UPDATE_DIR"
        fi
        exec env CONFIG_DIR="$CONFIG_DIR" "$UPDATE_DIR/install.sh"
        ;;
esac

LOCAL_CFG="$SELF_DIR/klipper/filament-change.cfg"
if [ -f "$LOCAL_CFG" ]; then
    cp "$LOCAL_CFG" "$TMP_CFG"
elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW_URL/klipper/filament-change.cfg" -o "$TMP_CFG" || fail "Cannot download filament-change.cfg"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_CFG" "$RAW_URL/klipper/filament-change.cfg" || fail "Cannot download filament-change.cfg"
else
    fail "curl or wget is required"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_DIR/filament-change-backup-$STAMP-$$"
mkdir -p "$BACKUP_DIR"
cp -p "$PRINTER_CFG" "$BACKUP_DIR/printer.cfg"
[ ! -f "$TARGET_CFG" ] || cp -p "$TARGET_CFG" "$BACKUP_DIR/filament-change.cfg"
[ ! -f "$MOONRAKER_CFG" ] || cp -p "$MOONRAKER_CFG" "$BACKUP_DIR/moonraker.conf"

cp "$TMP_CFG" "$TARGET_CFG"

if ! grep -Eq '^[[:space:]]*\[include[[:space:]]+GuppyScreen/\*\.cfg\][[:space:]]*$' "$PRINTER_CFG"; then
    printf '\n[include GuppyScreen/*.cfg]\n' >> "$PRINTER_CFG"
fi

if [ -f "$MOONRAKER_CFG" ]; then
    if ! grep -q '^\[update_manager filament-change-wizard\]' "$MOONRAKER_CFG"; then
        cat >> "$MOONRAKER_CFG" <<EOF

[update_manager filament-change-wizard]
type: git_repo
channel: stable
path: $UPDATE_DIR
origin: $REPO_URL
primary_branch: main
install_script: install.sh
managed_services: klipper
info_tags:
    desc=Native Filament Change wizard for Guppy Screen
EOF
    fi
    SPOOLMAN_STATUS="Spoolman section found"
    grep -q '^\[spoolman\]' "$MOONRAKER_CFG" || SPOOLMAN_STATUS="WARNING: [spoolman] was not found; active spool tracking will not work"
else
    SPOOLMAN_STATUS="WARNING: $MOONRAKER_CFG was not found; Update Manager and Spoolman checks were skipped"
fi

restart_service() {
    service_name="$1"
    if [ "$service_name" = klipper ] && [ -x /etc/init.d/S55klipper_service ]; then
        /etc/init.d/S55klipper_service restart
    elif [ "$service_name" = moonraker ] && [ -x /etc/init.d/S56moonraker_service ]; then
        /etc/init.d/S56moonraker_service restart
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$service_name"
    else
        warn "No service manager found; restart $service_name manually"
    fi
}

restart_service klipper || fail "Klipper restart failed; restore the backup in $BACKUP_DIR before retrying"
[ ! -f "$MOONRAKER_CFG" ] || restart_service moonraker || fail "Moonraker restart failed; restore the backup in $BACKUP_DIR before retrying"

echo "Filament Change Wizard installed"
echo "Update path: $UPDATE_DIR"
echo "Config: $TARGET_CFG"
echo "Backup: $BACKUP_DIR"
echo "$SPOOLMAN_STATUS"
