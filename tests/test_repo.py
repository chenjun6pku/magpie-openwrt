from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import importlib.util

spec = importlib.util.spec_from_file_location("check_versions", ROOT / "scripts/check-versions.py")
check_versions = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(check_versions)


class RepositorySecurityTests(unittest.TestCase):
    def test_upstream_source_is_pinned_to_full_git_commit(self) -> None:
        metadata = check_versions.parse_env(ROOT / "versions.env")
        recipe = (ROOT / "magpie/Makefile").read_text(encoding="utf-8")
        self.assertRegex(metadata["MAGPIE_SOURCE_COMMIT"], r"^[0-9a-f]{40}$")
        self.assertNotRegex(recipe, r"(?m)^\s*PKG_HASH\s*:?=")
        self.assertNotIn("PKG_HASH:=skip", recipe)
        self.assertEqual(
            check_versions.make_value(recipe, "PKG_SOURCE_VERSION"),
            metadata["MAGPIE_SOURCE_COMMIT"],
        )

    def test_web_key_is_not_in_uci_or_browser_bundle(self) -> None:
        uci = (ROOT / "magpie/files/magpie.config").read_text(encoding="utf-8")
        js = (ROOT / "luci-app-magpie/htdocs/luci-static/resources/view/magpie/overview.js").read_text(encoding="utf-8")
        acl = (ROOT / "luci-app-magpie/root/usr/share/rpcd/acl.d/luci-app-magpie.json").read_text(encoding="utf-8")
        self.assertNotIn("web_key", uci)
        self.assertNotIn("web_key", js)
        self.assertNotRegex(js, r"\?k=|encodeURIComponent\(key\)")
        self.assertNotIn("web_key", acl)

    def test_secret_file_is_root_only_and_not_in_public_uci(self) -> None:
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertIn("/etc/magpie/secrets/web.key", init)
        self.assertIn("chmod 0600", init)
        self.assertIn("chown root:root", init)
        self.assertIn("MAGPIE_WEB_KEY=\"$WEB_KEY\"", init)
        self.assertIn('chmod 0600 "$WEB_KEY_FILE"', init)

    def test_default_listeners_are_loopback_only(self) -> None:
        config = (ROOT / "magpie/files/magpie.config").read_text(encoding="utf-8")
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        js = (ROOT / "luci-app-magpie/htdocs/luci-static/resources/view/magpie/overview.js").read_text(encoding="utf-8")
        self.assertIn("127.0.0.1:3425", config)
        self.assertNotIn("0.0.0.0", config)
        self.assertIn("serve --web", init)
        self.assertNotIn("--web=127.0.0.1:3430", init)
        self.assertNotIn("0.0.0.0", js)

    def test_gateway_port_is_validated_before_start(self) -> None:
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertIn("gateway_addr must end with a numeric port", init)
        self.assertIn("gateway_addr port must be between 1 and 65535", init)
        self.assertIn("wildcard Gateway listeners are forbidden", init)

    def test_health_check_checks_tcp_ports(self) -> None:
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertIn("port_is_listening", init)
        self.assertIn("/proc/net/tcp", init)
        self.assertIn("/proc/net/tcp6", init)
        self.assertIn("Gateway port", init)
        self.assertIn("Web Console port 3430", init)

    def test_data_directory_cannot_overlap_secret_directory_or_traverse(self) -> None:
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertIn("/etc/magpie/secrets/*", init)
        self.assertIn("*/../*", init)
        self.assertIn("*/..", init)

    def test_unsupported_sqlite_architectures_are_rejected(self) -> None:
        recipe = (ROOT / "magpie/Makefile").read_text(encoding="utf-8")
        self.assertIn("mips%", recipe)
        self.assertIn("mipsel%", recipe)
        self.assertIn("mips64%", recipe)
        self.assertIn("mips64el%", recipe)
        self.assertIn("ppc64", recipe)

    def test_headless_server_mode(self) -> None:
        recipe = (ROOT / "magpie/Makefile").read_text(encoding="utf-8")
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertIn("GO_PKG_TAGS:=nogui", recipe)
        self.assertIn("CGO_ENABLED=0", recipe)
        self.assertIn("/usr/bin/magpie serve --web", init)

    def test_luci_package_version_matches_project(self) -> None:
        metadata = check_versions.parse_env(ROOT / "versions.env")
        luci = (ROOT / "luci-app-magpie/Makefile").read_text(encoding="utf-8")
        self.assertEqual(
            check_versions.make_value(luci, "PKG_VERSION", "luci-app-magpie/Makefile"),
            metadata["PROJECT_VERSION"],
        )

    def test_luci_makefile_has_buildpackage_signature(self) -> None:
        # OpenWrt's include/scan.mk only indexes Makefiles containing a
        # "call BuildPackage" line. Keep the package self-contained instead
        # of relying on luci.mk to emit it.
        luci = (ROOT / "luci-app-magpie/Makefile").read_text(encoding="utf-8")
        self.assertIn("$(eval $(call BuildPackage,luci-app-magpie))", luci)

    def test_luci_package_has_empty_build_compile(self) -> None:
        # The package only installs files; without an explicit empty
        # Build/Compile the OpenWrt default runs make in an empty directory.
        luci = (ROOT / "luci-app-magpie/Makefile").read_text(encoding="utf-8")
        self.assertRegex(luci, r"(?m)^define Build/Compile\nendef$")

    def test_luci_page_uses_safe_ssh_host(self) -> None:
        # E() parses string children as HTML; an angle-bracket placeholder is
        # dropped and leaves an unusable "root@" command.
        js = (ROOT / "luci-app-magpie/htdocs/luci-static/resources/view/magpie/overview.js").read_text(encoding="utf-8")
        self.assertNotIn("<router-lan-ip>", js)
        self.assertIn("window.location.hostname", js)
        self.assertIn("root@' + routerHost", js)

    def test_init_does_not_relay_stdout_to_syslog(self) -> None:
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertNotIn("procd_set_param stdout 1", init)
        self.assertIn("procd_set_param stderr 1", init)

    def test_init_migrates_legacy_v1_configuration(self) -> None:
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertIn("migrate_config", init)
        self.assertIn("magpie.main.web_key", init)
        self.assertIn("magpie.main.web_addr", init)
        self.assertIn("127.0.0.1:$port", init)

    def test_init_rejects_noncanonical_data_dir(self) -> None:
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertIn("*//*|*/./*", init)
        self.assertIn("*/../*", init)

    def test_init_rejects_expanded_wildcard_hosts(self) -> None:
        init = (ROOT / "magpie/files/magpie.init").read_text(encoding="utf-8")
        self.assertIn("is_unspecified_host", init)
        self.assertIn("0:0:0:0:0:0:0:0", init)
        self.assertIn("[fF][fF][fF][fF]", init)

    def test_build_sdk_guards_output_dir(self) -> None:
        script = (ROOT / "scripts/build-sdk.sh").read_text(encoding="utf-8")
        self.assertIn("Refusing unsafe output directory", script)
        self.assertNotIn('find "$output_dir" -maxdepth 1 -type f -delete', script)

    def test_build_sdk_does_not_build_luci_feed_chain(self) -> None:
        # luci-base's host build pulls in lucihttp, whose lua/ucode headers
        # are not in the SDK. The LuCI page is self-contained; luci-base is
        # only a runtime dependency on the target.
        script = (ROOT / "scripts/build-sdk.sh").read_text(encoding="utf-8")
        self.assertNotIn("feeds install -p luci luci-base", script)
        self.assertNotIn("feeds update packages luci magpie", script)

    def test_upgrade_notes_exist(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("Upgrading from v1", readme)


class MetadataTests(unittest.TestCase):
    def test_all_actions_are_pinned_to_full_commit_sha(self) -> None:
        for workflow in (ROOT / ".github/workflows").glob("*.yml"):
            source = workflow.read_text(encoding="utf-8")
            for line in source.splitlines():
                if "uses:" in line:
                    self.assertRegex(line, r"uses:\s+[^@\s]+@[0-9a-f]{40}(?:\s+#.*)?$")

    def test_upstream_updater_uses_pat_to_trigger_pr_ci(self) -> None:
        workflow = (ROOT / ".github/workflows/upstream-update.yml").read_text(encoding="utf-8")
        self.assertIn("secrets.MAGPIE_UPDATER_TOKEN", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("gh auth setup-git", workflow)

    def test_apk_signing_accepts_unsigned_sdk_outputs_then_verifies_both(self) -> None:
        script = (ROOT / "scripts/sign-feed.sh").read_text(encoding="utf-8")
        self.assertIn("--allow-untrusted --sign-key \"$private_key\" adbsign", script)
        self.assertIn("--reset-signatures", script)
        self.assertIn("--root \"$sdk_dir\" --keys-dir \"$keys_dir\" mkndx", script)
        self.assertIn("--keys-dir \"$keys_dir\" verify", script)
        self.assertIn("packages.adb", script)
        self.assertIn("--allow-untrusted --sign-key \"$private_key\" adbsign", script)

    def test_release_signing_is_fail_closed(self) -> None:
        workflow = (ROOT / ".github/workflows/build-apk.yml").read_text(encoding="utf-8")
        self.assertIn("MAGPIE_APK_SIGNING_KEY_B64", workflow)
        self.assertIn("REQUIRE_SIGNING", workflow)
        self.assertIn("actions: read", workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn("Require pinned OpenWrt SDK for release builds", workflow)

    def test_readme_source_pins_match_manifest(self) -> None:
        errors = check_versions.validate(tag=None, verify_upstream=False)
        self.assertEqual(errors, [])

    def test_release_tag_consistency(self) -> None:
        errors = check_versions.validate(tag="v2.0.0", verify_upstream=False)
        self.assertEqual(errors, [])

    def test_mismatched_release_tag_fails(self) -> None:
        errors = check_versions.validate(tag="openwrt-v0.1.0", verify_upstream=False)
        self.assertTrue(any("release tag mismatch" in error for error in errors))


class ApkArchitectureTests(unittest.TestCase):
    def run_arch_check(self, document: dict, package: str, arch: str) -> subprocess.CompletedProcess[str]:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".json") as stream:
            json.dump(document, stream)
            stream.flush()
            return subprocess.run(
                [sys.executable, str(ROOT / "scripts/check-apk-arch.py"), stream.name, package, arch],
                text=True,
                capture_output=True,
                check=False,
            )

    def test_magpie_x86_64_is_accepted(self) -> None:
        result = self.run_arch_check({"packages": [{"name": "magpie", "arch": "x86_64"}]}, "magpie", "x86_64")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_wrong_architecture_is_rejected(self) -> None:
        result = self.run_arch_check({"packages": [{"name": "magpie", "arch": "aarch64_cortex-a53"}]}, "magpie", "x86_64")
        self.assertNotEqual(result.returncode, 0)

    def test_luci_all_architecture_is_accepted(self) -> None:
        result = self.run_arch_check({"packages": [{"name": "luci-app-magpie", "arch": "all"}]}, "luci-app-magpie", "all")
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
