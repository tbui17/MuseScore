## 1. Wrapper Entry Points

- [x] 1.1 Add repository-root `dev.ps1` with strict error handling, repo-root resolution, concise help output, and command dispatch for only `build`, `run`, `test`, and `clean`.
- [x] 1.2 Ensure the implementation does not add a new `dev.bat` wrapper.

## 2. Build Command

- [x] 2.1 Implement `dev build` to delegate to the existing Debug build flow equivalent to `ninja_build.bat -t debug`.
- [x] 2.2 Support `dev build -j <n>` and `dev build --jobs <n>` by validating a positive integer and forwarding it to the underlying build command.
- [x] 2.3 Propagate the underlying build command exit code without adding release, install, compile-commands, packaging, or target-specific shortcuts.

## 3. Run and Test Commands

- [x] 3.1 Centralize resolution of the expected Debug executable path, initially `build.debug\src\app\MuseScoreStudio5.exe`.
- [x] 3.2 Implement `dev run [args...]` to launch the Debug executable directly and forward all remaining arguments unchanged.
- [x] 3.3 Implement a missing-executable error that prints the expected path and tells the user to run `dev build`.
- [x] 3.4 Implement `dev test <script> [args...]` to launch the Debug executable with `--test-case <script>` followed by any additional unchanged arguments.
- [x] 3.5 Validate that `dev test` fails with test-command usage when no script path is supplied.

## 4. Clean Command

- [x] 4.1 Implement clean target mapping for `debug` -> `build.debug`, `release` -> `build.release`, and `install` -> `build.install`.
- [x] 4.2 Implement `dev clean` as a dry-run preview of all three clean targets.
- [x] 4.3 Implement `dev clean <target>` as a dry-run preview of one clean target.
- [x] 4.4 Implement `--yes` confirmation for deleting selected clean targets, leaving dry-run as the default.
- [x] 4.5 Fail with clean-command usage for unknown clean targets or unsupported clean arguments.

## 5. Verification

- [x] 5.1 Verify help paths with `dev.ps1`, `dev.ps1 help`, and `dev.ps1 --help` without building MuseScore.
- [x] 5.2 Verify invalid-command and invalid-argument errors without building MuseScore.
- [x] 5.3 Verify `dev clean` dry-run output without deleting directories.
- [x] 5.4 Verify `dev run` and `dev test` missing-executable errors in an environment where the Debug executable is absent.
- [x] 5.5 Defer long build or full test execution unless explicitly requested.
