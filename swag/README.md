# swag/upstream-diff.sh

Diffs your local [SWAG](https://github.com/linuxserver/docker-swag) nginx
proxy-conf files against upstream sample configs (e.g.
[linuxserver/reverse-proxy-confs](https://github.com/linuxserver/reverse-proxy-confs))
and reports only genuine upstream changes, filtering out the customizations
every SWAG user makes (domain names, auth blocks, proxy tuning, etc).

Common SWAG pain point: you customize a vhost once, upstream ships a fix or
new directive later, and you never notice because your file no longer
matches the sample byte-for-byte. This script filters the noise so a real
upstream change stands out.

## Usage

```bash
git clone --depth 1 https://github.com/linuxserver/reverse-proxy-confs.git /tmp/upstream
./upstream-diff.sh /tmp/upstream
```

```text
Usage: upstream-diff.sh <upstream-dir> [options]

Options:
  --config-root DIR  Root directory to scan for local *.conf files.
                      Default: the first of REPO_ROOT/config/servers,
                      REPO_ROOT/servers, REPO_ROOT/proxy-confs, REPO_ROOT
                      that exists (REPO_ROOT is this script's parent dir).
  --domain NAME       Restrict the scan to configs under a path segment
                      matching */NAME/*.conf (repeatable). Use this if
                      your local tree is organized per-domain.
  --output-json       Output results as JSON instead of markdown
  --help, -h          Show this help

Exit codes:
  0  No actionable changes found
  1  Actionable changes found (needs review)
  2  Error
```

## Renamed / aliased vhosts

If a local config file is named differently from its upstream sample (or has
no upstream counterpart at all), copy `upstream-map.conf.example` to
`upstream-map.conf` next to `upstream-diff.sh` and add a mapping line. See
the comments in that file for the format.

## What gets filtered

`is_known_customization()` treats these removed-line patterns as expected
customizations, not actionable changes: `server_name`, auth directives
(basic auth, LDAP/Authelia/Authentik/tinyauth includes), `listen`,
`proxy_pass`/`set $upstream_*`, `proxy_*` tuning directives,
`client_max_body_size`, `return`/`rewrite`, and structural tokens
(`{`/`}`/`location`). Anything else removed from the upstream sample gets
flagged as actionable.

## CI usage

`upstream-sync.yml.example` is a GitHub Actions workflow template. Copy it
to `.github/workflows/upstream-sync.yml` in your own SWAG-config repo
(alongside a copy of `upstream-diff.sh`, keeping the `swag/` subpath, and
optionally `upstream-map.conf`). It runs the diff weekly against a fresh
clone of the upstream sample-conf repo and opens a GitHub issue when it
finds actionable changes.
