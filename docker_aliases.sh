#!/bin/bash
# Docker Compose Aliases — portable across all servers
# Source this file in .bashrc or .zshrc (compatible with both)
#
# Setup:
#   1. Place this file at ~/.docker_aliases.sh
#   2. Add to .bashrc or .zshrc: [[ -f ~/.docker_aliases.sh ]] && source ~/.docker_aliases.sh
#   3. Ensure your compose directory has a .env with COMPOSE_FILE set
#
# Features:
#   - Works from any directory (no cd side effects)
#   - Resolves 1Password op:// secrets only for commands that need them
#   - Tab completion for service names (bash and zsh)
#   - fzf integration for interactive service selection (optional)
#   - Dozzle group management via container labels

# Auto-detect compose directory — customize these paths for your setup
if [[ -d "/opt/dockergit" ]] && [[ -f "/opt/dockergit/.env" ]]; then
  DOCKER_GIT_DIR="/opt/dockergit"
elif [[ -d "$HOME/.docker" ]] && [[ -f "$HOME/.docker/.env" ]]; then
  DOCKER_GIT_DIR="$HOME/.docker"
else
  DOCKER_GIT_DIR=""
fi

# Colors
_dc_red() { printf '\033[0;31m%s\033[0m\n' "$1"; }
_dc_green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
_dc_yellow() { printf '\033[0;33m%s\033[0m\n' "$1"; }
_dc_blue() { printf '\033[0;34m%s\033[0m\n' "$1"; }

# Initialize compose environment (no cd — uses --project-directory instead)
_dc_init() {
  [[ -z "$DOCKER_GIT_DIR" ]] && { _dc_red "No compose directory found"; return 1; }
  [[ -d "$DOCKER_GIT_DIR" ]] || { _dc_red "Directory not found: $DOCKER_GIT_DIR"; return 1; }
  if [[ -z "$COMPOSE_FILE" ]] && [[ -f "$DOCKER_GIT_DIR/.env" ]]; then
    local raw
    raw=$(grep '^COMPOSE_FILE=' "$DOCKER_GIT_DIR/.env" 2>/dev/null | cut -d= -f2-)
    # Convert relative paths to absolute (relative to DOCKER_GIT_DIR)
    # Use parameter expansion to split on ':' (works in both bash and zsh)
    local abs=""
    local IFS=':'
    read -ra _cf_parts <<< "$raw"
    for f in "${_cf_parts[@]}"; do
      [[ "$f" != /* ]] && f="$DOCKER_GIT_DIR/$f"
      abs="${abs:+$abs:}$f"
    done
    export COMPOSE_FILE="$abs"
  fi
}

# Commands that need op:// secrets resolved (container runtime)
_dc_needs_secrets() {
  case "$1" in
    up|exec|run|create) return 0 ;;
    *) return 1 ;;
  esac
}

# Plain docker compose with project directory
_dc_plain() {
  docker compose --project-directory "$DOCKER_GIT_DIR" "$@"
}

# Compose wrapper — only uses op run for commands that need secrets
_dc_compose() {
  if _dc_needs_secrets "$1" && command -v op &>/dev/null && grep -q 'op://' "$DOCKER_GIT_DIR/.env" 2>/dev/null; then
    op run --env-file "$DOCKER_GIT_DIR/.env" -- docker compose --project-directory "$DOCKER_GIT_DIR" "$@"
  else
    _dc_plain "$@"
  fi
}

# Wait for container to be healthy
_wait_healthy() {
  local svc=$1 timeout=${2:-60}
  _dc_blue "Waiting for $svc to be healthy (max ${timeout}s)..."
  local status
  for ((i=0; i<timeout; i++)); do
    status=$(docker inspect --format='{{.State.Health.Status}}' "$svc" 2>/dev/null)
    case "$status" in
      healthy) _dc_green "$svc is healthy"; return 0 ;;
      unhealthy) _dc_red "$svc is unhealthy"; return 1 ;;
    esac
    sleep 1
  done
  _dc_yellow "$svc health check timed out"
  return 1
}

# Confirm destructive action (bash/zsh compatible)
_dc_confirm() {
  local msg=${1:-"Proceed?"}
  local REPLY
  printf "%s" "$(_dc_yellow "$msg [y/N]: ")"
  read -r -k 1 REPLY 2>/dev/null || read -r -n 1 REPLY
  echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

# Get services by Dozzle group label
_dc_group() {
  local group=$1
  _dc_init || return 1
  _dc_plain config 2>/dev/null | \
    awk -v grp="$group" '
      /^  [a-z].*:$/ { svc=$1; gsub(/:$/,"",svc) }
      /dozzle\.group:/ && $2 == grp { print svc }
    ' | tr '\n' ' '
}

# Clear any conflicting aliases from oh-my-zsh docker-compose plugin
unalias dc dcdown dcup dcpull dcrestart dcps dclogs dcexec dcconfig dcstats dctop dcq 2>/dev/null
unalias dcrecreate dcrs dcprune dcdf dcinfo dcfiles dchelp 2>/dev/null

# Core wrapper
function dc {
  _dc_init || return 1
  _dc_compose "$@"
}

# Full Stack Commands
function dcdown {
  _dc_init || return 1
  if [[ "$1" != "-f" ]] && [[ "$1" != "--force" ]]; then
    _dc_confirm "Stop ALL containers?" || { _dc_yellow "Cancelled"; return 0; }
  else
    shift
  fi
  _dc_blue "Stopping all services..."
  _dc_compose down "$@"
  _dc_green "All services stopped"
}

function dcpull {
  _dc_init || return 1
  local images
  # Use _dc_plain (no op run) — pulling images doesn't need secrets
  if [[ $# -eq 0 ]]; then
    images=$(_dc_plain config --images 2>/dev/null | sort -u)
    # Include images from standalone compose files (e.g. compose.*.yml)
    local server_dir
    server_dir=$(echo "$COMPOSE_FILE" | tr ':' '\n' | head -1 | xargs dirname)
    if [[ -n "$server_dir" ]]; then
      for f in "$server_dir"/compose.*.yml; do
        [[ -f "$f" ]] || continue
        [[ "$COMPOSE_FILE" == *"$(basename "$f")"* ]] && continue
        local extra
        extra=$(docker compose -f "$f" config --images 2>/dev/null)
        [[ -n "$extra" ]] && images=$(printf '%s\n%s' "$images" "$extra" | sort -u)
      done
    fi
  else
    images=$(_dc_plain config --images "$@" 2>/dev/null | sort -u)
  fi
  local total
  total=$(echo "$images" | wc -l)
  local count=0 failed=0
  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    ((count++))
    local short="${img##*/}"
    _dc_blue "[$count/$total] Pulling ${short}..."
    if ! docker pull --quiet "$img"; then
      ((failed++))
      _dc_red "Failed to pull $img"
    fi
  done <<< "$images"
  if (( failed > 0 )); then
    _dc_yellow "Pull complete ($total images, $failed failed)"
  else
    _dc_green "Pull complete ($total unique images)"
  fi
}

function dcup {
  _dc_init || return 1
  local services
  if [[ $# -eq 0 ]]; then
    services=$(_dc_compose config --services 2>/dev/null)
    _dc_blue "Starting all services..."
    _dc_compose up -d
  else
    services="$*"
    local total=$(echo "$services" | wc -w)
    local count=0
    for svc in $services; do
      ((count++))
      _dc_blue "[$count/$total] Starting $svc..."
      _dc_compose up -d "$svc"
    done
  fi
  _dc_green "Services started"
}

function dcrestart {
  if [[ "$1" == "-f" ]] || [[ "$1" == "--force" ]]; then
    shift
  else
    _dc_confirm "Full restart (down → pull → up)?" || { _dc_yellow "Cancelled"; return 0; }
  fi
  if [[ $# -gt 0 ]]; then
    _dc_yellow "dcrestart operates on the full stack. Use 'dcrs <service>' for single-service restart."
    return 1
  fi
  dcdown -f && dcpull && dcup
}

# Monitoring Commands
function dcps {
  _dc_init || return 1
  _dc_compose ps "$@"
}

function dclogs {
  _dc_init || return 1
  _dc_compose logs -f "$@"
}

function dcexec {
  _dc_init || return 1
  _dc_compose exec "$@"
}

function dcconfig {
  _dc_init || return 1
  _dc_compose config "$@"
}

function dcstats {
  docker stats "$@"
}

function dctop {
  _dc_init || return 1
  _dc_compose top "$@"
}

# Quick status overview
function dcq {
  _dc_init || return 1
  local running=$(_dc_compose ps --status running -q 2>/dev/null | wc -l)
  local stopped=$(_dc_compose ps --status exited -q 2>/dev/null | wc -l)
  local unhealthy=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)
  echo "Running: $(_dc_green "$running") | Stopped: $(_dc_yellow "$stopped") | Unhealthy: $(_dc_red "$unhealthy")"
}

# Dozzle Group Commands (dynamic from container labels)
function grpdown {
  local grp=$1; shift
  _dc_init || return 1
  local services=$(_dc_group "$grp")
  [[ -z "$services" ]] && { _dc_red "No services in group: $grp"; return 1; }
  _dc_blue "Stopping $grp: $services"
  _dc_compose stop $services "$@"
  _dc_green "$grp stopped"
}

function grpup {
  local grp=$1; shift
  _dc_init || return 1
  local services=$(_dc_group "$grp")
  [[ -z "$services" ]] && { _dc_red "No services in group: $grp"; return 1; }
  _dc_blue "Starting $grp: $services"
  _dc_compose up -d $services "$@"
  _dc_green "$grp started"
}

function grplogs {
  local grp=$1; shift
  _dc_init || return 1
  local services=$(_dc_group "$grp")
  [[ -z "$services" ]] && { _dc_red "No services in group: $grp"; return 1; }
  _dc_compose logs -f $services "$@"
}

function grpps {
  local grp=$1; shift
  _dc_init || return 1
  local services=$(_dc_group "$grp")
  [[ -z "$services" ]] && { _dc_red "No services in group: $grp"; return 1; }
  _dc_compose ps $services "$@"
}

function grprestart {
  local grp=$1; shift
  _dc_init || return 1
  local services=$(_dc_group "$grp")
  [[ -z "$services" ]] && { _dc_red "No services in group: $grp"; return 1; }
  _dc_blue "Restarting $grp: $services"
  _dc_compose restart $services "$@"
  _dc_green "$grp restarted"
}

# List available Dozzle groups
function grplist {
  _dc_init || return 1
  _dc_blue "Available Dozzle groups:"
  _dc_plain config 2>/dev/null | grep "dozzle\.group:" | awk '{print $2}' | sort -u
}

# Show services in a group
function grpshow {
  local grp=$1
  _dc_init || return 1
  local services=$(_dc_group "$grp")
  [[ -z "$services" ]] && { _dc_red "No services in group: $grp"; return 1; }
  echo "$grp: $services"
}

# Utility Commands
function dcrecreate {
  _dc_init || return 1
  _dc_compose up -d --force-recreate "$@"
}

function dcrs {
  _dc_init || return 1
  _dc_compose restart "$@"
}

function dcprune {
  docker system prune "$@"
}

function dcdf {
  docker system df "$@"
}

function dcinfo {
  _dc_init || return 1
  echo "Docker Compose Configuration"
  echo "============================="
  echo "Directory: $DOCKER_GIT_DIR"
  echo "Compose files: ${COMPOSE_FILE//:/ }"
  echo ""
  echo "Service count: $(_dc_plain config --services 2>/dev/null | wc -l)"
  echo ""
  dcq
}

function dcfiles {
  _dc_init || return 1
  echo "Compose files in use:"
  echo "${COMPOSE_FILE//:/$'\n'}"
}

function dchelp {
  cat << 'EOF'
Docker Compose Aliases Quick Reference
======================================

Full Stack:
  dc [cmd]        docker compose (with op run for secrets)
  dcdown [-f]     docker compose down (confirm unless -f)
  dcpull          docker pull (unique images, quiet, progress)
  dcup            docker compose up -d
  dcrestart [-f]  dcdown → dcpull → dcup

Monitoring:
  dcps            docker compose ps
  dcq             Quick status (running/stopped/unhealthy counts)
  dclogs [svc]    docker compose logs -f
  dcexec svc cmd  docker compose exec
  dcconfig        docker compose config
  dcstats         docker stats
  dctop           docker compose top

Dozzle Groups (dynamic from labels):
  grplist              List all Dozzle groups
  grpshow <group>      Show services in a group
  grp[up|down|logs|ps|restart] <group>  Generic group commands

Utility:
  dcrecreate svc  docker compose up -d --force-recreate
  dcrs svc        docker compose restart
  dcprune         docker system prune
  dcdf            docker system df
  dcinfo          Show config state + quick status
  dcfiles         List compose files in use

Interactive (requires fzf):
  dclogsi         Pick service to tail logs
  dcexeci         Pick service to exec into
  dcrsi           Pick service(s) to restart
  dcrecreatei     Pick service(s) to recreate
  dcupi           Pick service(s) to start
  dcdowni         Pick service(s) to stop
  dcpsi           Browse containers with log preview
  grpi            Pick group and show services
  grp[up|down|logs|ps]i  Pick group interactively

EOF
}

# Shell-specific completion
if [[ -n "$BASH_VERSION" ]]; then
  _dc_services() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local services
    [[ -z "$COMPOSE_FILE" ]] && [[ -f "$DOCKER_GIT_DIR/.env" ]] && \
      export COMPOSE_FILE=$(grep '^COMPOSE_FILE=' "$DOCKER_GIT_DIR/.env" 2>/dev/null | cut -d= -f2-)
    mapfile -t services < <(_dc_plain config --services 2>/dev/null)
    mapfile -t COMPREPLY < <(compgen -W "${services[*]}" -- "$cur")
  }
  complete -F _dc_services dclogs dcexec dcrecreate dcrs dc
elif [[ -n "$ZSH_VERSION" ]]; then
  _dc_services() {
    local services
    [[ -z "$COMPOSE_FILE" ]] && [[ -f "$DOCKER_GIT_DIR/.env" ]] && \
      export COMPOSE_FILE=$(grep '^COMPOSE_FILE=' "$DOCKER_GIT_DIR/.env" 2>/dev/null | cut -d= -f2-)
    services=(${(f)"$(_dc_plain config --services 2>/dev/null)"})
    _describe 'service' services
  }
  compdef _dc_services dclogs dcexec dcrecreate dcrs dc 2>/dev/null || true
fi

# FZF Integration (if available)
if command -v fzf &>/dev/null; then
  _dc_fzf_pick() {
    local multi=${1:-false}
    _dc_init || return 1
    local opts=""
    [[ "$multi" == "true" ]] && opts="-m"
    _dc_plain config --services 2>/dev/null | fzf $opts --height 40% --reverse --border --header "Select service(s)"
  }

  _dc_fzf_group() {
    _dc_init || return 1
    _dc_plain config 2>/dev/null | grep "dozzle\.group:" | awk '{print $2}' | sort -u | \
      fzf --height 40% --reverse --border --header "Select group"
  }

  function grpi { local grp; grp=$(_dc_fzf_group); [[ -n "$grp" ]] && grpshow "$grp"; }
  function grpupi { local grp; grp=$(_dc_fzf_group); [[ -n "$grp" ]] && grpup "$grp"; }
  function grpdowni { local grp; grp=$(_dc_fzf_group); [[ -n "$grp" ]] && grpdown "$grp"; }
  function grplogsi { local grp; grp=$(_dc_fzf_group); [[ -n "$grp" ]] && grplogs "$grp"; }
  function grppsi { local grp; grp=$(_dc_fzf_group); [[ -n "$grp" ]] && grpps "$grp"; }

  function dclogsi { local svc; svc=$(_dc_fzf_pick); [[ -n "$svc" ]] && dclogs "$svc"; }
  function dcexeci { local svc; svc=$(_dc_fzf_pick); [[ -n "$svc" ]] && dcexec "$svc" "${@:-bash}"; }
  function dcrsi {
    local svc; svc=$(_dc_fzf_pick true)
    [[ -n "$svc" ]] && while IFS= read -r s; do dcrs "$s"; done <<< "$svc"
  }
  function dcrecreatei {
    local svc; svc=$(_dc_fzf_pick true)
    [[ -n "$svc" ]] && while IFS= read -r s; do dcrecreate "$s"; done <<< "$svc"
  }
  function dcupi {
    local svc; svc=$(_dc_fzf_pick true)
    [[ -n "$svc" ]] && while IFS= read -r s; do dcup "$s"; done <<< "$svc"
  }
  function dcdowni {
    local svc; svc=$(_dc_fzf_pick true)
    [[ -n "$svc" ]] && { _dc_init || return 1; while IFS= read -r s; do _dc_compose stop "$s"; done <<< "$svc"; }
  }

  function dcpsi {
    _dc_init || return 1
    _dc_plain ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" | \
      fzf --header-lines=1 --height 60% --reverse --border \
          --preview 'docker logs --tail 20 {1}' \
          --preview-window=down:40%:wrap
  }
fi
