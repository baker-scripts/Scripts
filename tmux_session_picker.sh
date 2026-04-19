#!/bin/bash
# Tmux Session Picker — auto-creates and displays sessions on SSH login
# Source this file at the END of .bashrc or .zshrc (compatible with both)
#
# Setup:
#   1. Place at ~/.tmux_session_picker.sh
#   2. Add to .bashrc or .zshrc: [[ -f ~/.tmux_session_picker.sh ]] && source ~/.tmux_session_picker.sh
#
# Features:
#   - Auto-creates sessions for configured directory paths
#   - Displays a table with session name, window count, running processes, and last access
#   - Detects notable processes via pstree (customizable)
#   - Supports attach by number, by name, creating new sessions, or skipping tmux
#   - Re-displays after creating new sessions
#   - Only runs on interactive SSH login (not inside tmux, not with NOTMUX=1)
#
# Configuration:
#   Edit _TMUX_SESS_PAIRS below to customize pre-created sessions.
#   Format: "session_name=/path/to/directory"
#
# Display:
#   #    SESSION          WIN PROCESSES            LAST ACCESS
#   ---  ---------------- --- -------------------- -------------------
#   1)   dockergit *        1 claude               just now
#   2)   docs               1 vim                  5m ago
#   3)   home               1 -                    2h ago
#
#   [1-3] attach  [n] new  [s] skip
#   >

# === Configuration ===
# Pre-created sessions: "name=/path" pairs. Sessions created only if path exists.
_TMUX_SESS_PAIRS=(
  "project=/path/to/project"
  "config=/path/to/config"
  "home=$HOME"
)

# Notable processes to detect via pstree
_TMUX_NOTABLE_PROCS=(claude vim nvim docker node python pwsh htop)

# === Implementation ===
if command -v tmux >/dev/null 2>&1 \
  && [[ $- == *i* ]] && [[ -n "$SSH_TTY" ]] && [[ -z "$TMUX" ]] && [[ -z "$NOTMUX" ]]; then

  # Create sessions for valid paths
  for _pair in "${_TMUX_SESS_PAIRS[@]}"; do
    _sess_name="${_pair%%=*}"
    _sess_path="${_pair#*=}"
    if [[ -d "$_sess_path" ]] && ! tmux has-session -t "$_sess_name" 2>/dev/null; then
      tmux new-session -d -s "$_sess_name" -c "$_sess_path"
    fi
  done

  # Detect notable processes in a tmux session via pstree
  _tmux_procs() {
    local sid=$1
    local pids procs=""
    pids=$(tmux list-panes -t "$sid" -F '#{pane_pid}' 2>/dev/null)
    for _pid in $pids; do
      local tree
      tree=$(pstree -A "$_pid" 2>/dev/null) || continue
      for _proc in "${_TMUX_NOTABLE_PROCS[@]}"; do
        [[ "$tree" == *"$_proc"* ]] && procs="${procs:+$procs, }$_proc"
      done
    done
    printf '%s' "${procs:--}"
  }

  # Relative time since last activity in a session
  _tmux_age() {
    local sid=$1
    local now age_s
    now=$(date +%s)
    local last
    last=$(tmux display-message -t "$sid" -p '#{session_activity}' 2>/dev/null) || {
      printf '?'
      return
    }
    age_s=$((now - last))
    if ((age_s < 60)); then
      printf 'just now'
    elif ((age_s < 3600)); then
      printf '%dm ago' "$((age_s / 60))"
    elif ((age_s < 86400)); then
      printf '%dh ago' "$((age_s / 3600))"
    else printf '%dd ago' "$((age_s / 86400))"; fi
  }

  # Session picker with loop (re-displays after creating new sessions)
  while true; do
    _tmux_names=()
    _tmux_count=0

    printf '\n'
    printf '#    %-16s %s %-20s %s\n' 'SESSION' 'WIN' 'PROCESSES' 'LAST ACCESS'
    printf -- '---  %-16s %s %-20s %s\n' '----------------' '---' '--------------------' '-------------------'

    while IFS='|' read -r _sname _swins _satt; do
      ((_tmux_count++))
      _tmux_names[_tmux_count]="$_sname"
      _label="${_sname}${_satt:+ *}"
      _procs=$(_tmux_procs "$_sname")
      _age=$(_tmux_age "$_sname")
      printf '%-4s %-16s %3s %-20s %s\n' "${_tmux_count})" "$_label" "$_swins" "$_procs" "$_age"
    done < <(tmux list-sessions -F '#{session_name}|#{session_windows}|#{?session_attached,*,}' 2>/dev/null)

    printf '\n[1-%d] attach  [n] new  [s] skip\n' "$_tmux_count"
    printf '> '
    read -r _choice

    case "$_choice" in
      s | skip)
        break
        ;;
      n | new)
        printf 'Session name: '
        read -r _new_name
        printf 'Start directory: '
        read -r _new_path
        _new_path="${_new_path:-$HOME}"
        if [[ -n "$_new_name" ]] && [[ -d "$_new_path" ]]; then
          tmux new-session -d -s "$_new_name" -c "$_new_path"
        else
          printf 'Invalid name or path.\n' >&2
          continue
        fi
        ;;
      [0-9]*)
        if ((_choice >= 1 && _choice <= _tmux_count)); then
          exec tmux attach -t "${_tmux_names[_choice]}"
        else
          printf 'Invalid selection.\n' >&2
        fi
        ;;
      "") ;;
      *)
        # Try as session name directly
        if tmux has-session -t "$_choice" 2>/dev/null; then
          exec tmux attach -t "$_choice"
        else
          printf 'Unknown session: %s\n' "$_choice" >&2
        fi
        ;;
    esac
  done

  unset _pair _sess_name _sess_path _tmux_names _tmux_count _sname _swins _satt _choice _new_name _new_path _label _procs _age _pid _proc
fi
