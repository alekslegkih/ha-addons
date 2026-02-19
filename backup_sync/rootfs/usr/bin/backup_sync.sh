#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

set -uo pipefail

# =========================================================
# Bootstrap only
# =========================================================

BASE_DIR="/usr/local/backup_sync"
export BASE_DIR

source "${BASE_DIR}/core/logger.sh"
source "${BASE_DIR}/core/config.sh"
source "${BASE_DIR}/storage/checks.sh"
source "${BASE_DIR}/storage/detect.sh"
source "${BASE_DIR}/storage/mount.sh"


# =========================================================
# emit helper
# =========================================================

emit() {
  python3 "${BASE_DIR}/ha/emit_cli.py" "$@" || true
}


# =========================================================
# debug & exit
# =========================================================

fail_and_stop() {
  log_error "$1"

  if _is_debug; then
    log_warn "Debug mode enabled — staying alive for investigation"
  else
    exit 1
  fi
}


# =========================================================
# Load config
# =========================================================

load_config || fail_and_stop "Config load failed"


# =========================================================
# Binaries
# =========================================================

WATCHER_BIN="${BASE_DIR}/sync/watcher.py"
SCANNER_BIN="${BASE_DIR}/sync/scanner.py"
COPIER_BIN="${BASE_DIR}/sync/copier.sh"


# =========================================================
# Storage layer
# =========================================================

log_section "Storage layer"

if ! check_storage; then
    detect_devices
    log "Please set parameter: usb_device"
    log_warn "Example: usb_device: sdb1 | label | UUID"
    fail_and_stop "Storage connection failed"
fi

mount_usb     || fail_and_stop "Mount system failed"
check_target  || fail_and_stop "Target checks failed"


# =========================================================
# Sync layer
# =========================================================

log_section "Sync layer"

python3 "${WATCHER_BIN}" &
WATCHER_PID=$!
log_ok "Starting file watcher..."

"${COPIER_BIN}" &
COPIER_PID=$!
log_ok "Starting copy worker..."

if [ "${SYNC_EXIST_START}" = "true" ]; then
  python3 "${SCANNER_BIN}" || true
fi

log_ok "System ready"
emit ready '{}'

s6-notifyoncheck -n

wait "${COPIER_PID}"
