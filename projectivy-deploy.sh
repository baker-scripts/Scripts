#!/usr/bin/env bash
# Install Projectivy Launcher on an Android TV device and select it as home.
# Uses ADB_CONTAINER (default: androidtv-adb) when running, otherwise adb.

set -euo pipefail

readonly PROJECTIVY_PACKAGE="com.spocky.projengmenu"
readonly PROJECTIVY_HOME="${PROJECTIVY_PACKAGE}/.ui.home.MainActivity"
readonly ADB_CONTAINER="${ADB_CONTAINER:-androidtv-adb}"

usage() {
  cat >&2 <<EOF
Usage: $0 <device-host> [<apk-path>|--launcher-only|--backup <file>|--restore <file>]

The device must expose ADB over TCP and trust the selected ADB client key.
Set ADB_CONTAINER to use a running container other than androidtv-adb.
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
  "") ;;
  --launcher-only) LAUNCHER_ONLY=true ;;
  --restore)
    LAUNCHER_ONLY=true
    RESTORE_PATH="${3:?--restore needs a path}"
    ;;
  --backup)
    LAUNCHER_ONLY=true
    BACKUP_PATH="${3:?--backup needs a path}"
    ;;
  --*)
    printf 'ERROR: unknown option: %s\n' "$2" >&2
    usage
    ;;
esac

declare -a adb_cmd
using_container=false
container_tmp=""
if command -v docker >/dev/null 2>&1 \
  && docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$ADB_CONTAINER"; then
  adb_cmd=(docker exec "$ADB_CONTAINER" adb)
  using_container=true
  container_tmp="/tmp/projectivy-deploy-$$"
  docker exec "$ADB_CONTAINER" mkdir -p "$container_tmp"
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
  if [[ "$using_container" == true ]]; then
    docker exec "$ADB_CONTAINER" rm -rf "$container_tmp" >/dev/null 2>&1 || true
  fi
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
  install_path="$APK_PATH"
  if [[ "$using_container" == true ]]; then
    install_path="$container_tmp/projectivy.apk"
    docker cp "$APK_PATH" "$ADB_CONTAINER:$install_path"
  fi
  run_adb -s "$DEVICE_TARGET" install -r -g "$install_path"
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
  restore_path="$RESTORE_PATH"
  if [[ "$using_container" == true ]]; then
    restore_path="$container_tmp/projectivy.ab"
    docker cp "$RESTORE_PATH" "$ADB_CONTAINER:$restore_path"
  fi
  run_adb -s "$DEVICE_TARGET" restore "$restore_path"
fi

if [[ -n "$BACKUP_PATH" ]]; then
  printf 'Backing up Projectivy configuration; confirm the prompt on the TV\n'
  backup_path="$BACKUP_PATH"
  if [[ "$using_container" == true ]]; then
    backup_path="$container_tmp/projectivy.ab"
  fi
  run_adb -s "$DEVICE_TARGET" backup -f "$backup_path" -noapk "$PROJECTIVY_PACKAGE"
  if [[ "$using_container" == true ]]; then
    docker cp "$ADB_CONTAINER:$backup_path" "$BACKUP_PATH"
  fi
  if [[ -r "$BACKUP_PATH" ]]; then
    printf 'Backup written: %s bytes\n' "$(wc -c <"$BACKUP_PATH" | tr -d '[:space:]')"
  else
    printf 'Backup written: missing\n'
  fi
  exit 0
fi

printf 'Setting Projectivy as the default launcher\n'
run_adb -s "$DEVICE_TARGET" shell cmd package set-home-activity "$PROJECTIVY_HOME"
printf 'Done. Press Home on the TV to verify Projectivy launches.\n'
