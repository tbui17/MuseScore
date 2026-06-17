## Context

MuseScore already has a Windows build wrapper, `ninja_build.bat`, which locates Visual Studio with `vswhere.exe`, calls `vcvars64.bat`, and invokes `ninja_build.ps1`. The PowerShell build script contains the real CMake/Ninja configuration logic, including Debug and Release build directories, install prefix handling, and build environment variables.

The new `dev` wrapper is a daily-development convenience layer, not a replacement build system. It should make the common Windows loop discoverable without moving CMake configuration details out of the existing scripts.

## Goals / Non-Goals

**Goals:**

- Provide a small repository-root `dev.ps1` command for humans and agents on Windows.
- Support only the daily v1 commands: `build`, `run`, `test`, and `clean`.
- Default all build-related behavior to Debug and `build.debug`.
- Avoid touching `build.install` except when `dev clean` is asked to delete it.
- Preserve existing build behavior by delegating Debug builds to the current build wrapper.
- Keep command help short enough to replace detailed build instructions in agent-facing documentation.

**Non-Goals:**

- No release-build shortcut in v1.
- No install shortcut in v1.
- No `compile_commands.json` or editor/LSP setup shortcut in v1.
- No full unit-test-suite runner in v1.
- No packaging, installer, or braille installer workflow support.
- No new CMake targets or changes to `ninja_build.ps1` configuration semantics.

## Decisions

### Use `dev.ps1` as the only dev wrapper entry point

`dev.ps1` SHALL live at the repository root and SHALL be the only new wrapper file. It SHALL parse the daily commands directly and SHALL not add a parallel `dev.bat` entry point.

Alternative considered: add a `dev.bat` shim to set up MSVC before invoking PowerShell. This would duplicate existing batch-wrapper behavior and add another entry point. The v1 design favors one script and delegates build environment setup to the existing `ninja_build.bat` path when building.

### Keep `dev.ps1` as a command dispatcher, not a build reimplementation

`dev.ps1` SHALL parse `build`, `run`, `test`, `clean`, and `help` behavior. It SHALL NOT duplicate the CMake configure arguments from `ninja_build.ps1`.

Alternative considered: reimplement Debug build invocation directly in `dev.ps1`. This would make `dev build` shorter internally, but it would create a second source of truth for CMake options and environment variables.

### Delegate `dev build` to the existing Debug build target

`dev build` SHALL invoke the existing build wrapper for the Debug target. It SHALL pass through an optional `-j` or `--jobs` value to limit parallel jobs.

The expected delegation is equivalent to:

```powershell
.\ninja_build.bat -t debug [-j <jobs>]
```

The command SHALL propagate the build exit code.

### Run from the Debug build tree, not from `build.install`

`dev run` SHALL execute the Debug app binary from the Debug build output tree and SHALL pass all remaining arguments to the executable unchanged.

The initial expected Windows path is:

```text
build.debug\src\app\MuseScoreStudio5.exe
```

If the executable is missing, `dev run` SHALL fail fast with a message that shows the expected path and tells the user to run `dev build`. It SHALL NOT auto-build or auto-install.

Alternative considered: run from `build.install\bin\MuseScoreStudio5.exe`. This matches install/debugger staging paths but makes normal development depend on the install step. The v1 wrapper intentionally avoids `build.install` for daily run/test commands.

### Keep `dev test` scoped to app-level test-case scripts

`dev test <script>` SHALL execute the Debug app binary with `--test-case <script>`. Any additional arguments after `<script>` SHALL be passed through unchanged to MuseScore.

Example:

```powershell
.\dev.ps1 test vtest\vtest.js --test-case-context vtest\vtest_context.json
```

This maps to:

```powershell
build.debug\src\app\MuseScoreStudio5.exe --test-case vtest\vtest.js --test-case-context vtest\vtest_context.json
```

Alternative considered: make `dev test` run the whole CTest/unit-test suite. Unit tests are disabled by default in the current build script (`MUSESCORE_BUILD_UNIT_TESTS=OFF`), so a full-suite command would either fail in normal builds or require additional configuration outside the wrapper's daily scope.

### Make `dev clean` safe by default

`dev clean` SHALL target all three known local output directories by default:

```text
build.debug
build.release
build.install
```

Without `--yes`, it SHALL only print what would be deleted. With `--yes`, it SHALL delete the selected directories if they exist.

`dev clean debug`, `dev clean release`, and `dev clean install` SHALL target only the corresponding directory. Unknown clean targets SHALL fail with usage text.

Alternative considered: make `clean` delete immediately. That is faster but unsafe for large local build outputs and inconsistent with the explicit dry-run decision.

## Risks / Trade-offs

- Direct Debug executable path may differ on some local configurations -> Keep the path centralized in one helper and fail with a clear error if missing.
- Direct `dev.ps1` invocation means only commands delegated to `ninja_build.bat` initialize the Visual Studio environment automatically -> Keep `run`, `test`, and `clean` independent of MSVC setup and rely on the already-built Debug executable for run/test.
- `dev test` does not cover the full unit-test suite -> Document that v1 test support is for app-level `--test-case` scripts only.
- `dev clean --yes` can delete large directories -> Keep dry-run as the default and require explicit confirmation.
