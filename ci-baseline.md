# Fork CI implementation audit

## Live baseline (2026-09-13)

The supplied workspace contained only the implementation plan. A fresh clone was created in `application/`; no existing worktree was reset. Application branch: `ci/fork-windows-releases`.

- Application main: `df4c4a03670a22fbfed49679440fa3c1f029c9be`.
- Framework gitlink: `5fe181cdcddec2709ab9396335b3dc4be3d40258`, recursively initialized from `https://github.com/tbui17/muse_framework.git`.
- Application origin: `https://github.com/tbui17/MuseScore.git`; upstream remains separate.
- Both public owner forks report Actions enabled, all actions allowed, and authenticated push/admin capability. Application rulesets are empty, main protection endpoint reports “Branch not protected”, and environments are empty. These observations do not grant authority to merge, change settings, or publish publicly. No settings changed.
- Existing release `braille-test-2026-08-17` is outside mutation scope.

## Failure to repair mapping

| Observed failure | Affected code | Repair | Verification |
|---|---|---|---|
| Windows run [28743802498](https://github.com/tbui17/MuseScore/actions/runs/28743802498), configure rejects absent `fdk-aac-2.0.3` directory and unknown `vst3sdk_Populate` | Framework MuseDeps, fdk/VST loaders | Reviewed recipes, locked payloads, verified downloads and layout | Controlled negative tests, clean hosted full configure |
| Latest Linux unit run [34451168544](https://github.com/tbui17/MuseScore/actions/runs/34451168544), 2026-09-10, same absent fdk source directory; later Ninja missing build.ninja | Framework fdk loader, unit workflow | Dependency repair, exact-source mandatory tests | Hosted Linux unit run, no suppressed failures |
| Submodule run [28743802471](https://github.com/tbui17/MuseScore/actions/runs/28743802471), rejects owner-fork URL | check_submodules.yml | Explicit fork allowlist, exact gitlink initialization and checkout verification, retain upstream ancestry rule | Policy negative tests and hosted preflight |
| Prior Windows metadata upload despite failed build (reported in supplied inspection) | Legacy build workflow | Explicit validated ZIP/manifest/checksum upload, separate diagnostics | Empty install and failed archive tests |

Translation warnings in the July log precede the fatal CMake dependency errors; they are not being relabelled as a compiler exhaustion failure. The Windows PR log used a synthetic merge commit, distinct from the PR head. Future manifests record source SHA and workflow SHA separately.

## Required configuration and acceptance

Full desktop `app`, `RelWithDebInfo`, development channel, Windows x64, Qt 6.10.2 with qt5compat/qtnetworkauth/qtshadertools/qtwebsockets. Audio export, ASIO, VST, accessibility and Braille remain enabled. Crash upload and upstream auto-update are intentionally off. Initial compile parallelism: 4. No imported build-tree cache and no local full compilation.

Required evidence: successful configure/build/install, actual installed executable and runtime resources, ZIP integrity and independent SHA-256, fresh Windows runner without development Qt, bounded version and score export, TC11/TC14 GUI assertions, same-source Linux unit success, and opt-in draft prerelease with identical tested bytes. Caching follows cold success; legacy duplicate builds remain until replacement parity is demonstrated. No hosted success is claimed by this baseline document.

## Implementation evidence (2026-09-13)

Local results only; nothing below is a hosted run, and no hosted success is claimed.

| Item | Recorded value |
|---|---|
| Framework repair | `tbui17/muse_framework`, branch `ci/pinned-dependency-bootstrap`, commit `ac7772341de460f7c5b5e3af8ca0e546bc532e4f`, pushed to the fork; draft PR https://github.com/tbui17/muse_framework/pull/1 |
| Framework repair base | `5fe181cdcddec2709ab9396335b3dc4be3d40258`, the exact gitlink this application branch pins. Framework live `main` is `8c223d87b982edf135a8a21da61189201a7ec5a6` and does not contain that pin, so the repair is based on the pin, and the PR intentionally shows the owner feature commits the pin already carries. |
| Dependency-loader tests | `cmake -P buildscripts/cmake/deps/tests/run-tests.cmake` in the framework: `All 15 dependency loader tests passed` (exit 0). Reproduced independently by a second agent on the same commit. |
| Applications helper tests | `python3 -m unittest discover -s buildscripts/ci/fork/tests -p 'test_*.py'`: 15 tests, OK. `pwsh -File buildscripts/ci/fork/tests/Test-PackageHelpers.ps1`: 21 cases pass. `Invoke-Pester -Path buildscripts/ci/fork/tests` (Pester 5.7.1): 13 passed, 0 failed, 1 skipped (the toolchain-only case, Windows host required). |
| Workflow lint | `actionlint v1.7.7` (SHA-256 verified archive) over `fork_windows.yml`, `check_submodules.yml`, `check_unit_tests.yml`, `check_testflow_gui.yml`: clean. |
| Token scopes | The authenticated `gh` token reports `repo`, `admin:*`, `user`, `gist`, `project`, `write:packages`, ... and **not** `workflow`. |
| Untouched state | Release `braille-test-2026-08-17` was not read, modified, or deleted. No force push, no tag moves, no settings/protection/environment/billing changes, no public publication, no merge. |

Repairs made after the initial helper work, each verified locally:

- Dependency-loading engine: explicit TLS verification for the download scope plus `TIMEOUT`/`INACTIVITY_TIMEOUT`; no unconditional pre-rename removal; extraction validates this destination's reviewed paths inside staging before anything is replaced; libarchive damage reported on stderr is rejected even when `cmake -E tar` exits 0 (the truncated-archive case); the archive cache is keyed by the pinned SHA-256 only, so a mirror-URL change reuses verified bytes while a lock change re-extracts; completion is bound to a reviewed-hash identity stamp.
- The framework test harness pointed one directory level too high at the engine, so every case failed as a harness error; corrected, and a lock-change regression case plus fixture were added.
- `buildscripts/ci/linux/runutests.sh` now runs under `set -Ee`, validates the generated environment file and `build.debug`, and uses `ctest --no-tests=error -V` so an empty test list cannot satisfy the mandatory unit gate.
- Runtime acceptance now requires the reviewed GUI script from the source checkout (no packaged-copy fallback), a testflow record for the executed test case, a real PDF document, and a score container opened as a ZIP carrying score XML; the manifest executable is bounded and re-derived from `version.cmake`.
- Test integrity fixes in the helper suites (they had never been run): per-test fixture directories, because a reused fixture repository made the fixture commit a no-op; a PowerShell array-literal precedence bug (`"0" * 40` inside `@(...)` multiplied the argument array); and one wording-only assertion replaced by an observable check (nonzero exit and no package file left behind).

## Blocked milestones

1. **Workflow-scope token.** Pushing commits that add or modify `.github/workflows/*` is expected to be rejected by GitHub, because the authenticated token's scopes omit `workflow`. Exact owner action on rejection: re-authorise the token with `workflow` scope (or push those paths with an SSH key / a token that has it), then re-run the push. Until then the app branch cannot reach the remote and no hosted run can start.
2. **Cold hosted qualification** (and every later gate) is unproven until that push lands and `Fork Windows` runs. `use_cache=true` is therefore refused by preflight rather than accepted and ignored.
3. **Merge approval.** Merging the framework PR or the application branch into `main` is an owner decision; this work does not merge. The draft-release path additionally needs the workflow to run from `main` with a source commit already in `main`.
