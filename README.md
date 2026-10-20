# Scripts

[![ShellCheck](https://github.com/baker-scripts/Scripts/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/baker-scripts/Scripts/actions/workflows/shellcheck.yml)
[![Pre-commit](https://github.com/baker-scripts/Scripts/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/baker-scripts/Scripts/actions/workflows/pre-commit.yml)

Utility scripts for selfhosted infrastructure: NextDNS profile sync, shell and Docker Compose aliases, a tmux login picker, and Android TV deployment over ADB.

| Script | Purpose |
| --- | --- |
| `nextdns_sync.py` | Copies allowlist, denylist, parental control, security, privacy, rewrites, and settings from a main NextDNS profile to other profiles |
| `.bash_aliases` | General shell, systemd, Docker, git, and navigation aliases |
| `docker_aliases.sh` | Docker Compose wrapper with 1Password secret resolution, fzf pickers, Dozzle group commands, and tab completion (bash and zsh) |
| `tmux_session_picker.sh` | On interactive SSH login, creates configured tmux sessions and shows a table of sessions, running processes, and last access |
| `projectivy-deploy.sh` | Installs Projectivy Launcher on an Android TV over ADB, sets it as home, and backs up or restores its configuration |
| `androidtv-app-sync.sh` | Updates APKs on a reachable Android TV from a manifest of pinned versions and SHA-256 checksums, never downgrading |

## Quick start

Shell scripts: source the aliases from `.bashrc` or `.zshrc`.

```bash
cp .bash_aliases ~/.bash_aliases
cp docker_aliases.sh ~/.docker_aliases.sh
cp tmux_session_picker.sh ~/.tmux_session_picker.sh
cat >> ~/.bashrc <<'RC'
[[ -f ~/.docker_aliases.sh ]] && source ~/.docker_aliases.sh
[[ -f ~/.tmux_session_picker.sh ]] && source ~/.tmux_session_picker.sh   # keep last
RC
```

Python script: `nextdns_sync.py` needs `requests`.

## Configuration

### nextdns_sync.py

| Variable | Purpose |
| --- | --- |
| `NEXTDNS_API_KEY` | NextDNS API key |
| `NEXTDNS_PROFILE_MAIN` | Source profile ID |
| `NEXTDNS_PROFILE_RPM`, `NEXTDNS_PROFILE_BETSY`, `NEXTDNS_PROFILE_LEONA`, `NEXTDNS_PROFILE_HURLEY`, `NEXTDNS_PROFILE_TAILNET` | Target profile IDs; unset ones are skipped |
| `NEXTDNS_SITE_SPECIFIC_REWRITES` | Comma-separated rewrite names that stay on Main and are not synced |

### docker_aliases.sh

Uses `/opt/dockergit` if it has a `.env`, otherwise `~/.docker`. That `.env` must set `COMPOSE_FILE`. Relative paths in it resolve against the compose directory. Commands that need secrets run through `op run --env-file`. Edit the detection block at the top of the script for other paths. Run `dchelp` for the command list.

### tmux_session_picker.sh

Edit `_TMUX_SESS_PAIRS` (`"name=/path"`, created only if the path exists) and `_TMUX_NOTABLE_PROCS` (detected with `pstree`). It runs only on interactive SSH logins outside tmux; set `NOTMUX=1` to skip it.

### Android TV scripts

| Variable | Default | Purpose |
| --- | --- | --- |
| `ADB_CONTAINER` | `androidtv-adb` | Running container used for `adb`; falls back to host `adb` |

Both scripts connect to `<device-host>:5555`. The ADB client key must persist outside an ephemeral container. If a device reports `unauthorized`, approve that key once on the TV; do not rotate keys as a retry.

## Usage

```bash
# NextDNS: sync | update | get | diff
python nextdns_sync.py diff
python nextdns_sync.py sync
python nextdns_sync.py get --profile <profile-id>
python nextdns_sync.py update    # push the TLD ban list to the main profile's security settings

# Projectivy Launcher
./projectivy-deploy.sh <device-host> [<apk-path>|--launcher-only|--backup <file>|--restore <file>]

# APK sync
./androidtv-app-sync.sh <device-host> <manifest.tsv>
```

`sync` refuses to run while DNS rebinding protection is enabled on Main, syncs those categories to the targets (the `nrd` security key stays per-profile), and checks that the Tailscale record resolves into `100.64.0.0/10` on each profile. Any error gives a nonzero exit code. Without an APK argument, `projectivy-deploy.sh` installs `projectivy.apk` from the script's directory.

### APK sync manifest

Tab-separated columns: package, minimum versionCode, source, SHA-256. Blank lines and `#` lines are ignored. Source `managed` with checksum `-` audits a Play-managed package without installing it. Any other source is an APK URL with its pinned checksum. Updates need a new pinned version and checksum; downgrades are refused.

```text
# package<TAB>minimum-versionCode<TAB>source<TAB>SHA-256
com.spocky.projengmenu	1	managed	-
com.plexapp.android	1	managed	-
com.google.android.youtube.tvunplugged	1	managed	-
ca.devmesh.seerrtv	1	managed	-
smarttube.package.from.approved.apk	123	https://example.invalid/smarttube.apk	<64-character-sha256>
```

Use the managed SeerrTV row on Google TV and Shield manifests and a pinned APK row on Fire TV manifests. SmartTube is always a pinned sideload row. Read the package and version from the approved APK (`aapt dump badging app.apk`); stable, beta, and F-Droid builds can use different IDs.

## Conventions

- Scripts pass ShellCheck and shfmt (pre-commit).
- No domains, emails, IPs, or site-specific paths in committed code.

## Contributing

Issues and pull requests welcome. See the [contributing guidelines](https://github.com/baker-scripts/.github/blob/main/CONTRIBUTING.md) and [open an issue](https://github.com/baker-scripts/Scripts/issues) to discuss larger changes.

## Disclaimer

Provided as-is with no warranty. Review scripts before running them and test outside production first.

## License

[MIT](LICENSE)
