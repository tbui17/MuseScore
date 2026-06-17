## Why

MuseScore's Windows development flow currently requires contributors and agents to remember several lower-level build commands and build directories. A small `dev.ps1` wrapper gives humans and agents one daily command surface while keeping the existing CMake/Ninja build implementation delegated to `ninja_build.bat` and `ninja_build.ps1`.

## What Changes

- Add a repository-root `dev.ps1` command dispatcher for daily development commands only: `build`, `run`, `test`, and `clean`.
- Make Debug the default build configuration and `build.debug` the default build directory.
- Keep `build.install` out of normal daily `run` and `test` flows; only delete it through `clean` when requested.
- Delegate Debug builds to the existing `ninja_build.bat` implementation rather than duplicating CMake configuration logic.
- Run the Debug executable directly from the Debug build tree and fail with a helpful message if it is missing.
- Run app-level test-case scripts through the Debug executable's `--test-case` option, with remaining arguments passed through unchanged.
- Make `clean` dry-run by default and require `--yes` before deleting build directories.

## Capabilities

### New Capabilities
- `dev-wrapper`: A minimal Windows daily-development command wrapper for building, running, testing app-level scripts, and cleaning MuseScore build directories.

### Modified Capabilities

None.

## Impact

- Adds `dev.ps1` at the repository root.
- Uses the existing `ninja_build.bat` and `ninja_build.ps1` build path for `dev build`.
- Uses the existing Windows Debug executable path under `build.debug` for `dev run` and `dev test`.
- Does not change CMake configuration, Ninja targets, packaging, installer behavior, or test definitions.
