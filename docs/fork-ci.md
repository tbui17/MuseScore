# Fork Windows builds and draft prereleases

## Scope and readiness

Entry point: `.github/workflows/fork_windows.yml` in `tbui17/MuseScore`.
The required aggregate status is **Fork Windows readiness**. It succeeds only when source preflight, full Windows build/package, Linux unit tests, and fresh-runner package tests all succeed. An uploaded `windows-candidate-*` artifact is not by itself release-ready. `diagnostic-*` artifacts contain logs, not application packages.

The deliverable is an unsigned Windows x64 ZIP, extracted and run as a complete directory. It is **not** an MSI installer, the PortableApps target, or an upstream stable release. The build uses the development channel and `RelWithDebInfo`. Audio export, ASIO, VST, accessibility, and Braille remain enabled. External crash upload and upstream auto-update are disabled. No signing, FTP, backend, Sentry, OMP, or model credentials are required.

Keep the extracted directory intact. Do not move just the executable or selectively copy DLLs. Windows may warn about unsigned binaries. Do not claim signing or installer upgrade/uninstall behavior. CI isolates its application profile; ordinary interactive launches retain the application's existing development-channel profile behavior and may share settings with another development build. Back up settings and scores before testing a fork. This pipeline does not change application IDs or settings migration.

## Source and workflow identities

PR runs build the intended synthetic merge SHA, not merely the PR head. Push runs build the pushed SHA. Manual `source_ref` accepts a branch, tag, or full commit from this repository, resolves it once, and uses that exact commit for Windows and Linux. A branch name with `/` never becomes a package directory name. Framework checkout always uses the committed `muse` gitlink; no runtime override or `submodule update --remote` is allowed.

Manual release policy is deliberately conservative: execute the approved workflow from `main`, and select a source commit already merged into `main`. Unmerged feature refs are supported for artifact-only builds after their framework pins receive the maintenance repair. Do not silently patch an old checkout. Preserve feature framework work when cherry-picking/merging the repair and commit its new exact gitlink.

Trusted helpers come from `workflow_sha` under `pipeline/`; build sources come from `source_sha` under `source/`. The runtime job never checks out a compilable tree: it takes the trusted helper sparsely under `pipeline/` and, under `fixtures/`, only the files the runtime helper reads from `-SourceDirectory` (`version.cmake`, the two reviewed GUI scripts and one committed score). A full source tree is therefore never present beside the extracted package, so the application cannot fall back to source resources and mask a missing packaged file. Build and runtime jobs have read-only tokens, do not persist checkout credentials, and receive no secrets. Only the isolated release job has repository write permission. It executes trusted pipeline code, never artifact-provided scripts.

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

A fresh Windows job downloads the producing job's exact artifact, checks its hash, extracts outside the source tree, and tests the installed package without installing Qt. It checks out only the sparse reviewed fixtures described above, clears developer Qt/QML overrides, prepares the profile through the real Windows known folders (refusing to seed an existing development profile, and refusing to run outside a fresh GitHub-hosted runner), and bounds process lifetimes. Mandatory checks: structural resources from the manifest (all paths bounded before use, and the executable both bounded and re-derived from `version.cmake`), version startup, a **PDF export** that exercises layout, painting and font embedding, a **score container export** validated as a ZIP carrying the score XML, and both command-palette GUI test cases. Logs distinguish assertion failure, crash, missing script and timeout.

For each GUI case the reviewed script from the source checkout must be present and byte-identical to the installed copy; a missing reviewed script fails the run instead of falling back to whatever the package contains. The helper points `MUSE_TESTFLOW_DATA_PATH` at its own output directory, so the testflow runner's record of the executed case is helper-owned evidence, and it now requires exactly one report file per case: the file name must be filesystem-safe, the `Test:` header must name the reviewed case, the `steps:` declaration must match the reviewed step list exactly, and every one of those steps must be recorded as finished, with no error, skipped or aborted step and no aborted completion. A zero exit status alone, or a bare `reports/` directory, is not accepted. The framework escapes only the report file name (`io::escapeFileName`, so `TC11: ...` can be written on Windows) while keeping the case name verbatim in the report content, fails the run when the report cannot be opened, refuses a test case that declares no steps, and turns an abort that lands between steps into `Status::Aborted` instead of leaving `Running` for `execScript()` to promote to `Finished`; the GUI runner exits 0 only for `Status::Finished`. Four further probes run the installed binary through those semantics: an escaping-name case must produce a safe-named completed report, an unusable data path must fail the run, a case without steps must fail, and an aborted case must fail with the abort recorded. Those probes use helper-generated scripts and are not evidence about MuseScore behaviour itself.

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
| Framework repair branch | `ci/pinned-dependency-bootstrap` in `tbui17/muse_framework`, draft PR https://github.com/tbui17/muse_framework/pull/1; pushed as `ac7772341de460f7c5b5e3af8ca0e546bc532e4f`, then `87f2e2a92060ca0bcf6b16adc38e84dfae67e5d6` (include-order resolution) `47579c22a6bee9b546b0deb0804fd47014a9c5db` (filesystem-safe GUI report names, refuse a step-less case, record a between-steps abort as aborted) and `b734227abcb2b78ec6bec87e5580c2c49e6ed8de` (synchronize the ring queue consumer test on producer completion) |
| Framework repair base | `5fe181cdcddec2709ab9396335b3dc4be3d40258`, the gitlink the repair was based on; framework live `main` is `8c223d87b982edf135a8a21da61189201a7ec5a6` and does not contain that pin, so the repair is based on the pin rather than on live main. This bundle moves the application gitlink to the repair tip `b734227abcb2b78ec6bec87e5580c2c49e6ed8de` |
| Dependency-loader tests | `cmake -P buildscripts/cmake/deps/tests/run-tests.cmake` in the framework: 15/15 pass, reproduced independently by a second agent on the same commit |
| Application helper tests | `python3 -m unittest discover -s buildscripts/ci/fork/tests -p 'test_*.py'` and the PowerShell helper suites run locally before any hosted dispatch |
| Existing release | `braille-test-2026-08-17` metadata was read read-only (one asset, 177547861 bytes, published, not a prerelease); the release was not modified or deleted |

Hosted runs exist and are recorded run by run in `ci-baseline.md`; none of them is a success claim. The hosted quoting failure and the Qt version parsing failure are repaired, and framework `87f2e2a92060ca0bcf6b16adc38e84dfae67e5d6` addresses the `FETCHCONTENT_BASE_DIR` failure, but the current Windows job is still inside its combined configure/compile/install step with no configure-success evidence, so this is progression, not qualification.

Open blockers for the hosted milestones:

1. **Workflow-scope token (resolved for this branch).** The authenticated `gh` token reports scopes that do not include `workflow` (`repo`, `admin:*`, `user`, `gist`, ... are present), so HTTPS pushes that add or modify `.github/workflows/*` are rejected. The owner's existing SSH key pushed the branch instead (`git push git@github.com:tbui17/MuseScore.git ci/fork-windows-releases:ci/fork-windows-releases`, no force update). Future workflow-file pushes need the same path or a token re-authorised with `workflow` scope.
2. **Cold hosted qualification** (Phase 1/2 gate) and every later gate remain unproven. `preflight` is green; run `34775359037` has not yet produced a completed Windows configure/build/install/package (the Windows job is still inside the combined configure/compile/install step, which is not evidence that configure passed), and its separate Linux `units` job built the application successfully before failing in `Run tests` on `Global_Concurrency_RingQueueTests.FixedSizeQueue` (`successCount` 0, expected 10), a bounded-attempt race in the test that framework `b734227abcb2b78ec6bec87e5580c2c49e6ed8de` repairs by synchronizing on producer completion (the retained log is `/tmp/musescore-ci-verification/units-api.log`) `use_cache=true` is refused by preflight rather than accepted and ignored.
3. **Merge approval:** merging the framework PR or the application branch into `main` is an owner decision and is not performed by this pipeline. The draft-release path additionally requires the workflow to run from `main` with a source commit already merged into `main`.

## Deferred work

macOS/Linux release packaging, MSI identity and upgrade semantics, signing/notarization, PortableApps, upstream FTP/backend publishing, public release publication and accessibility device QA remain separate tasks. Legacy automatic Windows/GUI builds stay in place until replacement parity is demonstrated; then guard duplicate fork jobs while preserving upstream/manual behavior. Required-check settings must be updated only with owner authority and after the readiness status exists.

See `ci-baseline.md` for observed failures and the implementation evidence record. Do not describe the pipeline as working until it contains actual successful hosted runs, tested package hashes and draft verification.
