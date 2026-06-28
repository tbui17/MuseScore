# MuseScore Studio

## Daily Development

Use `dev.ps1` for all daily development tasks:

| Command | Meaning |
|---|---|
| `.\dev.ps1 build` | Incremental Debug build |
| `.\dev.ps1 build -j 8` | Debug build with 8 parallel jobs |
| `.\dev.ps1 run [args...]` | Run Debug MuseScore |
| `.\dev.ps1 test <script>` | Run headless testflow script (`--test-case`) |
| `.\dev.ps1 test-gui <script>` | Run GUI testflow script (`--test-case-gui`) |
| `.\dev.ps1 release` | Release build to `build.release/` |
| `.\dev.ps1 install` | Release build + install to `build.install/` |
| `.\dev.ps1 package` | Package `build.install/` into distributable ZIP |
| `.\dev.ps1 publish` | Build release, install, package, and push to GitHub Releases |
| `.\dev.ps1 clean [debug\|release\|install]` | Preview build dir deletion |
| `.\dev.ps1 clean --yes` | Delete all build dirs |

## Build System

- **Generator**: CMake + Ninja
- **Build directories**: `build.debug` (Debug), `build.release` (RelWithDebInfo)
- **Compiler**: MSVC 2022 (Windows), requires Visual Studio developer environment
- **Build a single target**: `ninja_build.bat -t relwithdebinfo-target --build-target MuseScoreStudio5.exe` (use `--build-target`, NOT `-T` — PowerShell `-eq` is case-insensitive so `-T` collides with `-t`)
- **ccache**: enabled by default if ccache is on PATH (`MUSESCORE_USE_CCACHE=ON`). Uses `/Z7` debug info (embedded in .obj, not PDB) for ccache compatibility.

## Testing

Testflow scripts live in `share/testflowscripts/`. GUI testflow uses `api.keyboard`, `api.dispatcher`, `api.navigation`, and `api.interactive.isOpened(uri)` to drive the real UI.

C++ unit tests:
```
ninja -C build.debug muse_appshell_qml_tests
ctest -R CommandPalette --output-on-failure
```

## CI

- **Workflow**: `.github/workflows/check_testflow_gui.yml` — builds `MuseScoreStudio5.exe` (RelWithDebInfo) then runs TC11_CommandPaletteDialog.js as a GUI integration test
- **Build optimization**: ccache + /Z7 debug info + building only the `MuseScoreStudio5.exe` target (not `all`) + `actions/cache` on both `~/AppData/Local/ccache` and `build.release`
- **Job split**: `build` job produces an artifact, `test` job downloads it — iterate on test scripts without rebuilding

### CI gotchas (learned the hard way)

- **Use RelWithDebInfo, not Debug** — Debug `assert()` shows a blocking dialog on Windows CI without a debugger. RelWithDebInfo defines `NDEBUG`.
- **Set `QT_QUICK_BACKEND=software`** — the GraphicsApi probe creates a test QQuickWindow that never paints on headless CI runners, blocking the event loop.
- **Pre-seed QSettings at `%APPDATA%\MuseScore\MuseScoreStudio5Development.ini`** — fresh runners need `hasCompletedFirstLaunchSetup=true`, `welcomeDialogShowOnStartup=false`, AND `welcomeDialogLastShownVersion=5.0.0`. Without all three, the WelcomeDialog steals keyboard focus from the command palette (`startupscenario.cpp:256` overrides `welcomeDialogShowOnStartup` to `true` when `welcomeDialogLastShownVersion < currentVersion`).
- **Disable `MUSE_MODULE_AUDIO_EXPORT` and `MUSE_MODULE_AUDIO_ASIO`** — both download from 404 URLs (muse_deps repo restructured). Not needed for testflow.
- **PowerShell here-strings (`@"..."@`) break YAML** — `@` at line start is a YAML flow mapping indicator. Use single-line `Set-Content` with `` `r`n `` escapes.

## Release & Packaging

```powershell
.\dev.ps1 publish              # Build release, install, package, and push to GitHub Releases
```

Or step by step:

```powershell
.\dev.ps1 install              # Build release + install to build.install/
.\dev.ps1 package              # Package build.install/ into ZIP
```
Produces `dist\musescore-braille-installer\MuseScore-Braille-Installer-<date>.zip`. Then create a GitHub release:

```powershell
gh release create braille-test-YYYY-MM-DD "dist/musescore-braille-installer/MuseScore-Braille-Installer-*.zip" --repo tbui17/MuseScore --title "MuseScore Braille Test Build YYYY-MM-DD"
```

**Client install** — one-liner that fetches the installer script from GitHub, which downloads the latest release ZIP:
```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/tbui17/MuseScore/feat/braille-normal-input/tools/braille-installer/Install-MuseScore-Braille.ps1')))
```
