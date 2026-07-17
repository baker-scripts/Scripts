# Scripts

[![ShellCheck](https://github.com/baker-scripts/Scripts/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/baker-scripts/Scripts/actions/workflows/shellcheck.yml)

Utility scripts for selfhosted infrastructure management.

## Contents

- `nextdns_sync.py` — Syncs NextDNS profile settings (allowlist, denylist, security, privacy)
- `.bash_aliases` — Shell aliases for common operations
- `docker_aliases.sh` — Docker Compose wrapper with 1Password secret resolution, fzf integration, Dozzle group management, and tab completion
- `tmux_session_picker.sh` — Auto-creates tmux sessions on SSH login with a table showing running processes and last access time
- `projectivy-deploy.sh` — Installs Projectivy Launcher on Android TV over ADB, selects it as home, and supports configuration backup/restore
- `androidtv-app-sync.sh` — Applies checksum-pinned APK updates to reachable Android TV devices without downgrading packages

`androidtv-app-sync.sh` can share one manifest between a timer and manual runs. Keep Play-managed
apps in audit-only mode and pin every sideloaded APK by version and checksum:

```text
# package<TAB>minimum-versionCode<TAB>source<TAB>SHA-256
com.spocky.projengmenu	1	managed	-
com.plexapp.android	1	managed	-
com.google.android.youtube.tvunplugged	1	managed	-
ca.devmesh.seerrtv	1	managed	-
smarttube.package.from.approved.apk	123	https://example.invalid/smarttube.apk	<64-character-sha256>
ca.devmesh.seerrtv	123	https://example.invalid/seerrtv.apk	<64-character-sha256>
```

Use the managed SeerrTV row on Google TV/Shield manifests and the pinned APK row on Fire TV
manifests. SmartTube is always a pinned sideload row. Obtain the package and version from the exact
approved APK (`aapt dump badging app.apk`) rather than assuming stable, beta, and F-Droid IDs match.

The ADB client key must be stored outside an ephemeral container. If a device reports
`unauthorized`, approve that persistent key once on the TV; never rotate keys as a retry strategy.

## Contributors

<a href="https://github.com/baker-scripts/Scripts/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=baker-scripts/Scripts" alt="Contributors" />
</a>

## Disclaimer

These scripts are provided as-is with no warranty. Always review scripts before running them on your system and test in a non-production environment first. The authors are not responsible for any issues resulting from their use.

## License

[MIT](LICENSE)
