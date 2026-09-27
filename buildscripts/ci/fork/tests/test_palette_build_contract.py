"""Run real CMake/Bash/CTest control flow; these fixtures do not compile Qt."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
CMAKE = shutil.which("cmake")
CTEST = shutil.which("ctest")
BASH = shutil.which("bash")


@unittest.skipUnless(CMAKE, "CMake is required")
class PaletteRegistrationTests(unittest.TestCase):
    def configure(self, *, tests=True, ui=True, appshell=False, already_registered=False):
        with tempfile.TemporaryDirectory(prefix="palette registration ") as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            # Only module traversal is stubbed: execute the actual src/CMakeLists.txt
            # predicates in a real configure, without compiling or finding Qt.
            (source / "CMakeLists.txt").write_text(r'''cmake_minimum_required(VERSION 3.20)
project(PaletteRegistration NONE)
if(ALREADY_REGISTERED)
    add_custom_target(muse_appshell_qml_tests)
endif()
function(add_subdirectory path)
    if(path STREQUAL "appshell/qml/MuseScore/AppShell/tests")
        file(APPEND "${CMAKE_BINARY_DIR}/registrations.txt" "palette\n")
        add_custom_target(muse_appshell_qml_tests)
    endif()
endfunction()
include("${REPOSITORY_ROOT}/src/CMakeLists.txt")
if(EXPECT_TARGET AND NOT TARGET muse_appshell_qml_tests)
    message(FATAL_ERROR "Required native palette target was not registered")
elseif(NOT EXPECT_TARGET AND TARGET muse_appshell_qml_tests)
    message(FATAL_ERROR "Palette target must not be added without Qt/unit tests")
endif()
''')
            build = root / "build"
            args = [CMAKE, "-S", str(source), "-B", str(build),
                    "-DREPOSITORY_ROOT=" + str(ROOT),
                    "-DMUSE_ENABLE_UNIT_TESTS=" + ("ON" if tests else "OFF"),
                    "-DMUSE_MODULE_UI=" + ("ON" if ui else "OFF"),
                    "-DMUE_BUILD_APPSHELL_MODULE=" + ("ON" if appshell else "OFF"),
                    "-DALREADY_REGISTERED=" + ("ON" if already_registered else "OFF"),
                    "-DEXPECT_TARGET=" + ("ON" if tests and ui else "OFF")]
            result = subprocess.run(args, text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record = build / "registrations.txt"
            expected = ["palette"] if tests and ui and not already_registered else []
            self.assertEqual(record.read_text().splitlines() if record.exists() else [], expected)

    def test_utest_registers_palette_with_full_appshell_disabled(self):
        self.configure()

    def test_full_app_registers_palette_when_qml_did_not(self):
        self.configure(appshell=True)

    def test_existing_qml_registration_is_not_duplicated(self):
        self.configure(appshell=True, already_registered=True)

    def test_disabled_unit_tests_do_not_register_palette(self):
        self.configure(tests=False)

    def test_without_qt_does_not_register_palette(self):
        self.configure(ui=False)


@unittest.skipUnless(BASH, "Bash is required")
class NativeSuiteGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="native suite gate ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        (self.home / "build_tools").mkdir(parents=True)
        (self.home / "build_tools/environment.sh").write_text("# isolated fixture\n")
        (self.root / "build.debug").mkdir()
        self.tools = self.root / "tools"
        self.tools.mkdir()
        self.log = self.root / "ctest-calls"
        stub = self.tools / "ctest"
        stub.write_text(r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$COMMAND_LOG"
if [[ "$*" == *"-R ^muse_appshell_qml_tests$"* ]]; then
    [[ "$FAIL_STAGE" == palette ]] && exit 8
else
    [[ "$FAIL_STAGE" == all ]] && exit 9
fi
exit 0
''')
        stub.chmod(0o755)

    def run_driver(self, failure="", *, real_ctest=False):
        environment = dict(os.environ, HOME=str(self.home), COMMAND_LOG=str(self.log), FAIL_STAGE=failure)
        if not real_ctest:
            environment["PATH"] = str(self.tools) + os.pathsep + os.environ["PATH"]
        return subprocess.run([BASH, str(ROOT / "buildscripts/ci/linux/runutests.sh")],
                              cwd=self.root, env=environment, capture_output=True, text=True, timeout=20)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_required_palette_gate_precedes_full_suite(self):
        result = self.run_driver()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), ["--no-tests=error -R ^muse_appshell_qml_tests$ --output-junit test-results/palette.xml -V",
                                       "--no-tests=error --output-junit test-results/all.xml -V"])

    def test_palette_failure_stops_before_full_suite(self):
        result = self.run_driver("palette")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), ["--no-tests=error -R ^muse_appshell_qml_tests$ --output-junit test-results/palette.xml -V"])

    def test_full_suite_failure_still_fails(self):
        result = self.run_driver("all")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 2)

    def test_missing_environment_fails_without_running_tests(self):
        (self.home / "build_tools/environment.sh").unlink()
        result = self.run_driver()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_missing_build_fails_without_running_tests(self):
        (self.root / "build.debug").rmdir()
        result = self.run_driver()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    @unittest.skipUnless(CTEST and CMAKE, "CTest and CMake are required")
    def test_real_ctest_rejects_missing_palette_even_with_another_passing_test(self):
        marker = self.root / "unrelated-suite-ran"
        testfile = self.root / "build.debug/CTestTestfile.cmake"
        testfile.write_text('add_test(unrelated "' + Path(CMAKE).as_posix()
                            + '" "-E" "touch" "' + marker.as_posix() + '")\n')
        result = self.run_driver(real_ctest=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(marker.exists(), "A missing palette suite must stop the full run")


if __name__ == "__main__":
    unittest.main()
