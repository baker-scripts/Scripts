#!/usr/bin/env bash
# Update pinned Android TV APKs when a device is reachable over network ADB.

set -euo pipefail

readonly ADB_CONTAINER="${ADB_CONTAINER:-androidtv.internal}"

usage() {
  cat >&2 <<EOF
Usage: $0 <device-host> <manifest.tsv>

Manifest columns (tab-separated): package, minimum versionCode, source, SHA-256.
Use source "managed" and checksum "-" to audit a Play-managed package without
installing it. Otherwise source must be an APK URL with its pinned checksum.
Blank lines and lines beginning with # are ignored. Updates and downgrades must
be represented by a new pinned version and checksum; downgrades are refused.
EOF
  exit 2
}

[[ $# -eq 2 ]] || usage
readonly DEVICE_TARGET="$1:5555"
readonly MANIFEST="$2"
[[ -r "$MANIFEST" ]] || {
  printf 'ERROR: manifest is not readable: %s\n' "$MANIFEST" >&2
  exit 1
}

declare -a adb_cmd
if command -v docker >/dev/null 2>&1 \
  && docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$ADB_CONTAINER"; then
  adb_cmd=(docker exec "$ADB_CONTAINER" adb)
elif command -v adb >/dev/null 2>&1; then
  adb_cmd=(adb)
else
  printf 'ERROR: no running ADB container and no host adb executable\n' >&2
  exit 1
fi

run_adb() {
  "${adb_cmd[@]}" "$@"
}

tmp_dir="$(mktemp -d)"
cleanup() {
  run_adb disconnect "$DEVICE_TARGET" >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if ! timeout 15s "${adb_cmd[@]}" connect "$DEVICE_TARGET" >/dev/null; then
  printf 'Device is offline or ADB is unavailable: %s\n' "$DEVICE_TARGET" >&2
  exit 75
fi
device_state="$(run_adb -s "$DEVICE_TARGET" get-state 2>&1 || true)"
if [[ "$device_state" == *unauthorized* ]]; then
  printf 'ERROR: ADB authorization is missing; approve the persistent client key on the TV\n' >&2
  exit 77
fi
if ! timeout 15s "${adb_cmd[@]}" -s "$DEVICE_TARGET" wait-for-device; then
  printf 'ERROR: timed out waiting for authorized ADB device %s\n' "$DEVICE_TARGET" >&2
  exit 75
fi
device_state="$(run_adb -s "$DEVICE_TARGET" get-state 2>&1 || true)"
[[ "$device_state" == device ]] || {
  printf 'ERROR: unexpected ADB state for %s: %s\n' "$DEVICE_TARGET" "$device_state" >&2
  exit 1
}

updates=0
audit_failures=0
while IFS=$'\t' read -r package target_version source expected_sha extra; do
  [[ -z "$package" || "$package" == \#* ]] && continue
  [[ -z "${extra:-}" && "$target_version" =~ ^[0-9]+$ ]] || {
    printf 'ERROR: invalid manifest row for %s\n' "$package" >&2
    exit 1
  }

  installed_version="$(run_adb -s "$DEVICE_TARGET" shell dumpsys package "$package" 2>/dev/null \
    | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
  installed_version="${installed_version:-0}"
  if [[ "$source" == managed ]]; then
    [[ "$expected_sha" == - ]] || {
      printf 'ERROR: managed package %s must use checksum "-"\n' "$package" >&2
      exit 1
    }
    if ((installed_version >= target_version && installed_version > 0)); then
      printf 'Managed/current: %s (%s)\n' "$package" "$installed_version"
    else
      printf 'MANAGED ACTION NEEDED: %s is missing or below %s (installed: %s)\n' \
        "$package" "$target_version" "$installed_version" >&2
      audit_failures=$((audit_failures + 1))
    fi
    continue
  fi
  [[ "$expected_sha" =~ ^[[:xdigit:]]{64}$ ]] || {
    printf 'ERROR: invalid SHA-256 for %s\n' "$package" >&2
    exit 1
  }
  if ((installed_version == target_version)); then
    printf 'Current: %s (%s)\n' "$package" "$target_version"
    continue
  fi
  if ((installed_version > target_version)); then
    printf 'ERROR: refusing downgrade of %s from %s to %s\n' \
      "$package" "$installed_version" "$target_version" >&2
    exit 1
  fi

  apk_path="$tmp_dir/${package}.apk"
  curl --fail --location --silent --show-error "$source" --output "$apk_path"
  printf '%s  %s\n' "${expected_sha,,}" "$apk_path" | sha256sum --check --status || {
    printf 'ERROR: checksum mismatch for %s\n' "$package" >&2
    exit 1
  }
  printf 'Updating: %s (%s -> %s)\n' "$package" "$installed_version" "$target_version"
  run_adb -s "$DEVICE_TARGET" install -r -g "$apk_path"
  updates=$((updates + 1))
done <"$MANIFEST"

printf 'Sync complete: %s update(s) installed\n' "$updates"
if ((audit_failures > 0)); then
  printf 'Managed package audit: %s action(s) needed\n' "$audit_failures" >&2
  exit 3
fi
