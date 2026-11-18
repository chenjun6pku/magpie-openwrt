# Magpie OpenWrt

**Production source package and signed APK-feed pipeline for OpenWrt 25.12+.**

This repository packages upstream [Magpie](https://github.com/yetone/magpie) in its headless Go build mode and adds a small LuCI service-management page. It does not package Wails, GTK, WebKit, a desktop window or a system tray. Magpie's own embedded Web Console is retained and served by `magpie serve --web`.

> Release status: the repository contains production-oriented package recipes, security defaults and a signed-feed release pipeline. A release is not considered production-verified until its GitHub Actions SDK matrix is green and both target runtime tests have been performed. The current source bundle has passed local static/unit checks only; no OpenWrt SDK build or router runtime test was run in this environment.

## Release pins

`versions.env` is the single release manifest:

| Field | Current pin |
|---|---|
| Project version | `2.0.0` |
| OpenWrt SDK baseline | `25.12.6` |
| Magpie upstream | `v0.1.4444` |
| Magpie source commit | `42181fdd27faadebd6d0bcf4d44322e404291ba8` |

The Magpie source is fetched through OpenWrt's Git source mechanism using the full 40-character commit object ID. `PKG_HASH:=skip` is not used. CI resolves the corresponding upstream release tag and refuses to build if it does not resolve to the pinned object. Upstream release changes are checked daily and submitted as PRs; they are not silently pulled into a release build.

The project release tag must equal `v${PROJECT_VERSION}`. The upstream Magpie version and this OpenWrt adapter version are intentionally independent.

## Upgrading from v1

The package migrates the v1 UCI layout on the first start after upgrade:

- a wildcard `gateway_addr` such as `0.0.0.0:3425` is rewritten to `127.0.0.1:<port>`;
- a legacy UCI `web_key` is copied to `/etc/magpie/secrets/web.key` (`root:root`, `0600`) and removed from UCI, so existing Web Console sessions stay signed in;
- the removed `web_addr` option is deleted.

The LuCI package version is `2.0.0`, so the service page is upgraded as well. If you intentionally exposed the Gateway on the LAN before the upgrade, set a specific router LAN/VPN address afterwards and add firewall rules; wildcard binds are rejected. See [docs/UPGRADING.md](docs/UPGRADING.md) for the full checklist.

## First push

From this project root:

```sh
git init -b main
git add .
git commit -m "feat: add Magpie OpenWrt packages and signed APK CI"
git remote add origin https://github.com/OWNER/magpie-openwrt.git
git push -u origin main
```

Replace `OWNER` with the destination account or organization. Pushing to `main` starts the build workflow. The release tag must be exactly `v2.0.0`, not a directory or bundle name such as `v2.0.0-production`.

## Supported build targets

| APK architecture | Official SDK target | SDK archive slug |
|---|---|---|
| `x86_64` | `x86/64` | `x86-64` |
| `aarch64_cortex-a53` | `mediatek/filogic` | `mediatek-filogic` |

The build workflow targets only these two architectures. The package Makefile explicitly rejects MIPS/MIPSel/MIPS64/MIPS64el and big-endian PPC64 because the pinned Magpie dependency graph includes SQLite implementations without support for those targets. Other architectures are not claimed as supported by this repository.

## Repository structure

```text
magpie-openwrt/
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       ├── build-apk.yml
│       └── upstream-update.yml
├── docs/
│   ├── BUILDING.md
│   ├── SECURITY.md
│   ├── RELEASE.md
│   ├── UPGRADING.md
│   └── VERIFICATION.md
├── magpie/
│   ├── Makefile
│   └── files/
│       ├── magpie.config
│       └── magpie.init
├── luci-app-magpie/
│   ├── Makefile
│   ├── htdocs/luci-static/resources/view/magpie/overview.js
│   └── root/usr/share/
│       ├── luci/menu.d/luci-app-magpie.json
│       └── rpcd/{acl.d/luci-app-magpie.json,ucode/magpie}
├── scripts/
│   ├── build-sdk.sh
│   ├── check-apk-arch.py
│   ├── check-versions.py
│   ├── download-sdk.sh
│   ├── sign-feed.sh
│   ├── update-upstream.py
│   └── validate-repo.sh
├── tests/
│   ├── test_repo.py
│   ├── test_init.sh
│   └── test_sign_feed.sh
├── CHANGELOG.md
├── versions.env
└── ...
```

## Security defaults

* Gateway binds to `127.0.0.1:3425` by default.
* Web Console binds to `127.0.0.1:3430` and is only exposed through an SSH tunnel by default.
* `MAGPIE_WEB_KEY` is generated once and stored in `/etc/magpie/secrets/web.key` as `root:root`, mode `0600`. It is not stored in UCI, is not returned by rpcd, and is never read by the LuCI JavaScript.
* The daemon's stdout is deliberately **not** relayed to syslog: upstream prints the Web Console link with `?k=<key>` on startup. Only stderr is logged, so `logread` never receives the key.
* LuCI does not construct a `?k=` URL. An administrator obtains the key over SSH and enters it in the Web Console sign-in prompt.
* No WAN firewall rule is installed. If remote Gateway clients are needed, bind only to a specific router LAN/VPN address (wildcard listeners are rejected), configure firewall restrictions, and create Gateway API keys in Magpie.
* The package service runs as the dedicated `magpie` user. Persistent application data is separate from the root-only Web Console secret.

See [docs/SECURITY.md](docs/SECURITY.md) for access and key-handling details, and [docs/VERIFICATION.md](docs/VERIFICATION.md) for the exact local verification record and release gates.

## Build and test locally

Requirements: Linux x86_64 build host, OpenWrt SDK host dependencies, Bash, Git, curl, zstd, tar, OpenSSL, Python 3, Node.js, ShellCheck, yamllint, mypy, and actionlint.

```sh
./scripts/validate-repo.sh
actionlint -color

./scripts/download-sdk.sh 25.12.6 x86/64 x86-64 "$PWD/.sdk-x86_64"
./scripts/build-sdk.sh /path/to/openwrt-sdk-x86-64 x86_64

./scripts/download-sdk.sh 25.12.6 mediatek/filogic mediatek-filogic "$PWD/.sdk-aarch64"
./scripts/build-sdk.sh /path/to/openwrt-sdk-mediatek-filogic aarch64_cortex-a53
```

SDK archives are discovered from the official OpenWrt target directory and verified against the official `sha256sums` file before extraction. The build script installs this repository as an SDK feed, builds both APKs, then checks APK architecture metadata using the SDK's `apk adbdump` command.

Non-tag builds produce **unsigned test artifacts**. They are not a trusted package feed and must not be installed with an expectation of repository signature verification.

## GitHub Actions

* Push/PR: validation + parallel SDK builds for `x86_64` and `aarch64_cortex-a53`; temporary artifacts expire after 14 days.
* Scheduled upstream check: daily checks the latest upstream Magpie release and opens a PR with version/date/full commit updates.
* Release tag: only `v${PROJECT_VERSION}` is accepted. Both matrix builds must sign the APKs and `packages.adb` index using the repository signing key. Artifacts are published as GitHub Release assets and a versioned feed on the `gh-pages` branch.

All `uses:` GitHub Actions are pinned to full commit SHAs. Workflow permissions are least-privilege; normal CI receives `contents: read`, and the Release job alone receives `actions: read` plus `contents: write`. The upstream updater uses a repository-scoped PAT so its PR actually triggers CI.

### One-time repository setup for signed releases

1. Create a fine-grained, repository-scoped PAT named for the updater with **Contents: Read and write** and **Pull requests: Read and write** permissions. Add it as the Actions secret `MAGPIE_UPDATER_TOKEN`. The updater uses this token (not `GITHUB_TOKEN`) so its new PR emits a `pull_request` event and triggers CI.
2. Generate a dedicated OpenWrt APK repository signing key:

   ```sh
   openssl ecparam -name prime256v1 -genkey -noout -out magpie-repo.sec.pem
   base64 -w0 magpie-repo.sec.pem
   ```

3. Add the base64 output as the GitHub Actions secret `MAGPIE_APK_SIGNING_KEY_B64`. Never commit or upload `magpie-repo.sec.pem`.
4. In GitHub repository Settings → Pages, select **Deploy from a branch**, branch `gh-pages`, folder `/`. The first successful release creates this branch.
5. Ensure repository Actions settings allow the workflow's declared `contents: write` permission.
6. Confirm both target runtime tests are complete, then create and push the project tag:

   ```sh
   git tag v2.0.0
   git push origin v2.0.0
   ```

The Release workflow fails closed if the key secret is missing, either architecture fails, unsigned packages/index are produced, or the tag does not match the project version.

## Install from the signed feed

After a successful release and after GitHub Pages is enabled, replace `OWNER` and `REPOSITORY`:

```sh
FEED_BASE="https://OWNER.github.io/REPOSITORY"
mkdir -p /etc/apk/keys /etc/apk/repositories.d
wget -O /etc/apk/keys/magpie-repo.pub "$FEED_BASE/magpie-repo.pub"
printf '%s\n' "$FEED_BASE/openwrt-25.12.6/$(apk --print-arch)/packages.adb" \
  > /etc/apk/repositories.d/magpie.list
apk update
apk add magpie luci-app-magpie
```

The public key is safe to distribute and must be obtained over HTTPS from the repository's published `gh-pages` feed or a trusted out-of-band channel. The private key must remain only in GitHub Secrets / controlled release infrastructure.

## Open the Magpie Web Console

The Web Console is intentionally not exposed on the LAN by default. On the administrator workstation:

```sh
ssh -L 3430:127.0.0.1:3430 root@<router-lan-ip>
```

In a second terminal, read the root-only key through SSH:

```sh
ssh root@<router-lan-ip> 'cat /etc/magpie/secrets/web.key'
```

Open `http://127.0.0.1:3430/` in the workstation browser and enter the key in Magpie's sign-in prompt. This uses an encrypted SSH tunnel; LuCI does not expose the secret or embed it in a link.

LuCI entry: **Services → Magpie**. LuCI controls procd and UCI; Provider/model/Gateway administration remains in Magpie's own Web Console.

## Enable a remote Gateway client

Default Gateway listener is loopback. To expose it only on the router's LAN address, for example:

```sh
uci set magpie.main.gateway_addr='192.168.1.1:3425'
uci commit magpie
/etc/init.d/magpie restart
```

Add a firewall rule restricted to trusted client subnets/VPN peers and create Gateway API keys in the Magpie Web Console. Do not open the port to WAN or bind to `0.0.0.0` without an explicit firewall and authentication design.

## Scope and limitations

* Headless server build only; no Wails/GTK/WebKit desktop shell, tray or window APIs.
* Magpie CLI, Gateway and embedded Web Console are retained through upstream's `nogui` build path. Actual functional parity must be checked for each upstream update.
* Optional plugins may require Bun or other runtime dependencies; those are not silently bundled.
* The repository creates package artifacts and a signed feed. It does not contain prebuilt APKs in the source tree.
* Source/static checks are not a substitute for SDK builds and on-device runtime tests. A tag must not be published until the CI matrix and release checklist pass.
