#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_dir="${1:-}"
expected_arch="${2:-}"
output_dir="${3:-${OUTPUT_DIR:-$repo_root/dist/${expected_arch:-unknown}}}"

if [[ -z "$sdk_dir" || -z "$expected_arch" || ! -d "$sdk_dir" ]]; then
  echo "Usage: $0 <extracted-openwrt-sdk-dir> <expected-package-arch> [output-dir]" >&2
  exit 2
fi

case "$expected_arch" in
  x86_64|aarch64_cortex-a53) ;;
  *) echo "Unsupported CI architecture: $expected_arch" >&2; exit 2 ;;
esac

sdk_dir="$(cd "$sdk_dir" && pwd)"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
case "$output_dir" in
  /|"$repo_root"|"$sdk_dir"|"$HOME")
    echo "Refusing unsafe output directory: $output_dir" >&2
    exit 1
    ;;
esac
# Only remove artifacts this script creates; never delete unrelated files.
rm -f "$output_dir"/*.apk "$output_dir"/packages.adb "$output_dir"/packages.json \
  "$output_dir"/SHA256SUMS "$output_dir"/BUILD-INFO.txt \
  "$output_dir"/FEED_STATUS.txt "$output_dir"/magpie-repo.pub
cd "$sdk_dir"

if [[ ! -x ./scripts/feeds || ! -f ./include/package.mk ]]; then
  echo "Not an OpenWrt SDK directory: $sdk_dir" >&2
  exit 1
fi

# Confirm the release tag is still the exact immutable source commit pinned by
# versions.env and magpie/Makefile. A force-moved or deleted upstream tag fails.
python3 "$repo_root/scripts/check-versions.py" --verify-upstream

feeds_file=feeds.conf.default
[[ ! -f feeds.conf ]] || feeds_file=feeds.conf
if ! grep -qE '^src-link[[:space:]]+magpie[[:space:]]' "$feeds_file" 2>/dev/null; then
  printf '\nsrc-link magpie %s\n' "$repo_root" >> "$feeds_file"
fi

./scripts/feeds update packages luci magpie
./scripts/feeds install -p packages golang
./scripts/feeds install -p luci luci-base
./scripts/feeds install -p magpie magpie luci-app-magpie

make defconfig
jobs="${JOBS:-2}"
make -j"$jobs" package/feeds/magpie/magpie/compile V=s
make -j"$jobs" package/feeds/magpie/luci-app-magpie/compile V=s
make package/index V=s

mapfile -t magpie_apks < <(find bin/packages -type f -name 'magpie-*.apk' | sort)
mapfile -t luci_apks < <(find bin/packages -type f -name 'luci-app-magpie-*.apk' | sort)
if [[ ${#magpie_apks[@]} -ne 1 || ${#luci_apks[@]} -ne 1 ]]; then
  echo "Expected exactly one magpie APK and one luci-app-magpie APK." >&2
  printf 'Magpie candidates: %s\n' "${magpie_apks[*]:-(none)}" >&2
  printf 'LuCI candidates: %s\n' "${luci_apks[*]:-(none)}" >&2
  exit 1
fi

apk_tool="$sdk_dir/staging_dir/host/bin/apk"
[[ -x "$apk_tool" ]] || {
  echo "Could not find SDK host apk-tools binary: $apk_tool" >&2
  exit 1
}

magpie_package_dir="$(dirname "${magpie_apks[0]}")"
luci_package_dir="$(dirname "${luci_apks[0]}")"
[[ "$magpie_package_dir" == "$luci_package_dir" ]] || {
  echo "Expected both packages in the same local feed directory." >&2
  exit 1
}
adb_index="$magpie_package_dir/packages.adb"
[[ -s "$adb_index" ]] || {
  echo "OpenWrt SDK did not generate package index: $adb_index" >&2
  exit 1
}

dump_json="$(mktemp)"
trap 'rm -f "$dump_json"' EXIT
"$apk_tool" adbdump --format json "$adb_index" > "$dump_json"
python3 "$repo_root/scripts/check-apk-arch.py" "$dump_json" magpie "$expected_arch"
python3 "$repo_root/scripts/check-apk-arch.py" "$dump_json" luci-app-magpie all
rm -f "$dump_json"
trap - EXIT

cp -f "${magpie_apks[0]}" "${luci_apks[0]}" "$output_dir/"

if [[ "${REQUIRE_SIGNING:-false}" == "true" && -z "${SIGNING_KEY_FILE:-}" ]]; then
  echo 'REQUIRE_SIGNING=true but SIGNING_KEY_FILE was not supplied.' >&2
  exit 1
fi

if [[ -n "${SIGNING_KEY_FILE:-}" ]]; then
  "$repo_root/scripts/sign-feed.sh" "$sdk_dir" "$SIGNING_KEY_FILE" "$output_dir" "$expected_arch"
  printf 'SIGNED_FEED\n' > "$output_dir/FEED_STATUS.txt"
else
  (
    cd "$output_dir"
    sha256sum ./*.apk > SHA256SUMS
  )
  printf 'UNSIGNED_TEST_ARTIFACT_ONLY\n' > "$output_dir/FEED_STATUS.txt"
fi

{
  printf 'Project version: %s\n' "$(sed -n 's/^PROJECT_VERSION=//p' "$repo_root/versions.env")"
  printf 'OpenWrt SDK release: %s\n' "${OPENWRT_VERSION:-$(sed -n 's/^OPENWRT_VERSION=//p' "$repo_root/versions.env")}"
  printf 'Magpie upstream version: %s\n' "$(sed -n 's/^MAGPIE_VERSION=//p' "$repo_root/versions.env")"
  printf 'Magpie source commit: %s\n' "$(sed -n 's/^MAGPIE_SOURCE_COMMIT=//p' "$repo_root/versions.env")"
  printf 'OpenWrt APK architecture: %s\n' "$expected_arch"
  printf 'SDK directory: %s\n' "$(basename "$sdk_dir")"
  printf 'Build timestamp (UTC): %s\n' "$(date -u +%FT%TZ)"
} > "$output_dir/BUILD-INFO.txt"

# Include build metadata in the checksum manifest; signing key material is never staged.
(
  cd "$output_dir"
  hash_files=( ./*.apk ./BUILD-INFO.txt ./FEED_STATUS.txt )
  if [[ -n "${SIGNING_KEY_FILE:-}" ]]; then
    hash_files+=( ./packages.adb ./magpie-repo.pub )
  fi
  sha256sum "${hash_files[@]}" > SHA256SUMS
)

printf '\nBuilt artifacts (%s):\n' "$expected_arch"
find "$output_dir" -maxdepth 1 -type f -printf '%f\n' | sort
