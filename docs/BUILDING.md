# Build procedure

## Matrix

| APK package architecture | Official SDK target | SDK archive slug |
|---|---|---|
| `x86_64` | `x86/64` | `x86-64` |
| `aarch64_cortex-a53` | `mediatek/filogic` | `mediatek-filogic` |

Default OpenWrt release is 25.12.6. `scripts/download-sdk.sh` discovers the official archive name and validates its SHA-256 using the official `sha256sums` file.

## Validate the repo

```sh
./scripts/validate-repo.sh
actionlint -color
python3 scripts/check-versions.py --verify-upstream
```

## Build unsigned CI artifacts locally

```sh
./scripts/download-sdk.sh 25.12.6 x86/64 x86-64 "$PWD/.sdk-x86_64"
./scripts/build-sdk.sh /path/to/openwrt-sdk-x86-64 x86_64

./scripts/download-sdk.sh 25.12.6 mediatek/filogic mediatek-filogic "$PWD/.sdk-aarch64"
./scripts/build-sdk.sh /path/to/openwrt-sdk-mediatek-filogic aarch64_cortex-a53
```

The output goes under `dist/<package-architecture>/`. Without `SIGNING_KEY_FILE`, outputs are unsigned test artifacts and include `FEED_STATUS.txt` with `UNSIGNED_TEST_ARTIFACT_ONLY`.

## Build a signed feed locally

Keep a dedicated private key outside the repository:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out "$HOME/magpie-repo.sec.pem"
SIGNING_KEY_FILE="$HOME/magpie-repo.sec.pem" \
  ./scripts/build-sdk.sh /path/to/openwrt-sdk-x86-64 x86_64
```

The same key must sign both architectures for one feed repository. Do not use a developer key for a public release; use the protected GitHub Actions secret.

## SDK build contents

The Magpie package uses the upstream Go `nogui` build tag and `CGO_ENABLED=0`. It does not compile the Wails/GTK/WebKit desktop shell. Magpie's embedded Web Console assets are built into the same Go executable and served by `magpie serve --web`.

The SDK package index is used to check the built package metadata. Release artifacts are then individually signed and a feed-specific `packages.adb` is created and signed with the repository key. This is not the SDK's temporary build key.
