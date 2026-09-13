# Fork Windows builds and draft prereleases

## Scope and readiness

Entry point: `.github/workflows/fork_windows.yml` in `tbui17/MuseScore`.
The required aggregate status is **Fork Windows readiness**. It succeeds only when source preflight, full Windows build/package, Linux unit tests, and fresh-runner package tests all succeed. An uploaded `windows-candidate-*` artifact is not by itself release-ready. `diagnostic-*` artifacts contain logs, not application packages.

The deliverable is an unsigned Windows x64 ZIP, extracted and run as a complete directory. It is **not** an MSI installer, the PortableApps target, or an upstream stable release. The build uses the development channel and `RelWithDebInfo`. Audio export, ASIO, VST, accessibility, and Braille remain enabled. External crash upload and upstream auto-update are disabled. No signing, FTP, backend, Sentry, OMP, or model credentials are required.

Keep the extracted directory intact. Do not move just the executable or selectively copy DLLs. Windows may warn about unsigned binaries. Do not claim signing or installer upgrade/uninstall behavior. CI isolates its application profile; ordinary interactive launches retain the application's existing development-channel profile behavior and may share settings with another development build. Back up settings and scores before testing a fork. This pipeline does not change application IDs or settings migration.

## Source and workflow identities

PR runs build the intended synthetic merge SHA, not merely the PR head. Push runs build the pushed SHA. Manual `source_ref` accepts a branch, tag, or full commit from this repository, resolves it once, and uses that exact commit for Windows and Linux. A branch name with `/` never becomes a package directory name. Framework checkout always uses the committed `muse` gitlink; no runtime override or `submodule update --remote` is allowed.

Manual release policy is deliberately conservative: execute the approved workflow from `main`, and select a source commit already merged into `main`. Unmerged feature refs are supported for artifact-only builds after their framework pins receive the maintenance repair. Do not silently patch an old checkout. Preserve feature framework work when cherry-picking/merging the repair and commit its new exact gitlink.

Trusted helpers come from `workflow_sha` under `pipeline/`; build sources come from `source_sha` under `source/`. Build and runtime jobs have read-only tokens, do not persist checkout credentials, and receive no secrets. Only the isolated release job has repository write permission. It executes trusted pipeline code, never artifact-provided scripts.

## Run a build

In GitHub: Actions → Fork Windows → Run workflow. Use workflow branch `main`, choose `source_ref`, leave `create_release` false for a downloadable candidate, and submit. The workflow must first be present on the default branch for normal manual-dispatch discovery. During review, the narrowly scoped `ci/fork-windows-releases` push trigger bootstraps hosted validation; remove it after rollout.

Bash/WSL:

```bash
gh workflow run fork_windows.yml --repo tbui17/MuseScore --ref main \
  -f source_ref=main -f create_release=false -f use_cache=false

gh run list --repo tbui17/MuseScore --workflow fork_windows.yml \
  --event workflow_dispatch --limit 10
```

PowerShell uses backticks rather than Bash continuations, or put the command on one line. `source_ref` is an input, while `--ref main` selects the trusted workflow revision; do not confuse them.

Use the matching workflow, actor, trigger time, ref and SHA to identify your run, not the latest unrelated repository run. Record the actual run ID and candidate artifact name from that run:

```bash
RUN_ID='<actual-run-id>'
ARTIFACT_NAME='<windows-candidate-name-from-that-run>'
gh run watch "$RUN_ID" --repo tbui17/MuseScore --exit-status
gh run view "$RUN_ID" --repo tbui17/MuseScore --log-failed
gh run download "$RUN_ID" --repo tbui17/MuseScore \
  --name "$ARTIFACT_NAME" --dir ./downloaded-build
(cd downloaded-build && sha256sum --check SHA256SUMS.txt)
```

On PowerShell, use `Get-FileHash -Algorithm SHA256` on the ZIP and compare it with both `SHA256SUMS.txt` and `build-manifest.json`. The manifest records application/framework/workflow identities, feature configuration, toolchain, dependency lock and archive digest. Binary and diagnostic artifacts expire after 14 days.

## Cold builds and toolchain maintenance

The qualification path uses fresh build/install directories and no restored dependency or compiler cache. `use_cache=false` requests the cold path.

`use_cache` is part of the public interface, but it is **not qualified yet** and is therefore fail-closed: preflight refuses `use_cache=true` with an explicit error instead of accepting it and silently running an uncached build under a cached label. The input keeps a provisional `false` default. It becomes effective only after the caching phase is implemented and a cold full-feature hosted run has demonstrably succeeded; a warm run must then report actual compiler hits, not merely an installed launcher. Never restore `build.release` or CMakeCache.txt in the authoritative path.

Baseline tools: standard `windows-2025`, Qt 6.10.2, `win64_msvc2022_64`, modules `qt5compat qtnetworkauth qtshadertools qtwebsockets`, 4 compile jobs and a 240-minute safety timeout. Actual runner image, compiler, SDK, CMake, Ninja, Python and Qt versions belong in build evidence. A runner label does not freeze MSVC. Change a toolchain pin only after reproducing a compatibility issue and requalify cold and warm artifacts.

Dependency locks live in the framework. To refresh a pin, inspect the actual authoritative payload and layout, review its upstream identity/licensing, record its expected SHA-256 in the lock, run controlled missing/hash/truncation/layout/retry tests, then run a cold hosted full configuration. Do not trust a hash computed from whatever response CI just downloaded. Commit and push the framework repair before committing the application gitlink. Preserve the selected feature branch's framework changes.

## Runtime test interpretation

A fresh Windows job downloads the producing job's exact artifact, checks its hash, extracts outside the source tree, and tests the installed package without installing Qt. It clears developer Qt/QML overrides, isolates profile state, and bounds process lifetimes. Mandatory checks: structural resources from the manifest (all paths bounded before use, and the executable both bounded and re-derived from `version.cmake`), version startup, a **PDF export** that exercises layout, painting and font embedding, a **score container export** validated as a ZIP carrying the score XML, and both command-palette GUI test cases. Logs distinguish assertion failure, crash, missing script and timeout.

For each GUI case the reviewed script from the source checkout must be present and byte-identical to the installed copy; a missing reviewed script fails the run instead of falling back to whatever the package contains. The helper points `MUSE_TESTFLOW_DATA_PATH` at its own output directory, so the testflow runner's record of the executed test case (`reports/`, created by `TestCaseReport::beginReport()` at the start of `runTestCase()`) is helper-owned evidence. A zero exit status without that record fails the run, because the GUI runner only exits 0 when the script's `main()` completed with the testflow status `Finished`. Note that a test case name may contain characters that are not valid in a Windows file name, which is why the record is checked as a directory rather than by report file name. Only `runtime results/logs` is uploaded; the extraction tree and isolated profile are not.

A GitHub-hosted Windows image may already contain shared runtimes; this is not proof of compatibility with every minimal Windows installation. Automated announcement assertions do not establish NVDA, JAWS, or physical Braille-device behavior. Those require separate user/QA checks. Linux unit failures also block release eligibility; they are not ignored because the Windows executable starts.

## Create and inspect a draft

After source review/merge and successful qualification:

```bash
gh workflow run fork_windows.yml --repo tbui17/MuseScore --ref main \
  -f source_ref=main -f create_release=true \
  -f release_tag=fork-2026.09.13.1 -f use_cache=false
```

Use a new `fork-YYYY.MM.DD.N` tag, with positive N, for each attempt requiring new release state. PRs, pushes, artifact-only requests, failed/skipped tests, non-main workflow refs and unsafe inputs cannot publish. The release tag targets the resolved source SHA, not blindly the workflow SHA. The isolated job verifies the exact ZIP/manifest/checksum trio, creates a **draft prerelease**, and verifies the tag target, draft/prerelease flags, asset names, sizes and server-computed SHA-256 digests. No compilation occurs during release.

Publication remains a separate explicit owner action. This implementation never publishes publicly, moves tags, overwrites existing assets, or replaces an existing release.

### Partial failure recovery

A failed upload can leave a tag and incomplete draft. Inspect the tag, release ID, target SHA, run link and all asset digests before acting. This path deliberately rejects **all existing tag/release collisions**, including exact reruns; it does not assume that an existing draft belongs to this pipeline. Choose a new tag and rerun after fixing the failure. Remove abandoned state only through an explicit owner decision, never automatic cleanup. Do not use `--clobber`.

Preserve license notices and make exact application/framework/dependency sources discoverable. Before wider binary distribution, review corresponding-source requirements. A GitHub application source archive omits submodule contents; provenance alone does not establish compliance. Assemble recursive corresponding sources when required.

## Qualification status and evidence (2026-09-13)

Nothing in this section is a substitute for a hosted run. Recorded facts:

| Item | Value |
|---|---|
| Application branch | `ci/fork-windows-releases`, based on application `main` `df4c4a03670a22fbfed49679440fa3c1f029c9be` |
| Framework repair branch | `ci/pinned-dependency-bootstrap` in `tbui17/muse_framework`, pushed as `ac7772341de460f7c5b5e3af8ca0e546bc532e4f`, draft PR https://github.com/tbui17/muse_framework/pull/1 |
| Framework repair base | `5fe181cdcddec2709ab9396335b3dc4be3d40258`, the exact gitlink carried by the application branch; framework live `main` is `8c223d87b982edf135a8a21da61189201a7ec5a6` and does not contain that pin, so the repair is based on the pin rather than on live main |
| Dependency-loader tests | `cmake -P buildscripts/cmake/deps/tests/run-tests.cmake` in the framework: 15/15 pass, reproduced independently by a second agent on the same commit |
| Application helper tests | `python3 -m unittest discover -s buildscripts/ci/fork/tests -p 'test_*.py'` and the PowerShell helper suites run locally before any hosted dispatch |
| Existing release | `braille-test-2026-08-17` was not read, modified, or deleted |

Open blockers for the hosted milestones:

1. **Workflow-scope token:** the authenticated `gh` token reports scopes that do not include `workflow` (`repo`, `admin:*`, `user`, `gist`, ... are present). Pushing commits that add or modify `.github/workflows/*` is therefore expected to be rejected by GitHub. If the push fails with `refusing to allow a Personal Access Token to create or update workflow ... without workflow scope`, the exact owner action is: re-authorise the token with `workflow` scope (or push those paths with an SSH key or a token that has it), then re-run the push.
2. **Cold hosted qualification** (Phase 1/2 gate) and every later gate remain unproven until that push lands and the workflow runs.
3. **Merge approval:** merging the framework PR or the application branch into `main` is an owner decision and is not performed by this pipeline. The draft-release path additionally requires the workflow to run from `main` with a source commit already merged into `main`.

## Deferred work

macOS/Linux release packaging, MSI identity and upgrade semantics, signing/notarization, PortableApps, upstream FTP/backend publishing, public release publication and accessibility device QA remain separate tasks. Legacy automatic Windows/GUI builds stay in place until replacement parity is demonstrated; then guard duplicate fork jobs while preserving upstream/manual behavior. Required-check settings must be updated only with owner authority and after the readiness status exists.

See `ci-baseline.md` for observed failures and the implementation evidence record. Do not describe the pipeline as working until it contains actual successful hosted runs, tested package hashes and draft verification.
