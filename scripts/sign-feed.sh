#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <sdk-dir> <private-key.pem> <package-dir> <expected-package-arch>" >&2
  exit 2
fi

sdk_dir="$(cd "$1" && pwd)"
private_key="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
package_dir="$(cd "$3" && pwd)"
expected_arch="$4"
apk_tool="$sdk_dir/staging_dir/host/bin/apk"
keys_dir="$sdk_dir/tmp/magpie-repo-keys"

[[ -x "$apk_tool" ]] || { echo "apk-tools not found: $apk_tool" >&2; exit 1; }
[[ -s "$private_key" ]] || { echo "Signing key is missing or empty" >&2; exit 1; }
[[ -d "$package_dir" ]] || { echo "Package directory does not exist" >&2; exit 1; }

mapfile -t packages < <(find "$package_dir" -maxdepth 1 -type f -name '*.apk' | sort)
[[ ${#packages[@]} -eq 2 ]] || {
  echo "Expected exactly two APKs (magpie and luci-app-magpie), found ${#packages[@]}" >&2
  exit 1
}

mkdir -p "$keys_dir" "$package_dir"
chmod 0700 "$keys_dir"
openssl ec -in "$private_key" -check -noout
key_details="$(openssl ec -in "$private_key" -text -noout 2>/dev/null)"
grep -q 'ASN1 OID: prime256v1' <<< "$key_details" || {
  echo 'APK repository key must use the NIST P-256 (prime256v1) curve.' >&2
  exit 1
}
openssl ec -in "$private_key" -pubout -out "$keys_dir/magpie-repo.pub"
chmod 0644 "$keys_dir/magpie-repo.pub"
cp "$keys_dir/magpie-repo.pub" "$package_dir/magpie-repo.pub"

for package in "${packages[@]}"; do
  # SDK output is unsigned. --allow-untrusted is a global option and must
  # precede the adbsign applet so apk can read the unsigned input package.
  "$apk_tool" --allow-untrusted --sign-key "$private_key" adbsign \
    --reset-signatures "$package"
  "$apk_tool" --keys-dir "$keys_dir" verify "$package"
done

(
  cd "$package_dir"
  "$apk_tool" --root "$sdk_dir" --keys-dir "$keys_dir" mkndx \
    --output packages.adb \
    ./*.apk
)

# The 25.12 SDK apk-tools version creates the index first; sign it explicitly
# with the same repository key used for the APKs.
"$apk_tool" --allow-untrusted --sign-key "$private_key" adbsign \
  --reset-signatures "$package_dir/packages.adb"
"$apk_tool" --keys-dir "$keys_dir" verify "$package_dir/packages.adb"
"$apk_tool" adbdump --format json "$package_dir/packages.adb" > "$package_dir/packages.json"
python3 "$(dirname "$0")/check-apk-arch.py" "$package_dir/packages.json" magpie "$expected_arch"
python3 "$(dirname "$0")/check-apk-arch.py" "$package_dir/packages.json" luci-app-magpie all
rm -f "$package_dir/packages.json" "$package_dir/SHA256SUMS"
(
  cd "$package_dir"
  sha256sum ./*.apk ./packages.adb ./magpie-repo.pub > SHA256SUMS
)

echo "Signed APK feed ready: $package_dir"
