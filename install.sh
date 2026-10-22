#!/bin/sh
set -eu

REPO_URL="https://github.com/jigurdas/guppyscreen-filament-change-wizard.git"
DEFAULT_CONFIG_DIR="/usr/data/printer_data/config"
CONFIG_DIR="${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TMP_REPO="${CONFIG_DIR}/GuppyScreen/filament-change-wizard.tmp.$$"
TMP_TARGET=""

cleanup() {
    rm -rf "$TMP_REPO"
    [ -z "$TMP_TARGET" ] || rm -f "$TMP_TARGET"
}
trap cleanup EXIT INT TERM
fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

# Creality firmware keeps Klipper in /usr/share/klipper; KIAUH installs use ~/klipper
find_klipper_extras() {
    for dir in "${KLIPPER_EXTRAS:-}" /usr/share/klipper/klippy/extras "$HOME/klipper/klippy/extras"; do
        if [ -n "$dir" ] && [ -f "$dir/gcode_macro.py" ]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
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

# From here on the script runs from the Update Manager checkout. The config
# and the module are symlinked into it, so an update from Fluidd/Mainsail
# (git pull, then a Klipper service restart by Moonraker) applies them;
# Moonraker does not run this script on updates.
LOCAL_CFG="$UPDATE_DIR/klipper/filament-change.cfg"
LOCAL_MODULE="$UPDATE_DIR/klipper/fc_spoolman.py"
[ -f "$LOCAL_CFG" ] || fail "Cannot find $LOCAL_CFG"
[ -f "$LOCAL_MODULE" ] || fail "Cannot find $LOCAL_MODULE"
EXTRAS_DIR="$(find_klipper_extras)" || fail "Cannot find klippy/extras; set KLIPPER_EXTRAS=/path/to/klippy/extras"
TARGET_MODULE="$EXTRAS_DIR/fc_spoolman.py"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_DIR/filament-change-backup-$STAMP-$$"
mkdir -p "$BACKUP_DIR"
cp -p "$PRINTER_CFG" "$BACKUP_DIR/printer.cfg"
[ ! -f "$TARGET_CFG" ] || cp -p "$TARGET_CFG" "$BACKUP_DIR/filament-change.cfg"
[ ! -f "$MOONRAKER_CFG" ] || cp -p "$MOONRAKER_CFG" "$BACKUP_DIR/moonraker.conf"
[ ! -f "$TARGET_MODULE" ] || cp -p "$TARGET_MODULE" "$BACKUP_DIR/fc_spoolman.py"

# The module goes first: the config's [fc_spoolman] section needs it.
# Links are created next to the target and renamed over it, so the target
# is never missing.
TMP_TARGET="$TARGET_MODULE.$$"
ln -s "$LOCAL_MODULE" "$TMP_TARGET"
mv -f "$TMP_TARGET" "$TARGET_MODULE"

TMP_TARGET="$TARGET_CFG.$$"
ln -s "$LOCAL_CFG" "$TMP_TARGET"
mv -f "$TMP_TARGET" "$TARGET_CFG"
TMP_TARGET=""

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

# Creality's init scripts restart with "stop; sleep 1; start", and start
# refuses to run while the old process is still exiting, which leaves the
# service down. Stop, wait for the pid to go away, then start.
restart_initd() {
    script="$1"
    pidfile="$2"
    "$script" stop || true
    tries=0
    while [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -le 30 ] || return 1
        sleep 1
    done
    "$script" start
}

restart_service() {
    service_name="$1"
    if [ "$service_name" = klipper ] && [ -x /etc/init.d/S55klipper_service ]; then
        /etc/init.d/S55klipper_service restart
    elif [ "$service_name" = moonraker ] && [ -x /etc/init.d/S56moonraker_service ]; then
        restart_initd /etc/init.d/S56moonraker_service /var/run/moonraker.pid
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
echo "Klipper module: $TARGET_MODULE"
echo "Backup: $BACKUP_DIR"
echo "$SPOOLMAN_STATUS"
