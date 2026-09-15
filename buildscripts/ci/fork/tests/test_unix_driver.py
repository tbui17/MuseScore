"""Exercise real driver control flow with controlled native command failures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("bash"), "Bash is required")
class DriverFailures(unittest.TestCase):
    def test_failure_stops_before_next_stage(self):
        driver = Path(__file__).resolve().parents[4] / "ninja_build.sh"
        for stage in ("configure", "build", "install"):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory(prefix="fork driver ") as temp:
                root = Path(temp)
                tools = root / "tools"
                tools.mkdir()
                log = root / "commands"
                (tools / "cmake").write_text('#!/bin/bash\n[[ "$1" == --version ]] && exit 0\necho configure >> "$COMMAND_LOG"\n[[ "$FAIL_STAGE" == configure ]] && exit 31\nexit 0\n')
                (tools / "ninja").write_text('#!/bin/bash\n[[ "$1" == --version ]] && exit 0\nstage=build\n[[ "$1" == install ]] && stage=install\necho "$stage" >> "$COMMAND_LOG"\n[[ "$FAIL_STAGE" == "$stage" ]] && exit 32\nexit 0\n')
                for tool in tools.iterdir():
                    tool.chmod(0o755)
                environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"], COMMAND_LOG=str(log), FAIL_STAGE=stage)
                result = subprocess.run(["bash", str(driver), "-t", "installdebug", "-j", "1"], cwd=root, env=environment, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                expected = ["configure", "build", "install"]
                self.assertEqual(log.read_text().splitlines(), expected[:expected.index(stage) + 1])


if __name__ == "__main__":
    unittest.main()
