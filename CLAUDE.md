# MuseScore Studio

## Daily Development

Use `dev.ps1` for all daily development tasks:

| Command | Meaning |
|---|---|
| `.\dev.ps1 build` | Incremental Debug build |
| `.\dev.ps1 build -j 8` | Debug build with 8 parallel jobs |
| `.\dev.ps1 run [args...]` | Run Debug MuseScore |
| `.\dev.ps1 test <script>` | Run app test-case script |
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
