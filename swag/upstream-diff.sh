#!/bin/bash
set -euo pipefail

# upstream-diff.sh — Smart diff of local SWAG/nginx proxy-confs against
# upstream sample configs (e.g. linuxserver/reverse-proxy-confs).
# Filters known customizations, flags genuine upstream changes.
#
# Usage: upstream-diff.sh <upstream-dir> [options]
# Exit codes: 0 = no actionable changes, 1 = has changes, 2 = error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPO_ROOT

# --- Configuration ---
OUTPUT_JSON=false
UPSTREAM_DIR=""
CONFIG_ROOT=""
declare -a DOMAINS=()

# Counters
declare -i TOTAL_CHECKED=0
declare -i TOTAL_NO_UPSTREAM=0
declare -i TOTAL_REDIRECT=0
declare -i TOTAL_CLEAN=0
declare -i TOTAL_FORKED=0
declare -i TOTAL_ACTIONABLE=0

# Accumulate markdown output
MARKDOWN_BODY=""
# Accumulate JSON entries
JSON_ENTRIES=""

# --- Argument parsing ---
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output-json)
        OUTPUT_JSON=true
        ;;
      --config-root)
        CONFIG_ROOT="${2:-}"
        shift
        ;;
      --domain)
        DOMAINS+=("${2:-}")
        shift
        ;;
      --help | -h)
        usage
        exit 0
        ;;
      -*)
        printf "Unknown option: %s\n" "$1" >&2
        usage >&2
        exit 2
        ;;
      *)
        if [[ -z "$UPSTREAM_DIR" ]]; then
          UPSTREAM_DIR="$1"
        else
          printf "Unexpected argument: %s\n" "$1" >&2
          usage >&2
          exit 2
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$UPSTREAM_DIR" ]]; then
    printf "Error: upstream directory required\n" >&2
    usage >&2
    exit 2
  fi

  if [[ ! -d "$UPSTREAM_DIR" ]]; then
    printf "Error: upstream directory does not exist: %s\n" "$UPSTREAM_DIR" >&2
    exit 2
  fi
}

usage() {
  cat <<'USAGE'
Usage: upstream-diff.sh <upstream-dir> [options]

Compare local SWAG/nginx proxy-conf files against upstream sample configs
(e.g. a checkout of linuxserver/reverse-proxy-confs). Filters known
customizations and reports only genuine upstream changes.

Arguments:
  <upstream-dir>     Path to a checkout of the upstream sample-conf repo

Options:
  --config-root DIR  Root directory to scan for local *.conf files.
                      Default: the first of REPO_ROOT/config/servers,
                      REPO_ROOT/servers, REPO_ROOT/proxy-confs, REPO_ROOT
                      that exists, where REPO_ROOT is the parent of this
                      script's directory.
  --domain NAME       Restrict the scan to configs under a path segment
                      matching */NAME/*.conf (repeatable). Use this if
                      your local tree is organized per-domain, e.g.
                      --domain example.com --domain example.org.
                      Default: scan all *.conf files under --config-root.
  --output-json       Output results as JSON instead of markdown
  --help, -h          Show this help

Exit codes:
  0  No actionable changes found
  1  Actionable changes found (needs review)
  2  Error
USAGE
}

# --- Upstream name mapping ---
# Load alias map: local_name=upstream_name
declare -A UPSTREAM_MAP
load_upstream_map() {
  local mapfile="${SCRIPT_DIR}/upstream-map.conf"
  if [[ -f "$mapfile" ]]; then
    while IFS='=' read -r local_name upstream_name; do
      # Skip comments and blank lines
      [[ -z "$local_name" || "$local_name" =~ ^# ]] && continue
      local_name="${local_name%%[[:space:]]*}"
      upstream_name="${upstream_name%%[[:space:]]*}"
      upstream_name="${upstream_name##[[:space:]]}"
      UPSTREAM_MAP["$local_name"]="$upstream_name"
    done <"$mapfile"
  fi
}

# Resolve upstream sample path: check exact match first, then alias map
resolve_upstream_sample() {
  local basename="$1"
  local exact="${UPSTREAM_DIR}/${basename}.sample"
  if [[ -f "$exact" ]]; then
    printf '%s' "$exact"
    return 0
  fi

  # Check alias map
  local mapped="${UPSTREAM_MAP[$basename]:-}"
  if [[ -n "$mapped" ]]; then
    local alias_path="${UPSTREAM_DIR}/${mapped}.sample"
    if [[ -f "$alias_path" ]]; then
      printf '%s' "$alias_path"
      return 0
    fi
  fi

  # Some multi-domain setups tag per-domain vhost files with an extra
  # domain segment (e.g. app.subdomain.example-tld.conf) so several
  # domains can share one proxy-confs tree. If the exact/aliased name
  # has no match, strip that middle segment and retry once so
  # domain-tagged vhosts still match the domain-agnostic upstream sample.
  local norm=""
  if [[ "$basename" =~ ^(.+)\.[^.]+\.conf$ ]]; then
    norm="${BASH_REMATCH[1]}.conf"
  fi
  if [[ -n "$norm" && "$norm" != "$basename" && -f "${UPSTREAM_DIR}/${norm}.sample" ]]; then
    printf '%s' "${UPSTREAM_DIR}/${norm}.sample"
    return 0
  fi

  return 1
}

# --- Fuzzy match for unmatched configs ---
# Accumulate unmatched configs for fuzzy reporting
declare -a UNMATCHED_CONFIGS=()

fuzzy_match_report() {
  if [[ ${#UNMATCHED_CONFIGS[@]} -eq 0 ]]; then
    return
  fi

  local fuzzy_body=""
  local fuzzy_count=0

  for conf_path in "${UNMATCHED_CONFIGS[@]}"; do
    local bn
    bn="$(basename "$conf_path")"
    # Extract service name (strip .subdomain/.subfolder.conf)
    local svc
    svc="$(printf '%s' "$bn" | sed 's/\.\(subdomain\|subfolder\)\.conf$//')"

    # Skip very short names (risk of false positives)
    [[ ${#svc} -lt 3 ]] && continue

    # Search upstream samples for partial match
    local matches
    matches="$(find "${UPSTREAM_DIR}" -maxdepth 1 -name '*.sample' -print0 2>/dev/null \
      | xargs -0 -I {} basename {} .sample \
      | grep -i "$svc" \
      | head -5 \
      | tr '\n' ', ' \
      | sed 's/,$//')"

    if [[ -n "$matches" ]]; then
      fuzzy_body+="| \`${bn}\` | ${matches} |"$'\n'
      fuzzy_count=$((fuzzy_count + 1))
    fi
  done

  if [[ $fuzzy_count -gt 0 && "$OUTPUT_JSON" == "false" ]]; then
    printf '\n## Potential Upstream Matches (Fuzzy)\n\n'
    printf 'These configs have no exact upstream match but their service name partially matches upstream samples.\n'
    printf $'Add confirmed mappings to `upstream-map.conf` (next to this script) to enable diff tracking.\n\n'
    printf '| Our Config | Possible Upstream |\n'
    printf '|---|---|\n'
    printf '%s' "$fuzzy_body"
    printf '\n'
  fi
}

# --- Known customization patterns ---
# Returns 0 if the diff line is a known customization that should be filtered.
# Called with a direction parameter: "removed" for - lines, "added" for + lines.
is_known_customization() {
  local line="$1"
  local direction="$2" # "removed" or "added"

  # Strip leading diff marker (+/-) and whitespace for matching
  local content
  content="${line#[+-]}"
  content="${content#"${content%%[![:space:]]*}"}"
  content="${content%"${content##*[![:space:]]}"}"

  # Empty or comment-only lines — always skip
  [[ -z "$content" ]] && return 0
  [[ "$content" =~ ^# ]] && return 0

  # --- Patterns for ADDED lines (+ lines = our customizations, always skip) ---
  if [[ "$direction" == "added" ]]; then
    return 0
  fi

  # --- Patterns for REMOVED lines (- lines = upstream content we might be missing) ---
  # Filter upstream template boilerplate and directive types most SWAG
  # users customize. Genuinely novel directive types still get caught.

  # server_name (upstream uses wildcards like app.*, users set specific domains)
  [[ "$content" =~ ^server_name[[:space:]] ]] && return 0

  # Upstream auth boilerplate (commented-out options stripped when enabling specific auth)
  [[ "$content" =~ ^#include.*/config/nginx/(ldap|authelia|authentik|tinyauth) ]] && return 0
  [[ "$content" =~ ^#auth_basic ]] && return 0
  [[ "$content" =~ ^auth_basic[[:space:]] ]] && return 0
  [[ "$content" =~ ^auth_basic_user_file ]] && return 0

  # Structural tokens (braces, location blocks)
  [[ "$content" == "}" ]] && return 0
  [[ "$content" == "{" ]] && return 0
  [[ "$content" =~ ^location[[:space:]] ]] && return 0

  # listen directives (QUIC variants)
  [[ "$content" =~ ^listen[[:space:]] ]] && return 0

  # Standard includes
  [[ "$content" =~ include.*/config/nginx/ssl\.conf ]] && return 0
  [[ "$content" =~ include.*/config/nginx/proxy\.conf ]] && return 0
  [[ "$content" =~ include.*/config/nginx/resolver\.conf ]] && return 0

  # set $upstream_* (app, port, proto — always customized)
  [[ "$content" =~ ^set[[:space:]]+\$upstream_ ]] && return 0

  # proxy_pass (standard form always follows set directives)
  [[ "$content" =~ ^proxy_pass[[:space:]] ]] && return 0

  # client_max_body_size (users customize values)
  [[ "$content" =~ ^client_max_body_size[[:space:]] ]] && return 0

  # Proxy tuning directives
  [[ "$content" =~ ^proxy_redirect[[:space:]] ]] && return 0
  [[ "$content" =~ ^proxy_buffering[[:space:]] ]] && return 0
  [[ "$content" =~ ^proxy_buffer ]] && return 0
  [[ "$content" =~ ^proxy_busy_buffers_size ]] && return 0

  # proxy_set_header (users add/remove various headers)
  [[ "$content" =~ ^proxy_set_header[[:space:]] ]] && return 0

  # return / rewrite (routing customizations)
  [[ "$content" =~ ^return[[:space:]] ]] && return 0
  [[ "$content" =~ ^rewrite[[:space:]] ]] && return 0

  # Not a known customization — flag it
  return 1
}

# --- Version comparison ---
# Extracts version string from config file (## Version YYYY/MM/DD)
get_version() {
  local file="$1"
  grep -oP '^## Version \K\d{4}/\d{2}/\d{2}' "$file" 2>/dev/null || printf "unknown"
}

# Compare version strings (YYYY/MM/DD format).
# Prints: "equal", "newer" (v1 > v2), "older" (v1 < v2), or "unknown"
compare_versions() {
  local v1="$1" v2="$2"
  if [[ "$v1" == "unknown" || "$v2" == "unknown" ]]; then
    printf "unknown"
    return
  fi
  if [[ "$v1" == "$v2" ]]; then
    printf "equal"
  elif [[ "$v1" > "$v2" ]]; then
    printf "newer"
  else
    printf "older"
  fi
}

# --- Detect redirect-only configs (no proxy_pass; only return 30x) ---
is_redirect_only() {
  local conf="$1"
  # Has return 301 or 302 directive
  grep -qE '^\s*return\s+30[12]\b' "$conf" || return 1
  # And does NOT have proxy_pass or set $upstream_*
  # shellcheck disable=SC2016  # regex pattern; $ is literal in grep, not shell expansion
  if grep -qE '^\s*proxy_pass\b|^\s*set\s+\$upstream_' "$conf"; then
    return 1
  fi
  return 0
}

# --- Process a single config ---
process_config() {
  local conf="$1"
  local basename
  basename="$(basename "$conf")"
  local server_dir
  server_dir="$(basename "$(dirname "$(dirname "$conf")")")"
  local conf_dir_name
  conf_dir_name="$(basename "$(dirname "$conf")")"

  TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

  # Skip redirect-only configs (no upstream to compare; intentional legacy 301s)
  if is_redirect_only "$conf"; then
    TOTAL_REDIRECT=$((TOTAL_REDIRECT + 1))
    return 0
  fi

  # Resolve upstream sample (exact match or alias map)
  local sample
  if ! sample="$(resolve_upstream_sample "$basename")"; then
    TOTAL_NO_UPSTREAM=$((TOTAL_NO_UPSTREAM + 1))
    UNMATCHED_CONFIGS+=("$conf")
    return 0
  fi

  # Get versions
  local local_version upstream_version version_cmp
  local_version="$(get_version "$conf")"
  upstream_version="$(get_version "$sample")"
  version_cmp="$(compare_versions "$local_version" "$upstream_version")"

  # Run diff (upstream is "old", local is "new")
  local raw_diff
  raw_diff="$(diff -u "$sample" "$conf" 2>/dev/null || true)"

  # No diff at all — identical
  if [[ -z "$raw_diff" ]]; then
    TOTAL_CLEAN=$((TOTAL_CLEAN + 1))
    return 0
  fi

  # Classify changed lines — only - lines (upstream content we might be missing) are actionable
  local has_actionable=false

  while IFS= read -r line; do
    # Skip diff headers
    [[ "$line" =~ ^--- ]] && continue
    [[ "$line" =~ ^\+\+\+ ]] && continue
    [[ "$line" =~ ^@@ ]] && continue

    # Determine direction
    if [[ "$line" =~ ^\- ]]; then
      if ! is_known_customization "$line" "removed"; then
        has_actionable=true
        break
      fi
    elif [[ "$line" =~ ^\+ ]]; then
      # + lines are our additions — always skip for actionable detection
      continue
    fi
  done <<<"$raw_diff"

  if [[ "$has_actionable" == "false" ]]; then
    if [[ "$version_cmp" == "newer" ]]; then
      TOTAL_FORKED=$((TOTAL_FORKED + 1))
    else
      TOTAL_CLEAN=$((TOTAL_CLEAN + 1))
    fi
    return 0
  fi

  # We have actionable changes
  TOTAL_ACTIONABLE=$((TOTAL_ACTIONABLE + 1))

  local version_note=""
  case "$version_cmp" in
    older)
      version_note=" — upstream updated (local: ${local_version}, upstream: ${upstream_version})"
      ;;
    newer)
      version_note=" — forked (local: ${local_version}, upstream: ${upstream_version})"
      ;;
    unknown)
      version_note=" — version unknown"
      ;;
  esac

  # Build filtered diff — show only hunks with actionable - lines
  local filtered_diff
  filtered_diff="$(build_filtered_diff "$raw_diff")"

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    local json_entry
    json_entry="$(
      cat <<JSONEOF
{
  "config": "${basename}",
  "server": "${server_dir}",
  "dir": "${conf_dir_name}",
  "local_version": "${local_version}",
  "upstream_version": "${upstream_version}",
  "version_status": "${version_cmp}",
  "has_actionable": true,
  "diff": $(printf '%s' "$filtered_diff" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""')
}
JSONEOF
    )"
    if [[ -n "$JSON_ENTRIES" ]]; then
      JSON_ENTRIES+=","$'\n'
    fi
    JSON_ENTRIES+="$json_entry"
  else
    MARKDOWN_BODY+="### ${basename} (${server_dir}/${conf_dir_name})${version_note}"$'\n\n'
    MARKDOWN_BODY+='```diff'$'\n'
    MARKDOWN_BODY+="${filtered_diff}"$'\n'
    MARKDOWN_BODY+='```'$'\n\n'
  fi
}

# Build a filtered diff showing only hunks that contain actionable removed lines
build_filtered_diff() {
  local raw_diff="$1"

  local current_hunk=""
  local hunk_header=""
  local hunk_has_actionable=false
  local output=""

  while IFS= read -r line; do
    # Skip file headers
    [[ "$line" =~ ^--- ]] && continue
    [[ "$line" =~ ^\+\+\+ ]] && continue

    # New hunk starts
    if [[ "$line" =~ ^@@ ]]; then
      # Flush previous hunk if actionable
      if [[ "$hunk_has_actionable" == "true" && -n "$current_hunk" ]]; then
        output+="${hunk_header}"$'\n'
        output+="${current_hunk}"
      fi
      hunk_header="$line"
      current_hunk=""
      hunk_has_actionable=false
      continue
    fi

    # Accumulate hunk lines
    current_hunk+="${line}"$'\n'

    # Only - lines can be actionable (upstream content we're missing)
    if [[ "$line" =~ ^\- ]]; then
      if ! is_known_customization "$line" "removed"; then
        hunk_has_actionable=true
      fi
    fi
  done <<<"$raw_diff"

  # Flush last hunk
  if [[ "$hunk_has_actionable" == "true" && -n "$current_hunk" ]]; then
    output+="${hunk_header}"$'\n'
    output+="${current_hunk}"
  fi

  printf '%s' "$output"
}

# Pick the config root to scan: explicit --config-root, else the first of a
# few conventional locations relative to REPO_ROOT (the parent of this
# script's directory).
resolve_config_root() {
  if [[ -n "$CONFIG_ROOT" ]]; then
    printf '%s' "$CONFIG_ROOT"
    return 0
  fi

  local candidate
  for candidate in "config/servers" "servers" "proxy-confs" "."; do
    if [[ -d "${REPO_ROOT}/${candidate}" ]]; then
      printf '%s' "${REPO_ROOT}/${candidate}"
      return 0
    fi
  done

  printf '%s' "$REPO_ROOT"
}

# --- Main ---
main() {
  parse_args "$@"
  load_upstream_map

  local servers_root
  servers_root="$(resolve_config_root)"

  if [[ ! -d "$servers_root" ]]; then
    printf "Error: config root does not exist: %s\n" "$servers_root" >&2
    exit 2
  fi

  local -a find_expr=()
  if [[ ${#DOMAINS[@]} -gt 0 ]]; then
    find_expr+=(-type f "(")
    local first=true domain
    for domain in "${DOMAINS[@]}"; do
      if [[ "$first" == true ]]; then
        first=false
      else
        find_expr+=(-o)
      fi
      find_expr+=(-path "*/${domain}/*.conf")
    done
    find_expr+=(")")
  else
    find_expr+=(-type f -name "*.conf")
  fi

  local configs=()
  while IFS= read -r -d '' conf; do
    configs+=("$conf")
  done < <(find "$servers_root" "${find_expr[@]}" -print0 2>/dev/null | sort -z)

  if [[ ${#configs[@]} -eq 0 ]]; then
    printf "No configs found to check under %s.\n" "$servers_root" >&2
    exit 2
  fi

  # Process each config
  for conf in "${configs[@]}"; do
    process_config "$conf"
  done

  # Output results
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    cat <<JSONEOF
{
  "summary": {
    "total_checked": ${TOTAL_CHECKED},
    "no_upstream": ${TOTAL_NO_UPSTREAM},
    "forked": ${TOTAL_FORKED},
    "clean": ${TOTAL_CLEAN},
    "actionable": ${TOTAL_ACTIONABLE}
  },
  "configs": [
${JSON_ENTRIES}
  ]
}
JSONEOF
  else
    # Markdown output
    if [[ $TOTAL_ACTIONABLE -gt 0 ]]; then
      printf '# SWAG Upstream Config Changes\n\n'
      printf '| Metric | Count |\n'
      printf '|--------|-------|\n'
      printf '| Configs checked | %d |\n' "$TOTAL_CHECKED"
      printf '| No upstream sample | %d |\n' "$TOTAL_NO_UPSTREAM"
      printf '| Forked (local version newer) | %d |\n' "$TOTAL_FORKED"
      printf '| Clean (customizations only) | %d |\n' "$TOTAL_CLEAN"
      printf '| **Actionable changes** | **%d** |\n\n' "$TOTAL_ACTIONABLE"
      printf '%s' "$MARKDOWN_BODY"
    else
      printf 'All %d configs are in sync (customizations filtered).\n' "$TOTAL_CHECKED"
      if [[ $TOTAL_FORKED -gt 0 ]]; then
        printf '  (%d forked, %d clean, %d without upstream sample)\n' \
          "$TOTAL_FORKED" "$TOTAL_CLEAN" "$TOTAL_NO_UPSTREAM"
      fi
    fi

    # Append fuzzy match suggestions for unmatched configs
    fuzzy_match_report
  fi

  # Exit code
  if [[ $TOTAL_ACTIONABLE -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
