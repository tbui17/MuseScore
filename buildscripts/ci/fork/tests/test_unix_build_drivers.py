"""Execute production Unix drivers with bounded build/tool stubs, never Qt.

The scripts run in workspaces containing spaces. Their parsing, environment
handoff, and stop-on-failure behavior are real Bash control flow; compiling,
packaging, and assistive-technology behavior require the separate hosted gates.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
BASH = os.environ.get("MUSE_TEST_BASH") or shutil.which("bash")
PLATFORMS = ("linux", "macos")
KEYS = ("MUSESCORE_BUILD_CRASHPAD_CLIENT", "MUSESCORE_CRASHREPORT_URL",
        "MUSE_APP_BUILD_MODE", "MUSE_APP_INSTALL_SUFFIX", "MUSESCORE_BUILD_NUMBER",
        "MUSESCORE_REVISION", "MUSESCORE_BUILD_VST_MODULE", "MUSESCORE_BUILD_WEBSOCKET",
        "MUSESCORE_BUILD_PIPEWIRE_AUDIO_DRIVER", "MUSESCORE_BUILD_UPDATE_MODULE",
        "MUSESCORE_MACOS_DEPS_PATH", "CMAKE_OSX_ARCHITECTURES", "MUSESCORE_INSTALL_DIR")


@unittest.skipUnless(BASH and os.name == "posix", "POSIX Bash is required")
class UnixBuildDriverTests(unittest.TestCase):
    def run_driver(self, platform, args, *, mode="devel", fail="", mode_file=True,
                   setup_file=True, home_spaces=False, environment=None):
        with tempfile.TemporaryDirectory(prefix="MuseScore CI ") as work, \
                tempfile.TemporaryDirectory(prefix="musescore-ci-home-") as home:
            root = Path(work)
            home = root / "home with spaces" if home_spaces else Path(home)
            tools = root / "tools"
            tools.mkdir()
            (home / "build_tools").mkdir(parents=True)
            (root / "build.artifacts/env").mkdir(parents=True)
            if mode_file:
                (root / "build.artifacts/env/build_mode.env").write_text(mode + "\n")
            log = 'printf "%s\\n" "{stage}" >> "$STAGES_FILE"\n'
            failure = '[ "$FAIL_STAGE" != "{stage}" ] || exit 37\n'
            if setup_file:
                (home / "build_tools/environment.sh").write_text(
                    log.format(stage="environment") + failure.format(stage="environment"))
            git = tools / "git"
            git.write_text("#!/usr/bin/env bash\n" + log.format(stage="git")
                           + failure.format(stage="git") + "printf '%s\\n' abc1234\n")
            git.chmod(0o755)
            capture = root / "capture.py"
            capture.write_text("import json, os, sys\nfrom pathlib import Path\n"
                               + "keys = " + repr(KEYS) + "\n"
                               + "Path('build-env.json').write_text(json.dumps({"
                                 "'env': {k: os.environ.get(k) for k in keys}, 'args': sys.argv[1:]}))\n")
            (root / "ninja_build.sh").write_text(
                log.format(stage="build") + '"$TEST_PYTHON" "$CAPTURE_SCRIPT" "$@" || exit 1\n'
                + failure.format(stage="build"))
            helpers = root / "buildscripts/ci/tools"
            helpers.mkdir(parents=True)
            for name, stage in (("make_release_channel_env.sh", "release"),
                                ("make_version_env.sh", "version"),
                                ("make_revision_env.sh", "revision"),
                                ("make_branch_env.sh", "branch")):
                (helpers / name).write_text(log.format(stage=stage) + failure.format(stage=stage))
            env = {k: v for k, v in os.environ.items()
                   if not k.startswith(("MUSESCORE_", "MUSE_APP_", "BASH_FUNC_"))
                   and k not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "BUILD_NUMBER", "PACKARCH")}
            env.update(HOME=str(home), PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       TEST_PYTHON=sys.executable, CAPTURE_SCRIPT=str(capture),
                       STAGES_FILE=str(root / "stages.txt"), FAIL_STAGE=fail)
            env.update(environment or {})
            driver = ROOT / "buildscripts/ci" / platform / "build.sh"
            result = subprocess.run([BASH, str(driver), *args], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=15, check=False)
            data = root / "build-env.json"
            stages = root / "stages.txt"
            return (result, json.loads(data.read_text()) if data.exists() else None,
                    stages.read_text().splitlines() if stages.exists() else [])

    def assert_build(self, platform, args, **kwargs):
        result, data, stages = self.run_driver(platform, args, **kwargs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNotNone(data)
        self.assertEqual(stages, self.stages(platform))
        self.assertEqual(data["args"], ["-t", "appimage" if platform == "linux" else "install"])
        self.assertEqual(data["env"]["MUSESCORE_BUILD_VST_MODULE"], "ON")
        self.assertEqual(data["env"]["MUSESCORE_BUILD_WEBSOCKET"], "ON")
        self.assertEqual(data["env"]["MUSESCORE_REVISION"], "abc1234")
        return result, data["env"]

    @staticmethod
    def stages(platform):
        return (["environment"] if platform == "linux" else []) + [
            "git", "build", "release", "version", "revision", "branch"]

    def test_absent_url_keeps_crashpad_off(self):
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                _, env = self.assert_build(platform, ["-n", "42"])
                self.assertEqual(env["MUSESCORE_BUILD_CRASHPAD_CLIENT"], "OFF")
                self.assertEqual(env["MUSESCORE_CRASHREPORT_URL"], "")

    def test_empty_and_legacy_quote_sentinels_keep_crashpad_off(self):
        for platform in PLATFORMS:
            for url in ("", "''", '""'):
                with self.subTest(platform=platform, url=url):
                    _, env = self.assert_build(platform, ["-n", "42", "--crash_log_url", url])
                    self.assertEqual(env["MUSESCORE_BUILD_CRASHPAD_CLIENT"], "OFF")
                    self.assertEqual(env["MUSESCORE_CRASHREPORT_URL"], "")

    def test_real_url_preserves_value_and_explicitly_enables_crashpad(self):
        url = "https://example.invalid/report?a=one&b=two!&literal=$(echo not-executed)"
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                result, env = self.assert_build(platform, ["--crash_log_url", url, "--number", "42"])
                self.assertEqual(env["MUSESCORE_BUILD_CRASHPAD_CLIENT"], "ON")
                self.assertEqual(env["MUSESCORE_CRASHREPORT_URL"], url)
                self.assertNotIn(url, result.stdout + result.stderr)

    def test_last_url_wins_in_both_directions(self):
        for platform in PLATFORMS:
            for urls, enabled in ((("https://example.invalid/", "''"), "OFF"),
                                  (("", "https://example.invalid/"), "ON")):
                with self.subTest(platform=platform, urls=urls):
                    _, env = self.assert_build(platform, ["-n", "42", "--crash_log_url", urls[0],
                                                         "--crash_log_url", urls[1]])
                    self.assertEqual(env["MUSESCORE_BUILD_CRASHPAD_CLIENT"], enabled)
                    self.assertEqual(env["MUSESCORE_CRASHREPORT_URL"], "" if enabled == "OFF" else urls[1])

    def test_missing_values_fail_before_any_build(self):
        for platform in PLATFORMS:
            for args in ([], ["-n"], ["-n", "42", "--crash_log_url"],
                         ["--crash_log_url", "--number", "42"]):
                with self.subTest(platform=platform, args=args):
                    result, data, stages = self.run_driver(platform, args)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIsNone(data)
                    self.assertEqual(stages, [])

    def test_unknown_options_fail_before_build(self):
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                result, data, stages = self.run_driver(platform, ["-n", "42", "--typo"])
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(data)
                self.assertEqual(stages, [])

    def test_invalid_build_number_is_rejected(self):
        for platform in PLATFORMS:
            for value in ("", "abc", "42 43", "-1", "42;echo nope"):
                with self.subTest(platform=platform, value=value):
                    result, data, stages = self.run_driver(platform, ["-n", value])
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIsNone(data)
                    self.assertEqual(stages, [])

    def test_all_supported_build_modes_keep_their_mapping(self):
        for platform in PLATFORMS:
            for mode, expected, suffix in (("devel", "dev", "dev"), ("nightly", "dev", "nightly"),
                                           ("testing", "testing", "testing"), ("stable", "release", "")):
                with self.subTest(platform=platform, mode=mode):
                    _, env = self.assert_build(platform, ["-n", "42"], mode=mode)
                    self.assertEqual(env["MUSE_APP_BUILD_MODE"], expected)
                    if platform == "linux":
                        self.assertEqual(env["MUSE_APP_INSTALL_SUFFIX"], suffix)

    def test_invalid_or_missing_mode_stops_before_build(self):
        for platform in PLATFORMS:
            for options in ({"mode": "typo"}, {"mode": ""}, {"mode_file": False}):
                with self.subTest(platform=platform, options=options):
                    result, data, stages = self.run_driver(platform, ["-n", "42"], **options)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIsNone(data)
                    self.assertEqual(stages, [])

    def test_linux_explicit_mode_does_not_require_mode_file(self):
        _, env = self.assert_build("linux", ["-n", "42", "--build_mode", "stable"], mode_file=False)
        self.assertEqual(env["MUSE_APP_BUILD_MODE"], "release")

    def test_home_and_workspace_paths_with_spaces(self):
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                _, env = self.assert_build(platform, ["-n", "42"], home_spaces=True)
                if platform == "macos":
                    self.assertIn("home with spaces/musescore_deps_macos", env["MUSESCORE_MACOS_DEPS_PATH"])

    def test_linux_missing_environment_stops_before_build(self):
        result, data, stages = self.run_driver("linux", ["-n", "42"], setup_file=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(data)
        self.assertEqual(stages, [])

    def test_each_failed_stage_prevents_later_commands(self):
        for platform in PLATFORMS:
            expected = self.stages(platform)
            for stage in expected:
                with self.subTest(platform=platform, stage=stage):
                    result, _, stages = self.run_driver(platform, ["-n", "42"], fail=stage)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(stages, expected[:expected.index(stage) + 1])

    def test_linux_architecture_and_pipewire_policy_is_preserved(self):
        for arch, expected in (("x86_64", "ON"), ("aarch64", "OFF")):
            with self.subTest(arch=arch):
                _, env = self.assert_build("linux", ["-n", "42", "--arch", arch, "--build-pipewire"])
                self.assertEqual(env["MUSESCORE_BUILD_UPDATE_MODULE"], expected)
                self.assertEqual(env["MUSESCORE_BUILD_PIPEWIRE_AUDIO_DRIVER"], "ON")
        _, env = self.assert_build("linux", ["-n", "42"])
        self.assertEqual(env["MUSESCORE_BUILD_PIPEWIRE_AUDIO_DRIVER"], "OFF")

    def test_macos_universal_architecture_and_install_path_are_preserved(self):
        _, env = self.assert_build("macos", ["-n", "42"])
        self.assertEqual(env["CMAKE_OSX_ARCHITECTURES"], "arm64;x86_64")
        self.assertEqual(env["MUSESCORE_INSTALL_DIR"], "../applebuild")

    def test_inherited_crashpad_flag_cannot_enable_absent_url(self):
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                _, env = self.assert_build(platform, ["-n", "42"],
                                           environment={"MUSESCORE_BUILD_CRASHPAD_CLIENT": "ON"})
                self.assertEqual(env["MUSESCORE_BUILD_CRASHPAD_CLIENT"], "OFF")


if __name__ == "__main__":
    unittest.main()
