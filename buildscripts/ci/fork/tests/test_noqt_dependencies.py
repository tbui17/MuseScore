"""Exercise the no-Qt bootstrap with real CMake and controlled recipe stubs.

No external payloads are downloaded and no MuseScore/Qt project is built here.
Hosted Build: Without Qt is still required to validate the real dependency closure.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
CMAKE = shutil.which("cmake")
HELPER = ROOT / "tools/check_build_without_qt/SetupDependencies.cmake"
ENTRYPOINT = ROOT / "tools/check_build_without_qt/CMakeLists.txt"


@unittest.skipUnless(CMAKE, "CMake is required for dependency registration checks")
class NoQtDependencyTests(unittest.TestCase):
    def configure(self, *, missing="", fail="", qt=False):
        with tempfile.TemporaryDirectory(prefix="noqt dependency fixture ") as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            framework = root / "pinned-framework"
            modules = framework / "buildscripts/cmake"
            modules.mkdir(parents=True)
            (modules / "MuseDeps.cmake").write_text(r'''
function(populate name)
    file(APPEND "${CMAKE_BINARY_DIR}/populated.txt" "${name}\n")
    if(name STREQUAL FAIL_DEPENDENCY)
        message(FATAL_ERROR "Controlled pinned-payload failure: ${name}")
    endif()
    if(NOT name STREQUAL MISSING_TARGET)
        add_library(${name} INTERFACE)
    endif()
endfunction()
''')
            (source / "CMakeLists.txt").write_text(r'''
cmake_minimum_required(VERSION 3.20)
project(NoQtDependencyContract NONE)
include("${HELPER}")
include("${HELPER}")
foreach(name IN ITEMS picojson pugixml utfcpp)
    if(NOT TARGET ${name})
        message(FATAL_ERROR "Consumer cannot see ${name}")
    endif()
endforeach()
''')
            build = root / "build"
            result = subprocess.run([CMAKE, "-S", str(source), "-B", str(build),
                                     "-DHELPER=" + str(HELPER), "-DMUSE_FRAMEWORK_PATH=" + str(framework),
                                     "-DMISSING_TARGET=" + missing, "-DFAIL_DEPENDENCY=" + fail,
                                     "-DMUSE_QT_SUPPORT=" + ("ON" if qt else "OFF")],
                                    text=True, capture_output=True, timeout=20, check=False)
            calls = build / "populated.txt"
            return result, calls.read_text().splitlines() if calls.exists() else []

    def test_minimal_dependencies_are_populated_before_consumers(self):
        result, calls = self.configure()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, ["picojson", "pugixml", "utfcpp"])

    def test_repeated_include_does_not_create_duplicate_targets(self):
        result, calls = self.configure()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(calls), len(set(calls)))

    def test_missing_required_target_fails_at_configuration(self):
        dependencies = ["picojson", "pugixml", "utfcpp"]
        for dependency in dependencies:
            with self.subTest(dependency=dependency):
                result, calls = self.configure(missing=dependency)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("required target: " + dependency, result.stderr)
                self.assertEqual(calls, dependencies[:dependencies.index(dependency) + 1])

    def test_pinned_payload_failure_is_not_swallowed(self):
        result, calls = self.configure(fail="pugixml")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Controlled pinned-payload failure: pugixml", result.stderr)
        self.assertEqual(calls, ["picojson", "pugixml"])

    def test_qt_configuration_is_rejected_before_populating(self):
        result, calls = self.configure(qt=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("only for the no-Qt check", result.stderr)
        self.assertEqual(calls, [])

    def test_standalone_entrypoint_wires_bootstrap_before_global_module(self):
        source = ENTRYPOINT.read_text()
        include = "include(${CMAKE_CURRENT_LIST_DIR}/SetupDependencies.cmake)"
        self.assertEqual(source.count(include), 1)
        self.assertLess(source.index("set(MUSE_QT_SUPPORT OFF)"), source.index(include))
        self.assertLess(source.index(include), source.index("add_subdirectory(${MUSE_FRAMEWORK_SRC_PATH}/global global)"))


if __name__ == "__main__":
    unittest.main()
