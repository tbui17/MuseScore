"""Native cmd.exe tests of the real Windows driver parser and failure tail.

No compiler, Qt, network or application is invoked. The production parser is
copied verbatim into a scratch batch file; only subsequent build work is omitted.
The production build/metadata tail is exercised separately with bounded stubs.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
DRIVER = ROOT / "buildscripts/ci/windows/build.bat"
COMSPEC = os.environ.get("COMSPEC", "")
WINDOWS_COMMANDS = os.name == "nt" and Path(COMSPEC).is_file()
FIELDS = ("BUILD_NUMBER", "TARGET_PROCESSOR_BITS", "BUILD_WIN_PORTABLE",
          "BUILD_CRASHPAD_CLIENT", "CRASH_LOG_SERVER_URL")


def run_cmd(script, args=(), *, cwd, unquoted_options=False):
    # Test inputs are literal and always quoted for cmd, including empty values
    # and URL metacharacters. list2cmdline targets the C runtime, not cmd syntax.
    if any('"' in value for value in args):
        raise ValueError("This fixture does not accept embedded double quotes")
    quoted_args = " ".join(value if unquoted_options and re.fullmatch(r"--?[A-Za-z_]+", value)
                           else '"' + value + '"' for value in args)
    command = f'"{COMSPEC}" /d /s /c ""{script}" {quoted_args}"'
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True,
                          timeout=10, check=False)


@unittest.skipUnless(WINDOWS_COMMANDS, "Native Windows cmd.exe is required")
class WindowsParserTests(unittest.TestCase):
    def parse(self, args, source=None, *, unquoted_options=False):
        source = DRIVER.read_text() if source is None else source
        boundary = "SET /p BUILD_MODE="
        self.assertEqual(source.count(boundary), 1, "Driver parser boundary changed; update the fixture")
        prefix = source.split(boundary, 1)[0]
        with tempfile.TemporaryDirectory(prefix="MuseScore parser ") as temp:
            script = Path(temp) / "parser fixture.bat"
            trailer = "\nECHO PARSER_REACHED_END\n" + "\n".join("SET " + key for key in FIELDS) + "\nEXIT /b 0\n"
            script.write_text(prefix + trailer, newline="\r\n")
            result = run_cmd(script, args, cwd=temp, unquoted_options=unquoted_options)
        fields = {}
        for line in result.stdout.splitlines():
            key, sep, value = line.partition("=")
            if sep and key in FIELDS:
                fields[key] = value
        return result, fields

    def assert_ok(self, args):
        result, fields = self.parse(args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PARSER_REACHED_END", result.stdout)
        return fields

    def test_default_build_does_not_enable_crashpad(self):
        fields = self.assert_ok(["-n", "42"])
        self.assertEqual(fields["BUILD_NUMBER"], "42")
        self.assertEqual(fields["TARGET_PROCESSOR_BITS"], "64")
        self.assertEqual(fields["BUILD_WIN_PORTABLE"], "OFF")
        self.assertEqual(fields["BUILD_CRASHPAD_CLIENT"], "OFF")

    def test_options_can_appear_in_either_order(self):
        cases = [["-n", "42", "-b", "32", "--portable", "ON"],
                 ["--portable", "ON", "-b", "32", "-n", "42"]]
        for args in cases:
            with self.subTest(args=args):
                fields = self.assert_ok(args)
                self.assertEqual(fields["BUILD_NUMBER"], "42")
                self.assertEqual(fields["TARGET_PROCESSOR_BITS"], "32")
                self.assertEqual(fields["BUILD_WIN_PORTABLE"], "ON")
                self.assertEqual(fields["BUILD_CRASHPAD_CLIENT"], "OFF")

    def test_empty_workflow_crash_url_keeps_client_off(self):
        fields = self.assert_ok(["-n", "42", "--crash_log_url", ""])
        self.assertEqual(fields["BUILD_CRASHPAD_CLIENT"], "OFF")
        self.assertEqual(fields.get("CRASH_LOG_SERVER_URL", ""), "")

    def test_nonempty_url_is_not_double_quoted_or_truncated(self):
        url = "https://example.invalid/report?a=1&b=2!"
        fields = self.assert_ok(["--crash_log_url", url, "-n", "42"])
        self.assertEqual(fields["BUILD_CRASHPAD_CLIENT"], "ON")
        self.assertEqual(fields["CRASH_LOG_SERVER_URL"], url)

    def test_later_empty_url_clears_previous_crash_configuration(self):
        fields = self.assert_ok(["-n", "42", "--crash_log_url", "https://example.invalid/",
                                 "--crash_log_url", ""])
        self.assertEqual(fields["BUILD_CRASHPAD_CLIENT"], "OFF")
        self.assertEqual(fields.get("CRASH_LOG_SERVER_URL", ""), "")

    def test_missing_required_values_are_rejected(self):
        for args in ([], ["-n"], ["-n", ""], ["-n", "42", "-b"], ["-n", "42", "--portable"]):
            with self.subTest(args=args):
                result, _ = self.parse(args)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("PARSER_REACHED_END", result.stdout)

    def test_invalid_option_values_are_rejected(self):
        for args in (["-n", "abc"], ["-n", "42", "-b", "16"], ["-n", "42", "--portable", "MAYBE"]):
            with self.subTest(args=args):
                result, _ = self.parse(args)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("PARSER_REACHED_END", result.stdout)

    def test_unknown_options_are_not_silently_discarded(self):
        result, _ = self.parse(["-n", "42", "--unknown", "value"])
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PARSER_REACHED_END", result.stdout)

    def test_option_names_are_case_insensitive(self):
        fields = self.assert_ok(["-N", "42", "--PORTABLE", "on"])
        self.assertEqual(fields["BUILD_NUMBER"], "42")
        self.assertEqual(fields["BUILD_WIN_PORTABLE"].upper(), "ON")
        self.assertEqual(fields["BUILD_CRASHPAD_CLIENT"], "OFF")

    def test_negative_control_reproduces_old_empty_url_activation(self):
        # Use the old expression and the workflow's unquoted option name.
        # Quoting it here would double-wrap %1 in the old expression and
        # prevent the option comparison from matching at all.
        old = ('@echo off\nSET "BUILD_CRASHPAD_CLIENT=OFF"\n'
               'IF /I "%1" == "--crash_log_url" SET CRASH_LOG_SERVER_URL=%2 & SET BUILD_CRASHPAD_CLIENT=ON & SHIFT & SHIFT\n'
               'SET /p BUILD_MODE=unused\n')
        result, fields = self.parse(["--crash_log_url", ""], source=old, unquoted_options=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(fields["BUILD_CRASHPAD_CLIENT"].strip(), "ON")


@unittest.skipUnless(WINDOWS_COMMANDS, "Native Windows cmd.exe is required")
class WindowsFailurePropagationTests(unittest.TestCase):
    def run_tail(self, failed_stage):
        source = DRIVER.read_text()
        start = "CALL ninja_build.bat -t installrelwithdebinfo"
        self.assertEqual(source.count(start), 1, "Build dispatch boundary changed; update the fixture")
        tail = start + source.split(start, 1)[1]
        with tempfile.TemporaryDirectory(prefix="MuseScore driver ") as temp:
            root = Path(temp)
            # Git Bash is supplied by the Windows runner; do not use a WSL shim.
            git_bash = Path(os.environ.get("PROGRAMFILES", r"C:\Program Files")) / "Git/bin/bash.exe"
            self.assertTrue(git_bash.is_file(), "Windows hosted runner must provide Git Bash")
            header = ('@echo off\nSET "MUSE_APP_BUILD_MODE=dev"\nSET "BUILD_NUMBER=42"\n'
                      f'SET "PATH={git_bash.parent};%PATH%"\n')
            script = root / "driver tail.bat"
            script.write_text(header + tail, newline="\r\n")
            exit_code = 37 if failed_stage == "build" else 0
            (root / "ninja_build.bat").write_text(f"@echo off\necho build>>stages.txt\nexit /b {exit_code}\n", newline="\r\n")
            tools = root / "buildscripts/ci/tools"
            tools.mkdir(parents=True)
            for name, stage in (("make_release_channel_env.sh", "release"),
                                ("make_version_env.sh", "version"), ("make_branch_env.sh", "branch")):
                code = 38 if failed_stage == stage else 0
                (tools / name).write_text(f"printf '%s\\n' '{stage}' >> stages.txt\nexit {code}\n")
            result = run_cmd(script, cwd=root)
            stages = (root / "stages.txt").read_text().splitlines()
        return result, stages

    def test_success_runs_all_metadata_steps(self):
        result, stages = self.run_tail("")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(stages, ["build", "release", "version", "branch"])

    def test_each_failure_stops_before_the_next_step(self):
        expected = ["build", "release", "version", "branch"]
        for stage in expected:
            with self.subTest(stage=stage):
                result, stages = self.run_tail(stage)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(stages, expected[:expected.index(stage) + 1])


if __name__ == "__main__":
    unittest.main()
