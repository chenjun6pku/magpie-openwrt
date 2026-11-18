#!/usr/bin/env python3
"""Validate architecture metadata in an OpenWrt 25.12 APKv3/ADB package."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from collections.abc import Iterator
from typing import Any


def walk(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def main() -> int:
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <adbdump-json> <package-name> <expected-arch>", file=sys.stderr)
        return 2

    json_path, expected_name, expected_arch = sys.argv[1:]
    try:
        document = json.loads(Path(json_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Cannot parse apk adbdump JSON: {exc}", file=sys.stderr)
        return 1

    found_arches: list[str] = []
    for item in walk(document):
        name = item.get("name") or item.get("pkgname") or item.get("P")
        arch = item.get("arch") or item.get("architecture") or item.get("A")
        if name == expected_name and isinstance(arch, str):
            found_arches.append(arch)

    if not found_arches:
        print(f"Package '{expected_name}' with an arch field not found in APK metadata", file=sys.stderr)
        return 1

    # A LuCI package may be serialized as `all` or `noarch`, depending on the
    # APK metadata mapping used by the selected OpenWrt point release.
    accepted = {expected_arch}
    if expected_arch == "all":
        accepted = {"all", "noarch"}

    if any(arch not in accepted for arch in found_arches):
        print(
            f"Package '{expected_name}' has arch {found_arches}; expected one of {sorted(accepted)}",
            file=sys.stderr,
        )
        return 1

    print(f"{expected_name}: APK architecture {found_arches[0]} (OK)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
