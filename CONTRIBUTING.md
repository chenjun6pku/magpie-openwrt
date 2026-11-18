# Contributing

## Before opening a pull request

- Run `./scripts/validate-repo.sh` and `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 -color`.
- Keep the package recipe compatible with the official OpenWrt 25.12+ SDK and matching feeds.
- Do not commit SDK directories, `bin/`, `build/`, `staging_dir/`, generated APKs, signing keys or credentials.
- Keep `versions.env` and `magpie/Makefile` in sync. Use a full 40-character upstream Git commit pin; never use `PKG_HASH:=skip`.
- Test both SDK targets when changing Go build flags, package dependencies, SDK integration or APK metadata validation.
- Keep the root-only Web Console key outside UCI, rpcd return values and browser JavaScript.
- Preserve loopback-only listener defaults unless a reviewed security design changes them.

## Upstream Magpie updates

The daily `Check upstream Magpie release` workflow opens a PR when the upstream repository publishes a new release. It updates `versions.env` and the package Makefile with the release tag, release date and immutable full Git commit SHA. Review that PR, verify the source tag, and require both SDK matrix jobs before merging. It never updates `main` directly and never publishes a release automatically.

## Project versioning

`PROJECT_VERSION` identifies this OpenWrt adapter. The GitHub Release tag must be `v${PROJECT_VERSION}`. `MAGPIE_VERSION` separately identifies the upstream application version. The `luci-app-magpie` `PKG_VERSION` follows `PROJECT_VERSION` so that apk actually upgrades the LuCI page on every adapter release; `scripts/check-versions.py` enforces this. Increment the LuCI `PKG_RELEASE` when rebuilding the same version.

## Release and signing

Follow [docs/RELEASE.md](docs/RELEASE.md). Never commit `magpie-repo.sec.pem` or the base64 secret. An unsigned CI artifact is only for testing; it must never be promoted to a public package feed.
