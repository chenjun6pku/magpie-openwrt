# Security model

## Listener exposure

The package defaults to loopback-only listeners:

* Gateway: `127.0.0.1:3425`
* Web Console: `127.0.0.1:3430`

No OpenWrt firewall rule is installed by this package. Remote Gateway use is an explicit administrator action: bind to one trusted LAN/VPN address, permit only intended source networks, and configure a Gateway API key. The init script rejects wildcard Gateway listeners (`0.0.0.0`, `::`, `*`). Do not forward either port from WAN.

The Web Console stays on loopback. Access it through an SSH local-forward. Do not change it to `0.0.0.0` as a convenience setting; the page can administer providers, accounts and gateway settings.

## Web Console key

The Magpie Web Console key is a long-term secret. It is generated on first service start, stored at `/etc/magpie/secrets/web.key`, owned by `root:root`, mode `0600`. The parent `secrets` directory is mode `0700`; `/etc/magpie` is mode `0711` so the `magpie` service account can traverse to its own data directories without reading the secret.

The key is deliberately absent from `/etc/config/magpie`, rpcd UCI read results and LuCI JavaScript. LuCI never returns the key to the browser, constructs a keyed URL, or stores it in browser history. An administrator retrieves it over SSH and enters it into the Web Console sign-in prompt through an SSH tunnel.

The daemon's **stdout is not relayed to syslog**. Upstream `magpie serve --web` prints the Web Console link with `?k=<MAGPIE_WEB_KEY>` on startup, so the init script enables only `procd_set_param stderr 1`. Do not add `procd_set_param stdout 1` in a local override: it would put the long-term key into `logread`, remote syslog collectors and diagnostic bundles.

On upgrade from v1, the init script moves the legacy UCI `web_key` to the root-only secret file and removes it from UCI, and deletes the removed `web_addr` option. See [UPGRADING.md](UPGRADING.md).

The service reads the secret as root during init and passes it to the daemon using `MAGPIE_WEB_KEY`. The daemon runs under the dedicated `magpie` account. Root on the router can of course inspect process state; this is not intended to defend secrets against router root.

To rotate the key, stop Magpie, replace `/etc/magpie/secrets/web.key` with a new random value of at least 16 permitted characters (64 lowercase hex characters is recommended), set owner/mode to `root:root`/`0600`, then restart the service. Existing browser sessions may remain valid according to upstream cookie/session behavior; revoke them in Magpie if the upstream UI supports it.

## APK repository signing

Release APKs and `packages.adb` are signed with a dedicated P-256 EC key. The private PEM exists only as the GitHub Actions secret `MAGPIE_APK_SIGNING_KEY_B64` and in the ephemeral runner's temporary directory. It must never be committed, attached to a release or stored in the `gh-pages` branch.

The public key `magpie-repo.pub` is published with the feed. Router clients trust it by placing it in `/etc/apk/keys/` before adding the repository URL. The repository index is signed after the APKs are signed. The release workflow verifies each package and the generated index using the matching public key before publishing.

PR and branch builds are explicitly labeled `UNSIGNED_TEST_ARTIFACT_ONLY` and are not published as trusted feeds.

## GitHub Actions

* Actions are pinned to full commit SHAs.
* Normal CI receives `contents: read` only.
* The release job receives `contents: write` only to publish Release assets and the `gh-pages` feed.
* Upstream updater runs only on schedule/manual dispatch, has PR/write permission, and opens a PR; it does not push directly to `main` or publish releases.
* Release tags are checked against `PROJECT_VERSION`, while Magpie source version and commit are checked against the pinned metadata.

## Remaining trust boundary

A successful signature proves that the feed artifacts were signed by the repository key; it does not prove the upstream project itself is safe or that every feature works on every router. Review upstream update PRs and require both SDK builds plus runtime tests before cutting a release.
