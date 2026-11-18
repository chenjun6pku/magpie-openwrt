#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SDK="$TMP/sdk"
PACKAGES="$TMP/packages"
mkdir -p "$SDK/staging_dir/host/bin" "$PACKAGES"
: > "$PACKAGES/magpie-0.1.4444-r1.apk"
: > "$PACKAGES/luci-app-magpie-1.0.0-r1.apk"
openssl ecparam -name prime256v1 -genkey -noout -out "$TMP/repository-key.pem"

cat > "$SDK/staging_dir/host/bin/apk" <<'MOCK_APK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$APK_CALL_LOG"
args=("$@")
command_name=''
for arg in "${args[@]}"; do
  case "$arg" in
    adbsign|mkndx|verify|adbdump) command_name="$arg"; break ;;
  esac
done
case "$command_name" in
  adbsign|verify)
    ;;
  mkndx)
    output='packages.adb'
    for ((i = 0; i < ${#args[@]}; i++)); do
      if [[ "${args[$i]}" == '--output' ]]; then
        output="${args[$((i + 1))]}"
      fi
    done
    printf 'mock-index\n' > "$output"
    ;;
  adbdump)
    printf '%s\n' '{"packages":[{"name":"magpie","arch":"x86_64"},{"name":"luci-app-magpie","arch":"noarch"}]}'
    ;;
  *)
    echo "unexpected mock apk invocation: $*" >&2
    exit 1
    ;;
esac
MOCK_APK
chmod 0755 "$SDK/staging_dir/host/bin/apk"

export APK_CALL_LOG="$TMP/apk-calls.log"
"$ROOT/scripts/sign-feed.sh" "$SDK" "$TMP/repository-key.pem" "$PACKAGES" x86_64

grep -Eq '^--allow-untrusted --sign-key .+ adbsign --reset-signatures ' "$APK_CALL_LOG" \
  || { echo 'APK signing did not pass --allow-untrusted and repository key as global options' >&2; exit 1; }
grep -Eq '^--root .+ --keys-dir .+ mkndx --output packages\.adb ' "$APK_CALL_LOG" \
  || { echo 'APK index generation invocation was not correct' >&2; exit 1; }
grep -Eq '^--keys-dir .+ verify .+packages\.adb$' "$APK_CALL_LOG" \
  || { echo 'Signed APK index was not verified' >&2; exit 1; }
test -s "$PACKAGES/packages.adb"
test -s "$PACKAGES/magpie-repo.pub"
test -s "$PACKAGES/SHA256SUMS"

echo 'APK feed signing workflow tests: PASS'
