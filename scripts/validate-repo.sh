#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required validation tool is missing: $1" >&2
    exit 1
  }
}

for tool in bash sh python3 node shellcheck yamllint mypy; do
  require_cmd "$tool"
done

bash -n scripts/*.sh
sh -n magpie/files/magpie.init
shellcheck --severity=warning scripts/*.sh magpie/files/magpie.init tests/*.sh
node --check luci-app-magpie/htdocs/luci-static/resources/view/magpie/overview.js
yamllint -c .yamllint .github/workflows/*.yml .github/dependabot.yml
python3 -m py_compile scripts/*.py tests/*.py
mypy --strict --python-version 3.11 scripts/*.py
python3 scripts/check-versions.py
python3 -m unittest discover -s tests -v
bash tests/test_init.sh
bash tests/test_sign_feed.sh

python3 - <<'PY'
import json
from pathlib import Path
for path in (
    Path('luci-app-magpie/root/usr/share/luci/menu.d/luci-app-magpie.json'),
    Path('luci-app-magpie/root/usr/share/rpcd/acl.d/luci-app-magpie.json'),
):
    json.loads(path.read_text(encoding='utf-8'))
print('LuCI/rpcd JSON: OK')
PY

# Reject credential material in files intended for source control.
if grep -RInE '(^|[[:space:]])(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN (EC |RSA )?PRIVATE KEY-----)' \
  --exclude-dir=.git --exclude='*.md' .; then
  echo 'Possible hard-coded credential material detected.' >&2
  exit 1
fi

# A front-end secret regression is a hard failure, not a warning.
if grep -nE "uci\.get\(['\"]magpie['\"].*web_key|\?k=|MAGPIE_WEB_KEY" \
  luci-app-magpie/htdocs/luci-static/resources/view/magpie/overview.js; then
  echo 'Web Console key must never be exposed to the LuCI browser bundle.' >&2
  exit 1
fi

# Upstream prints the keyed Web Console link on stdout; relaying stdout to
# syslog would put the long-term key in logread.
if grep -nE 'procd_set_param[[:space:]]+stdout[[:space:]]+1' \
  magpie/files/magpie.init; then
  echo 'Magpie stdout must not be relayed to syslog: it contains the keyed Web Console link.' >&2
  exit 1
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
fi

echo 'Repository validation: PASS'
