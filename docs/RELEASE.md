# Release checklist

A release is created from an adapter tag `v${PROJECT_VERSION}`. The Magpie source release is independently pinned by `MAGPIE_VERSION` and `MAGPIE_SOURCE_COMMIT` in `versions.env`.

## One-time setup

1. Create a fine-grained, repository-scoped PAT with **Contents: Read and write** and **Pull requests: Read and write**. Store it as `MAGPIE_UPDATER_TOKEN`. The upstream updater deliberately uses this PAT rather than `GITHUB_TOKEN`, so its PR triggers the ordinary `pull_request` validation and SDK builds.
2. Generate an EC P-256 key:

   ```sh
   openssl ecparam -name prime256v1 -genkey -noout -out magpie-repo.sec.pem
   base64 -w0 magpie-repo.sec.pem
   ```

3. Store the base64 output as GitHub Actions secret `MAGPIE_APK_SIGNING_KEY_B64`.
4. Keep the private key in an offline/managed backup. Never commit it or publish it.
5. Configure GitHub Pages to deploy from `gh-pages` at `/`. The first release workflow creates this branch.
6. Ensure the repository allows Actions to write repository contents.

## Before each release

- [ ] Run `./scripts/validate-repo.sh`.
- [ ] Run actionlint.
- [ ] Verify `versions.env`, `magpie/Makefile` and the upstream release tag agree:

  ```sh
  python3 scripts/check-versions.py --verify-upstream
  python3 scripts/check-versions.py --tag v2.0.0
  ```

- [ ] Confirm the full commit SHA matches the upstream release tag.
- [ ] Confirm `luci-app-magpie` `PKG_VERSION` equals `PROJECT_VERSION` (enforced by `check-versions.py`) and the release tag is exactly `v2.0.0`, not `v2.0.0-production`.
- [ ] Both official SDK builds pass: `x86_64` and `aarch64_cortex-a53`.
- [ ] The signed APKs and `packages.adb` pass `apk verify` with the exported public key.
- [ ] Runtime test x86_64 OpenWrt 25.12.6: install, start, stop, restart, process health, Gateway listener and Web Console listener.
- [ ] Runtime test aarch64_cortex-a53 OpenWrt 25.12.6 on a real device or VM.
- [ ] Upgrade test from the v1 package on both architectures: keep the old `gateway_addr '0.0.0.0:3425'` and a generated `web_key`, install the new APK, and verify the service starts, the wildcard address migrates to `127.0.0.1:3425`, the key file is created with mode `0600`, and the LuCI package is now `2.0.0`.
- [ ] Verify `logread` does not contain `?k=` after the service starts.
- [ ] Verify LuCI cannot read the Web Console key and Web Console remains loopback-only.
- [ ] Verify wildcard Gateway listeners (`0.0.0.0`, `::`, `*`) are rejected; a specific LAN/VPN address is allowed only with a restrictive firewall rule and Gateway API key.
- [ ] Review the final Actions run and both architecture artifacts.

Create a tag only after every box is checked:

```sh
git tag v2.0.0
git push origin v2.0.0
```

The release workflow fails closed if the tag, source pin, signing key, package architecture, APK signatures or repository index verification fail.

## Release output

The workflow publishes:

- Architecture-suffixed APK files and checksums as GitHub Release assets.
- Per-architecture signed feed archives.
- A versioned signed feed directory on `gh-pages`:
  `openwrt-25.12.6/<apk-architecture>/packages.adb`.
- The public repository key at `magpie-repo.pub`.

After GitHub Pages finishes deploying, package clients use:

```text
https://OWNER.github.io/REPOSITORY/openwrt-25.12.6/<apk-architecture>/packages.adb
```

The GitHub Pages branch and Release assets contain public keys only. The private key must not appear anywhere in those artifacts.
