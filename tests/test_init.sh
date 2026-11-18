#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../magpie/files/magpie.init
source "$ROOT/magpie/files/magpie.init"

TEST_ENABLED=1
TEST_GATEWAY_ADDR='127.0.0.1:3425'
TEST_PUBLIC_URL=''
TEST_DATA_DIR='/etc/magpie'
TEST_WEB_KEY=''
TEST_WEB_ADDR=''
PROCD_STARTED=0
PROCD_CAPTURE=''

config_load() { :; }
config_get() {
  local variable="$1" option="$3" fallback="$4" value
  case "$option" in
    enabled) value="$TEST_ENABLED" ;;
    gateway_addr) value="$TEST_GATEWAY_ADDR" ;;
    public_url) value="$TEST_PUBLIC_URL" ;;
    data_dir) value="$TEST_DATA_DIR" ;;
    *) value="$fallback" ;;
  esac
  printf -v "$variable" '%s' "$value"
}
uci() {
  while [ "${1:-}" = '-q' ]; do shift; done
  case "${1:-}" in
    get)
      case "${2:-}" in
        magpie.main.gateway_addr)
          printf '%s\n' "$TEST_GATEWAY_ADDR"
          ;;
        magpie.main.web_key)
          [ -n "$TEST_WEB_KEY" ] || return 1
          printf '%s\n' "$TEST_WEB_KEY"
          ;;
        magpie.main.web_addr)
          [ -n "$TEST_WEB_ADDR" ] || return 1
          printf '%s\n' "$TEST_WEB_ADDR"
          ;;
        *) return 1 ;;
      esac
      ;;
    set)
      case "${2:-}" in
        magpie.main.gateway_addr=*) TEST_GATEWAY_ADDR="${2#*=}" ;;
        *) return 1 ;;
      esac
      ;;
    delete)
      case "${2:-}" in
        magpie.main.web_key) TEST_WEB_KEY='' ;;
        magpie.main.web_addr) TEST_WEB_ADDR='' ;;
        *) return 1 ;;
      esac
      ;;
    commit) return 0 ;;
    *) return 1 ;;
  esac
}
logger() { :; }
mkdir() { :; }
chown() { :; }
chmod() {
  if [[ "${*: -1}" == "${WEB_KEY_FILE:-}" && "$1" == '0600' ]]; then
    command chmod "$@"
  fi
}
procd_open_instance() { PROCD_STARTED=1; }
procd_set_param() { PROCD_CAPTURE+="$*"$'\n'; }
procd_close_instance() { :; }

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

if grep -qE 'procd_set_param[[:space:]]+stdout[[:space:]]+1' "$ROOT/magpie/files/magpie.init"; then
  fail 'init must not relay stdout to syslog (it contains the keyed Web Console link)'
fi

# BusyBox od does not consistently accept the old combined flags; the key
# generator must still produce a 64-character lowercase hex value.
generated_key="$(make_web_key)"
[[ ${#generated_key} -eq 64 ]] || fail 'make_web_key must return 64 characters'
case "$generated_key" in
  *[!0-9a-f]*) fail 'make_web_key must return lowercase hex' ;;
esac

# Existing key files are re-secured on every service start, not only at creation.
key_test_file="$(mktemp)"
WEB_KEY_FILE="$key_test_file"
printf '%s\n' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' > "$key_test_file"
command chmod 0644 "$key_test_file"
ensure_web_key || fail 'existing Web Console key should be accepted'
[[ "$(stat -c '%a' "$key_test_file")" == '600' ]] || fail 'existing Web Console key permissions were not tightened to 0600'
rm -f "$key_test_file"
WEB_KEY_FILE='/etc/magpie/secrets/web.key'

# Mock the root-owned secret so service start can be tested without touching /etc.
# shellcheck disable=SC2034 # consumed by the sourced magpie.init
ensure_web_key() { WEB_KEY='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'; }

# Legacy v1 configuration must be migrated before the service starts.
legacy_key='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
key_test_file="$(mktemp)"
rm -f "$key_test_file"
TEST_GATEWAY_ADDR='0.0.0.0:3425'
TEST_WEB_KEY="$legacy_key"
TEST_WEB_ADDR='0.0.0.0:3430'
WEB_KEY_FILE="$key_test_file"
PROCD_STARTED=0
PROCD_CAPTURE=''
start_service || fail 'legacy configuration should migrate and start'
[[ "$TEST_GATEWAY_ADDR" == '127.0.0.1:3425' ]] || fail 'legacy wildcard gateway_addr was not migrated'
[[ -z "$TEST_WEB_KEY" ]] || fail 'legacy web_key was not removed from UCI'
[[ -z "$TEST_WEB_ADDR" ]] || fail 'legacy web_addr was not removed from UCI'
[[ "$(cat "$key_test_file" 2>/dev/null)" == "$legacy_key" ]] || fail 'legacy web key was not migrated to the secret file'
[[ "$(stat -c '%a' "$key_test_file")" == '600' ]] || fail 'migrated web key file is not 0600'
rm -f "$key_test_file"
WEB_KEY_FILE='/etc/magpie/secrets/web.key'
TEST_GATEWAY_ADDR='127.0.0.1:3425'
TEST_WEB_KEY=''
TEST_WEB_ADDR=''

# Safe defaults start the single Magpie server process with a private Web Console.
start_service || fail 'default configuration should start'
[[ "$PROCD_STARTED" -eq 1 ]] || fail 'procd instance was not created'
[[ "$PROCD_CAPTURE" == *'/usr/bin/magpie serve --web'* ]] || fail 'Magpie must run its upstream server mode with Web Console enabled'
[[ "$PROCD_CAPTURE" == *'MAGPIE_ADDR=127.0.0.1:3425'* ]] || fail 'Gateway must default to loopback'
[[ "$PROCD_CAPTURE" == *'MAGPIE_WEB_KEY=0123456789abcdef'* ]] || fail 'Web key must be injected into daemon environment'

# Dangerous data paths must be rejected before procd starts.
for unsafe in '/etc/magpie/secrets/other' '/etc/magpie/../root' '/etc/magpie/./secrets' \
  '/etc/magpie//secrets' '/etc/magpie/secrets/.' '/etc/magpie/secrets/..' \
  '/etc/magpie/secrets/../secrets' '/tmp' '/'; do
  TEST_DATA_DIR="$unsafe"
  PROCD_STARTED=0
  PROCD_CAPTURE=''
  if start_service >/dev/null 2>&1; then
    fail "unsafe data_dir was accepted: $unsafe"
  fi
  [[ "$PROCD_STARTED" -eq 0 ]] || fail "procd started for unsafe data_dir: $unsafe"
done

# Health must reflect listener availability, not merely a matching PID.
TEST_PID_PRESENT=1
TEST_GATEWAY_LISTENING=1
TEST_WEB_LISTENING=1
pidof() { [ "$TEST_PID_PRESENT" -eq 1 ]; }
port_is_listening() {
  case "$1" in
    3425) [ "$TEST_GATEWAY_LISTENING" -eq 1 ] ;;
    3430) [ "$TEST_WEB_LISTENING" -eq 1 ] ;;
    *) return 1 ;;
  esac
}
status >/dev/null || fail 'healthy process and both listeners should report healthy'
TEST_GATEWAY_LISTENING=0
if status >/dev/null 2>&1; then
  fail 'running PID without Gateway listener must not report healthy'
fi
TEST_GATEWAY_LISTENING=1
TEST_WEB_LISTENING=0
if status >/dev/null 2>&1; then
  fail 'running PID without Web Console listener must not report healthy'
fi
TEST_WEB_LISTENING=1
TEST_PID_PRESENT=0
if status >/dev/null 2>&1; then
  fail 'missing Magpie process must not report healthy'
fi

# Reject a non-numeric or out-of-range Gateway port.
TEST_DATA_DIR='/etc/magpie'
for invalid in '127.0.0.1:abc' '127.0.0.1:0' '127.0.0.1:65536' '0.0.0.0:abc' \
  '[0:0:0:0:0:0:0:0]:3425' '[::0]:3425' '000.000.000.000:3425' \
  'router.lan:3425' '::1:3425'; do
  TEST_GATEWAY_ADDR="$invalid"
  PROCD_STARTED=0
  if start_service >/dev/null 2>&1; then
    fail "invalid Gateway address was accepted: $invalid"
  fi
  [[ "$PROCD_STARTED" -eq 0 ]] || fail "procd started for invalid Gateway address: $invalid"
done

# A specific bracketed IPv6 listener is valid.
TEST_GATEWAY_ADDR='[::1]:3425'
PROCD_STARTED=0
PROCD_CAPTURE=''
start_service >/dev/null 2>&1 || fail 'bracketed loopback IPv6 should be accepted'
[[ "$PROCD_STARTED" -eq 1 ]] || fail 'procd did not start for [::1]:3425'
TEST_GATEWAY_ADDR='127.0.0.1:3425'

printf 'Magpie init behavior tests: PASS\n'
