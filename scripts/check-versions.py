#!/usr/bin/env python3
"""Validate the project release metadata, package recipe and upstream tag."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def parse_env(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Malformed metadata line: {line}")
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip().strip("\"'")
    return result

def make_value(source: str, name: str, filename: str = "magpie/Makefile") -> str:
    match = re.search(rf"(?m)^{re.escape(name)}\s*:?=\s*(\S+)\s*$", source)
    if not match:
        raise ValueError(f"{name} not found in {filename}")
    return match.group(1)

def resolve_tag_commit(version: str) -> str:
    tag = f"v{version}"
    raw = subprocess.check_output(
        ["git", "ls-remote", "https://github.com/yetone/magpie.git", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}"],
        text=True,
        timeout=60,
    )
    refs = {line.split()[1]: line.split()[0] for line in raw.splitlines() if len(line.split()) == 2}
    return refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}") or ""

def validate(*, tag: str | None, verify_upstream: bool) -> list[str]:
    meta = parse_env(ROOT / "versions.env")
    recipe = (ROOT / "magpie/Makefile").read_text(encoding="utf-8")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    errors: list[str] = []

    required = ("PROJECT_VERSION", "OPENWRT_VERSION", "MAGPIE_VERSION", "MAGPIE_SOURCE_DATE", "MAGPIE_SOURCE_COMMIT")
    for key in required:
        if not meta.get(key):
            errors.append(f"versions.env missing {key}")

    expected = {
        "PKG_VERSION": meta.get("MAGPIE_VERSION", ""),
        "PKG_SOURCE_DATE": meta.get("MAGPIE_SOURCE_DATE", ""),
        "PKG_SOURCE_VERSION": meta.get("MAGPIE_SOURCE_COMMIT", ""),
    }
    for key, value in expected.items():
        try:
            actual = make_value(recipe, key)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        if actual != value:
            errors.append(f"{key} mismatch: Makefile={actual}, versions.env={value}")

    luci_recipe = (ROOT / "luci-app-magpie/Makefile").read_text(encoding="utf-8")
    try:
        luci_version = make_value(luci_recipe, "PKG_VERSION", "luci-app-magpie/Makefile")
    except ValueError as exc:
        errors.append(str(exc))
    else:
        if luci_version != meta.get("PROJECT_VERSION"):
            errors.append(
                "luci-app-magpie PKG_VERSION mismatch: package="
                f"{luci_version}, PROJECT_VERSION={meta.get('PROJECT_VERSION', '')}"
            )

    if re.search(r"(?m)^\s*PKG_HASH\s*:?=", recipe):
        errors.append("PKG_HASH placeholder/override is forbidden; use the pinned Git commit source")
    if f"| Magpie upstream | `v{meta.get('MAGPIE_VERSION', '')}` |" not in readme:
        errors.append("README.md Magpie upstream version does not match versions.env")
    if f"| Magpie source commit | `{meta.get('MAGPIE_SOURCE_COMMIT', '')}` |" not in readme:
        errors.append("README.md Magpie source commit does not match versions.env")
    if not re.fullmatch(r"[0-9a-f]{40}", meta.get("MAGPIE_SOURCE_COMMIT", "")):
        errors.append("MAGPIE_SOURCE_COMMIT must be a full 40-character lowercase Git commit SHA")

    if tag:
        wanted = f"v{meta.get('PROJECT_VERSION', '')}"
        if tag != wanted:
            errors.append(f"release tag mismatch: got {tag}, expected {wanted}")

    if verify_upstream:
        try:
            resolved = resolve_tag_commit(meta["MAGPIE_VERSION"])
        except (subprocess.SubprocessError, OSError, KeyError) as exc:
            errors.append(f"could not resolve upstream release tag: {exc}")
        else:
            if resolved != meta["MAGPIE_SOURCE_COMMIT"]:
                errors.append(
                    f"upstream tag v{meta['MAGPIE_VERSION']} resolves to {resolved or '(missing)'}, "
                    f"but versions.env pins {meta['MAGPIE_SOURCE_COMMIT']}"
                )
    return errors

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="Validate a repository release tag (for example v2.0.0)")
    parser.add_argument("--verify-upstream", action="store_true", help="Resolve the upstream Git tag and compare its commit")
    args = parser.parse_args()
    errors = validate(tag=args.tag, verify_upstream=args.verify_upstream)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("Version metadata and pinned source: OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
