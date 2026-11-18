# Changelog

## v2.0.0 - 2026-11-19

### Security

- Web Console key moved from UCI into `/etc/magpie/secrets/web.key` with
  `root:root` and mode `0600`; it is no longer returned by rpcd or read by the
  LuCI JavaScript.
- LuCI no longer builds `?k=` links. The Web Console is accessed through an SSH
  tunnel and the root-only key file.
- The daemon's stdout is no longer relayed to syslog, because upstream prints
  the keyed Web Console link on startup. Only stderr is logged.
- Gateway wildcard listeners (including expanded IPv6 and IPv4-mapped forms)
  and hostname listeners are rejected.
- `data_dir` rejects non-canonical paths (`//`, `/.`, `/..`) so the secrets
  directory cannot be reached through a path alias.
- Release APKs and the `packages.adb` index are signed; PR/branch builds are
  explicitly labeled `UNSIGNED_TEST_ARTIFACT_ONLY`.

### Packaging and release

- Upstream Magpie is pinned to `v0.1.4444` by full Git commit
  `42181fdd27faadebd6d0bcf4d44322e404291ba8`; `PKG_HASH` is not used.
- `check-versions.py` verifies the upstream tag resolves to the pinned commit
  and that `luci-app-magpie` follows `PROJECT_VERSION`.
- `luci-app-magpie` is version `2.0.0`, so apk upgrades the LuCI page.
- Signed feed publication to the `gh-pages` branch with fail-closed checks.
- Daily upstream update PR workflow.

### Upgrade

- v1 UCI `gateway_addr '0.0.0.0:3425'` is migrated to `127.0.0.1:3425`.
- Legacy UCI `web_key` is migrated to the root-only secret file; `web_addr` is
  removed. See [docs/UPGRADING.md](docs/UPGRADING.md).

### Tests and CI

- Python unit tests cover version pins, source tags, key handling, loopback
  defaults, health checks, path validation, architecture checks and the APK
  signing flow.
- Shell tests cover the init migration, unsafe paths, wildcard address
  rejection and the no-stdout-logging rule.
- GitHub Actions are pinned to full commit SHAs; ShellCheck, yamllint, mypy and
  actionlint run in CI.

### Verification status

The source bundle passed local static/unit checks. Full OpenWrt SDK builds,
real apk-tools signature verification, and router runtime/upgrade tests are
run by the GitHub Actions matrix and the release checklist; see
[docs/VERIFICATION.md](docs/VERIFICATION.md).
