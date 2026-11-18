#!/usr/bin/env python3
"""Open a PR when Magpie publishes a new GitHub release."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import urllib.request
from typing import Any
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API = "https://api.github.com/repos/yetone/magpie/releases/latest"

def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, check=check, text=True, capture_output=True)

def latest_release() -> tuple[str, str, str]:
    request = urllib.request.Request(API, headers={"Accept": "application/vnd.github+json", "User-Agent": "magpie-openwrt-updater"})
    with urllib.request.urlopen(request, timeout=30) as response:
        release: Any = json.load(response)
    tag = release.get("tag_name", "")
    if not isinstance(tag, str):
        raise ValueError("Upstream release tag_name is not a string")
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)", tag)
    if not match:
        raise ValueError(f"Unsupported upstream release tag: {tag!r}")
    published = release.get("published_at", "")
    if not isinstance(published, str) or not published:
        raise ValueError(f"Upstream release {tag} has no valid published_at timestamp")
    date = dt.datetime.fromisoformat(published.replace("Z", "+00:00")).date().isoformat()
    listing = run("git", "ls-remote", "https://github.com/yetone/magpie.git", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}", check=True).stdout
    refs: dict[str, str] = {
        line.split()[1]: line.split()[0]
        for line in listing.splitlines()
        if len(line.split()) == 2
    }
    commit = refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}") or ""
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError(f"Cannot resolve immutable 40-character commit for {tag}")
    return match.group(1), date, commit

def update_file(path: Path, replacements: dict[str, str], *, makefile: bool = False) -> None:
    text = path.read_text(encoding="utf-8")
    for key, value in replacements.items():
        pattern = (rf"(?m)^{re.escape(key)}=.*$") if not makefile else rf"(?m)^{re.escape(key)}\s*:?=\s*[^\r\n]+$"
        replacement = f"{key}={value}" if not makefile else f"{key}:={value}"
        text, count = re.subn(pattern, replacement, text, count=1)
        if count != 1:
            raise ValueError(f"Could not update {key} in {path.relative_to(ROOT)}")
    path.write_text(text, encoding="utf-8")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--create-pr", action="store_true", help="Commit the update and open a pull request using gh")
    args = parser.parse_args()
    version, source_date, commit = latest_release()
    metadata = ROOT / "versions.env"
    current: dict[str, str] = {}
    for line in metadata.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            current[k] = v
    if (current.get("MAGPIE_VERSION"), current.get("MAGPIE_SOURCE_DATE"), current.get("MAGPIE_SOURCE_COMMIT")) == (version, source_date, commit):
        print(f"Already pinned to Magpie v{version} ({commit}).")
        return 0

    update_file(metadata, {
        "MAGPIE_VERSION": version,
        "MAGPIE_SOURCE_DATE": source_date,
        "MAGPIE_SOURCE_COMMIT": commit,
    })
    update_file(ROOT / "magpie/Makefile", {
        "PKG_VERSION": version,
        "PKG_SOURCE_DATE": source_date,
        "PKG_SOURCE_VERSION": commit,
    }, makefile=True)
    readme = ROOT / "README.md"
    readme_text = readme.read_text(encoding="utf-8")
    readme_text, version_count = re.subn(
        r"(?m)^(\| Magpie upstream \| `)[^`]+(` \|)$",
        rf"\g<1>v{version}\g<2>", readme_text, count=1,
    )
    readme_text, commit_count = re.subn(
        r"(?m)^(\| Magpie source commit \| `)[0-9a-f]{40}(` \|)$",
        rf"\g<1>{commit}\g<2>", readme_text, count=1,
    )
    if version_count != 1 or commit_count != 1:
        raise ValueError("Could not update Magpie source pins in README.md")
    readme.write_text(readme_text, encoding="utf-8")
    print(f"Updated Magpie source pin to v{version} ({commit}).")
    if not args.create_pr:
        print("Working tree updated; pass --create-pr to create a PR.")
        return 0

    if not os.environ.get("GH_TOKEN"):
        raise RuntimeError("GH_TOKEN is required to push the update and create a pull request")
    branch = f"automation/magpie-{version}-{commit[:8]}"
    run("git", "checkout", "-B", branch)
    run("git", "add", "versions.env", "magpie/Makefile", "README.md")
    if run("git", "diff", "--cached", "--quiet", check=False).returncode != 0:
        run("git", "commit", "-m", f"chore: update Magpie to v{version}")
    else:
        print("No source changes to commit; checking whether an update PR is already open.")

    run("git", "push", "--force-with-lease", "origin", branch)
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if not repo:
        raise RuntimeError("GITHUB_REPOSITORY is required when --create-pr is used")
    existing = run(
        "gh", "pr", "list", "--repo", repo, "--head", branch,
        "--state", "open", "--json", "url", "--jq", ".[0].url", check=False,
    )
    if existing.returncode == 0 and existing.stdout.strip() and existing.stdout.strip() != "null":
        print(f"Update PR already exists: {existing.stdout.strip()}")
        return 0
    run("gh", "pr", "create", "--repo", repo, "--head", branch, "--base", "main",
        "--title", f"chore: update Magpie to v{version}",
        "--body", f"Updates the pinned upstream source to Magpie v{version}.\n\nCommit: `{commit}`\nRelease date: `{source_date}`.\n\nThe PR CI must pass both OpenWrt SDK builds before merge.")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
