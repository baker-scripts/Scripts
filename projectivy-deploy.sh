#!/usr/bin/env bash
# Install Projectivy Launcher on an Android TV device and select it as home.
# Uses ADB_CONTAINER (default: androidtv.internal) when running, otherwise adb.

set -euo pipefail

readonly PROJECTIVY_PACKAGE="com.spocky.projectivylauncher"
readonly PROJECTIVY_HOME="${PROJECTIVY_PACKAGE}/com.spocky.projectivylauncher.MainActivity"
readonly ADB_CONTAINER="${ADB_CONTAINER:-androidtv.internal}"

usage() {
  cat >&2 <<EOF
Usage: $0 <device-host> [<apk-path>|--launcher-only|--backup <file>|--restore <file>]

The device must expose ADB over TCP and trust the selected ADB client key.
Set ADB_CONTAINER to use a running container other than androidtv.internal.
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage
readonly DEVICE_HOST="$1"
readonly DEVICE_TARGET="${DEVICE_HOST}:5555"
APK_PATH="${2:-$(dirname "$0")/projectivy.apk}"
LAUNCHER_ONLY=false
RESTORE_PATH=""
BACKUP_PATH=""

case "${2:-}" in
  --launcher-only) LAUNCHER_ONLY=true ;;
  --restore)
    LAUNCHER_ONLY=true
    RESTORE_PATH="${3:?--restore needs a path}"
    ;;
  --backup)
    LAUNCHER_ONLY=true
    BACKUP_PATH="${3:?--backup needs a path}"
    ;;
esac

declare -a adb_cmd
if command -v docker >/dev/null 2>&1 \
  && docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$ADB_CONTAINER"; then
  adb_cmd=(docker exec "$ADB_CONTAINER" adb)
  printf 'Using ADB from container %s\n' "$ADB_CONTAINER"
elif command -v adb >/dev/null 2>&1; then
  adb_cmd=(adb)
  printf 'Using host ADB\n'
else
  printf 'ERROR: no running ADB container and no host adb executable\n' >&2
  exit 1
fi

run_adb() {
  "${adb_cmd[@]}" "$@"
}

cleanup() {
  run_adb disconnect "$DEVICE_TARGET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Connecting to %s\n' "$DEVICE_TARGET"
run_adb connect "$DEVICE_TARGET" >/dev/null
run_adb -s "$DEVICE_TARGET" wait-for-device

device_name="$(run_adb -s "$DEVICE_TARGET" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
printf 'Connected: %s\n' "${device_name:-unknown}"

if [[ "$LAUNCHER_ONLY" == false ]]; then
  [[ -f "$APK_PATH" ]] || {
    printf 'ERROR: APK not found at %s; use --launcher-only after store installation\n' "$APK_PATH" >&2
    exit 1
  }
  run_adb -s "$DEVICE_TARGET" install -r -g "$APK_PATH"
fi

if ! run_adb -s "$DEVICE_TARGET" shell pm list packages 2>/dev/null \
  | grep -Fq "package:${PROJECTIVY_PACKAGE}"; then
  printf 'ERROR: Projectivy is not installed; install it first or provide an APK\n' >&2
  exit 1
fi

if [[ -n "$RESTORE_PATH" ]]; then
  [[ -f "$RESTORE_PATH" ]] || {
    printf 'ERROR: restore file not found: %s\n' "$RESTORE_PATH" >&2
    exit 1
  }
  printf 'Restoring Projectivy configuration; confirm the prompt on the TV\n'
  run_adb -s "$DEVICE_TARGET" restore "$RESTORE_PATH"
fi

if [[ -n "$BACKUP_PATH" ]]; then
  printf 'Backing up Projectivy configuration; confirm the prompt on the TV\n'
  run_adb -s "$DEVICE_TARGET" backup -f "$BACKUP_PATH" -noapk "$PROJECTIVY_PACKAGE"
  printf 'Backup written: %s bytes\n' "$(stat -c %s "$BACKUP_PATH" 2>/dev/null || echo missing)"
  exit 0
fi

printf 'Setting Projectivy as the default launcher\n'
run_adb -s "$DEVICE_TARGET" shell cmd package set-home-activity "$PROJECTIVY_HOME"
printf 'Done. Press Home on the TV to verify Projectivy launches.\n'
