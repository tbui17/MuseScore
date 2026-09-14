# Fork CI implementation audit

## Live baseline (2026-09-14)

The current maintenance evidence covers application branch `ci/fork-windows-releases` at application commit `8881bcdc0db1bffac426b302577b4f82157715f9`. Its committed `muse` gitlink is framework maintenance commit `5519f3769b4e07a693c5b452a69cd19845d65f8d` on `ci/pinned-dependency-bootstrap`. Neither feature branch nor `main` was pushed or merged; no release or tag was changed.

- Application origin: `https://github.com/tbui17/MuseScore.git`; framework origin: `https://github.com/tbui17/muse_framework.git`.
- Both owner forks report Actions enabled and all actions allowed. Application rulesets are empty, main protection reports “Branch not protected”, and environments are empty. These observations do not grant authority to merge, change settings, or publish publicly. No settings changed.
- Existing release `braille-test-2026-08-17` is outside mutation scope and remains untouched.

## Failure to repair mapping

| Observed failure | Affected code | Repair | Verification |
|---|---|---|---|
| Windows run [28743802498](https://github.com/tbui17/MuseScore/actions/runs/28743802498), configure rejected absent `fdk-aac-2.0.3` and unknown `vst3sdk_Populate` | Framework MuseDeps, fdk/VST loaders | Reviewed recipes, locked payloads, verified downloads and layout | Controlled negative tests and hosted full configure |
| Linux unit run [34451168544](https://github.com/tbui17/MuseScore/actions/runs/34451168544), absent fdk source directory and later missing `build.ninja` | Framework fdk loader, unit workflow | Dependency repair and exact-source mandatory tests | Hosted Linux unit gate with no suppressed failures |
| Submodule run [28743802471](https://github.com/tbui17/MuseScore/actions/runs/28743802471), rejected owner-fork URL | `check_submodules.yml` | Explicit fork allowlist, exact gitlink initialization and checkout verification, retained upstream ancestry rule | Policy negative tests and hosted preflight |
| Prior Windows metadata upload despite failed build | Legacy build workflow | Validated ZIP/manifest/checksum upload separated from diagnostics | Empty-install and failed-archive tests |
| Qt 6.10 version file no longer contained a `PACKAGE_VERSION` literal | `buildscripts/ci/fork/windows-build.ps1` | Resolve Qt version through `qmake.exe -query QT_VERSION` and fail fast on empty output | Hosted configure/build/package runs below |
| SPIRV-Cross attribution named `COPYRIGHT.txt` while the required `LICENSE` was not installed | Framework `SetupLicenseNotices.cmake` | Validate and append every explicit required notice file before installing attribution-derived files | Framework 2/2 notice fixtures and hosted package proof below |

## Required configuration and acceptance

Full desktop `app`, `RelWithDebInfo`, development channel, Windows x64, Qt 6.10.2 with qt5compat/qtnetworkauth/qtshadertools/qtwebsockets. Audio export, ASIO, VST, accessibility and Braille remain enabled. Crash upload and upstream auto-update are intentionally off. Initial compile parallelism is 4. No imported build-tree cache or local full compilation is used.

Required evidence is successful configure/build/install, actual installed executable and runtime resources, ZIP integrity and independent SHA-256, a fresh Windows runner without development Qt, bounded version and score export, TC11/TC14 GUI assertions, same-source Linux unit success, and an opt-in draft prerelease with identical tested bytes. The same-code PR cold run and trusted cache-enabled warm proof are green. The draft-release path remains unexercised; legacy duplicate builds remain until replacement parity is demonstrated.

The trusted-cache contract is narrow: push and manual runs default to cache enabled, while pull requests use effective cache `false`. Compiler objects use helper-owned `build-output/ccache`, bounded at 4G, with normal-profile `MUSE_COMPILE_USE_PCH=ON`; dependency restore/save handles only completed hash-named archives under `build.release/_deps/<payload>/.pinned/<64 lowercase SHA-256>`. Pull requests never restore or save these caches, and no build tree, `CMakeCache.txt`, extracted dependency tree, partial archive or identity metadata is restored. Warm qualification below records matched-key provenance and real compiler hits.

## Local implementation evidence

- Framework dependency-loader tests: `cmake -P buildscripts/cmake/deps/tests/run-tests.cmake` passed all 15 cases on framework `5519f3769b4e07a693c5b452a69cd19845d65f8d`.
- Framework notice regression tests: `cmake -P buildscripts/cmake/deps/tests/run-license-tests.cmake` passed 2/2. The fixture models Qt Shader Tools/SPIRV-Cross with both `COPYRIGHT.txt` and required `LICENSE`, plus a negative missing-`LICENSE` configure case.
- Application Python helper tests: `python3 -m unittest discover -s buildscripts/ci/fork/tests -p 'test_*.py'` passed. PowerShell package cases passed; Pester reported 13 passed, 0 failed and 1 Windows-only skip. Workflow actionlint was clean.
- The ccache pin is 4.14 in `.github/workflows/fork_windows.yml`, `windows-build.ps1` and `ccache-pch-probe.ps1`; the workflow verifies the archive SHA-256 `2568347a697e103ca1b073981c704ad76fb2507d066c38dba038dd73399d968f`.

## Hosted evidence (through 2026-09-14)

The maintenance application push used the owner's existing SSH key because the authenticated HTTPS token lacks the `workflow` scope. It was a no-force update. Feature branches, `main`, releases and tags were not pushed or changed.

| Run | Revision | Observed |
|---|---|---|
| [34774152405](https://github.com/tbui17/MuseScore/actions/runs/34774152405) | `c32544bc6862b6ce1aebc68652bc3fe8a978dff8` | Hosted actionlint/shellcheck rejected unquoted variables; repaired in `5a1ae121bff38b28e84dbf8447a557635533d6ea`. |
| [34774233853](https://github.com/tbui17/MuseScore/actions/runs/34774233853) | `5a1ae121bff38b28e84dbf8447a557635533d6ea` | Preflight passed; Windows failed at full configure/build/install before later gates. |
| [34774769337](https://github.com/tbui17/MuseScore/actions/runs/34774769337) | `4a0b12189c7dfa7940b71b66f38bb8a8a4c10f67` | Preflight passed; Windows stopped at `DependencyPayload.cmake:53` because `FETCHCONTENT_BASE_DIR` was not resolved. Repaired by framework `87f2e2a92060ca0bcf6b16adc38e84dfae67e5d6`. |
| [34775359037](https://github.com/tbui17/MuseScore/actions/runs/34775359037) | `083d2227fbbfda2b260f662862741613e05f4b1e` | Windows eventually packaged, but units failed the ring-queue test and runtime evidence was disqualified by the stale job-directory profile and zero collected application logs. |
| [34777803748](https://github.com/tbui17/MuseScore/actions/runs/34777803748) | `6e1939da888553d57c7f99932428601d7f30323d` | Historical green cold run before current maintenance; all mandatory jobs succeeded and `release` was skipped. |
| [34797046747](https://github.com/tbui17/MuseScore/actions/runs/34797046747) | application `8881bcdc0db1bffac426b302577b4f82157715f9`, framework `5519f3769b4e07a693c5b452a69cd19845d65f8d` | **Same-code PR cold:** `preflight`, `windows`, `units`, `runtime` and `Fork Windows readiness` succeeded with pull-request cache disabled; `release` was skipped. |
| [34797044072](https://github.com/tbui17/MuseScore/actions/runs/34797044072), attempt 2 | application `8881bcdc0db1bffac426b302577b4f82157715f9`, framework `5519f3769b4e07a693c5b452a69cd19845d65f8d` | **Trusted cache-enabled cold primer:** all mandatory jobs succeeded; both cache restores missed, both cache saves succeeded, and `release` was skipped. The ccache 4.14 PCH probe reported producer `1/0/0`, first consumer `2/0/0`, second consumer `3/1/0` (cacheable/hits/uncacheable). |
| [34797044072](https://github.com/tbui17/MuseScore/actions/runs/34797044072), attempt 3 | application `8881bcdc0db1bffac426b302577b4f82157715f9`, framework `5519f3769b4e07a693c5b452a69cd19845d65f8d` | **Trusted cache-enabled warm proof:** all mandatory jobs succeeded; both exact attempt-2 keys restored, both attempt-3 saves succeeded, and `release` was skipped. Final ccache statistics were 2,521 cacheable calls, 1,140 hits (45.22%) and 1,381 misses. Units passed 29/29; runtime passed version, PDF, score-container, TC11, TC14 and four contract probes; package validation/upload and readiness succeeded. |

Attempt-3 restore provenance matched these exact attempt-2 keys:

- Compiler objects: `ccache-v1-win-x64-vs18.9.12120.119-msvc14.51.36231-cl19.51.36256-sdk10.0.26100.0-qt6.10.2-modulesqt5compat-qtnetworkauth-qtshadertools-qtwebsockets-cmake4.4-ninja1.13.2-RelWithDebInfo-lock77b1a6871c32d53c5cd77459220ae9a70a78c29ce0fa9b932e2403fbdb5805ff-flags52b1b7eed4f53ab883934ae5d82565ec6a8e121d55df8c723b5ab10494ee8486-ccache4.14-34797044072-2`
- Dependency archives: `deps-archives-v1-win-x64-lock77b1a6871c32d53c5cd77459220ae9a70a78c29ce0fa9b932e2403fbdb5805ff-schema1-34797044072-2`

The attempt-3 candidate artifact `tbui17-MuseScore-5.0.0-x64-8881bcdc0db1-unsigned.zip` was independently hashed as `e025a085d3df26632ff365a159022f41607940e633fbbc2dfce33bc38881dbdd`, matching `SHA256SUMS.txt` and `build-manifest.json`. The manifest requires `licenses/qt-libraries/qtshadertools/src/3rdparty/SPIRV-Cross/LICENSE`; an independent ZIP listing found that file and `COPYRIGHT.txt`.

A first trusted post-maintenance attempt failed closed before configure on a transient zlib archive checksum mismatch. The lock was not changed; independent refetches matched the locked bytes, and the subsequent full attempts passed.

The old Qt fatal remains useful historical evidence:

```text
== Resolving Qt
Exception: .../pipeline/buildscripts/ci/fork/windows-build.ps1:495
  | throw "Could not read the Qt version from '$qtVersionFile'."
  | Could not read the Qt version from 'D:\a\MuseScore\Qt\6.10.2\msvc2022_64\lib\cmake\Qt6\Qt6ConfigVersion.cmake'.
##[error]Process completed with exit code 1.
```

The helper now obtains the version from `bin\qmake.exe -query QT_VERSION`; the current hosted runs reached and passed configure. Synthetic helper fixtures remain supporting evidence only, not proof that a real MuseScore binary builds or runs.

## Remaining rollout and release gates

1. **Warm hosted qualification is complete.** The exact cache-enabled build/package/runtime/readiness path passed in trusted attempt 3, with matched restore keys and real compiler hits.
2. **Draft-release qualification remains open.** The opt-in release path has not been exercised. It must run from `main` with a source commit already merged into `main`; only the isolated release job may create a draft prerelease, and publication remains a separate owner action.
3. **Merge approval remains open.** Merging the framework PR or application branch into `main` is an owner decision and is not performed by this pipeline.
4. **Platform rollout remains open.** macOS/Linux release packaging, MSI identity and upgrade semantics, signing/notarization, PortableApps, upstream FTP/backend publishing, public release publication and accessibility-device QA remain separate tasks. Legacy automatic Windows/GUI builds stay in place until replacement parity is demonstrated; required-check settings need owner authority after readiness exists.

No main/release/tag action was taken. Do not describe the draft-release path as qualified until its exact ZIP/manifest/checksum and GitHub draft-prerelease verification have completed.
