# Scripts

Utility scripts for selfhosted infrastructure management.

## Contents
- `nextdns_sync.py` — Syncs NextDNS profile settings (allowlist, denylist, security, privacy)
- `.bash_aliases` — Shell aliases for common operations
- `docker_aliases.sh` — Docker Compose wrapper with 1Password secret resolution, fzf integration, Dozzle group management, and tab completion
- `tmux_session_picker.sh` — Auto-creates tmux sessions on SSH login with process detection and last-access display

## Conventions
- Bash scripts: POSIX-compatible where possible
- Python scripts: Use system python or project venv
- No PII: No domains, emails, IPs, or site-specific paths in committed code
- All scripts must pass shellcheck
