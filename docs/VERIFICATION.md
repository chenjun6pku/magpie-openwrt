# Verification record for v2.0.0 source bundle

This record distinguishes checks performed against the source bundle from checks that require GitHub Actions, the official OpenWrt SDK, or an OpenWrt runtime.

## Completed locally

- Python source compilation (`python3 -m py_compile scripts/*.py tests/*.py`).
- Project/tag metadata validation, including upstream tag-to-commit resolution (`scripts/check-versions.py --verify-upstream`).
- 28 Python unit tests.
- procd/init behavior test, including the v1 UCI migration (wildcard `gateway_addr` → loopback, UCI `web_key` → root-only secret file, `web_addr` removal), loopback defaults, rejected unsafe and non-canonical data paths, wildcard/non-literal Gateway binds, port validation, degraded status when either listener is absent despite a live PID, and re-securing a restored Web Console key to mode `0600`.
- APK feed signing-flow test using a temporary P-256 key and a mocked SDK `apk` executable. This checks command ordering, output layout, package architecture validation, and checksums; it is not a cryptographic verification by OpenWrt's real `apk` binary.
- Bash/POSIX shell syntax checks.
- LuCI JavaScript syntax check with Node.js.
- YAML parsing for GitHub workflows and Dependabot configuration (`yamllint 1.37.1`).
- JSON parsing for LuCI menu and rpcd ACL files.
- Static regression checks for full SHA-pinned GitHub Actions, absence of UCI/browser Web Key exposure, absence of stdout→syslog logging in the init script, the `build-sdk.sh` output-directory guard, a real `BuildPackage` line in the self-contained LuCI Makefile so OpenWrt's `include/scan.mk` indexes it, and no `luci-base`/`lucihttp` build in the SDK (its runtime dependency is resolved on the target).
- ShellCheck 0.10.0 (`--severity=warning`), mypy 1.18.2 (`--strict --python-version 3.11`), yamllint 1.37.1, and actionlint 1.7.12 run successfully against the source bundle.

## Required before calling a GitHub Release production-verified

The following checks were not run in the source-bundle environment:

- `apk`-based signature and index verification with the actual OpenWrt 25.12.6 SDK toolchain. The signing test used a mock `apk` executable only.
- Full x86_64 OpenWrt SDK compile.
- Full aarch64_cortex-a53 (mediatek/filogic) OpenWrt SDK compile.
- Installation, service lifecycle, upgrade from v1, Gateway API, Web Console authentication and persistence tests on OpenWrt x86_64 and aarch64_cortex-a53 devices/VMs.

A `v2.0.0` tag should only be pushed after GitHub Actions is green, the `MAGPIE_APK_SIGNING_KEY_B64` and `MAGPIE_UPDATER_TOKEN` repository secrets are configured, GitHub Pages is enabled for `gh-pages`, and both target runtime test checklists in `docs/RELEASE.md` are complete.
