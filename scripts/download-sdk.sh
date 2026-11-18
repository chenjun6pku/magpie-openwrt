#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <openwrt-version> <target/subtarget> <target-slug> <destination>" >&2
  exit 2
fi

version="$1"
target="$2"
target_slug="$3"
destination="$4"

case "$version" in
  *[!0-9.]*|'') echo "Invalid OpenWrt version: $version" >&2; exit 2 ;;
esac
case "$target" in
  */*) ;;
  *) echo "Target must be target/subtarget: $target" >&2; exit 2 ;;
esac

base="https://downloads.openwrt.org/releases/${version}/targets/${target}"
mkdir -p "$destination"

# Resolve the exact SDK filename from the official directory. This avoids
# hard-coding a GCC version that may change in a future OpenWrt point release.
index_file="$destination/index.html"
curl --fail --location --retry 3 --retry-delay 2 "$base/" -o "$index_file"
sdk_file="$(grep -oE "openwrt-sdk-${version}-${target_slug}_gcc-[^\"[:space:]]+_musl\.Linux-x86_64\.tar\.zst" "$index_file" | sort -u | head -n1)"
if [[ -z "$sdk_file" ]]; then
  echo "Could not find an official SDK archive under $base" >&2
  exit 1
fi

curl --fail --location --retry 3 --retry-delay 2 "$base/sha256sums" -o "$destination/sha256sums"
expected="$(awk -v f="$sdk_file" '{ name=$2; sub(/^\*/, "", name); sub(/^\.\//, "", name); if (name == f) { print $1; exit } }' "$destination/sha256sums")"
if [[ ! "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "No valid SHA-256 entry for $sdk_file in official sha256sums" >&2
  exit 1
fi

archive="$destination/$sdk_file"
curl --fail --location --retry 3 --retry-delay 2 "$base/$sdk_file" -o "$archive"
printf '%s  %s\n' "$expected" "$archive" | sha256sum --check --status || {
  echo "SDK SHA-256 verification failed: $sdk_file" >&2
  exit 1
}

tar --zstd -xf "$archive" -C "$destination"
sdk_dir="$(find "$destination" -mindepth 1 -maxdepth 1 -type d -name 'openwrt-sdk-*' -print -quit)"
if [[ -z "$sdk_dir" || ! -x "$sdk_dir/scripts/feeds" ]]; then
  echo "SDK extraction did not produce a valid SDK directory" >&2
  exit 1
fi

printf '%s\n' "$sdk_dir"
