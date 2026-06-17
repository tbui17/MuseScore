# MuseScore Studio

## Daily Development

Use `dev.ps1` for all daily development tasks:

| Command | Meaning |
|---|---|
| `.\dev.ps1 build` | Incremental Debug build |
| `.\dev.ps1 build -j 8` | Debug build with 8 parallel jobs |
| `.\dev.ps1 run [args...]` | Run Debug MuseScore |
| `.\dev.ps1 test <script>` | Run app test-case script |
| `.\dev.ps1 clean [debug\|release\|install]` | Preview build dir deletion |
| `.\dev.ps1 clean --yes` | Delete all build dirs |

## Build System

- **Generator**: CMake + Ninja
- **Build directories**: `build.debug` (Debug), `build.release` (RelWithDebInfo)
- **Compiler**: MSVC 2022 (Windows), requires Visual Studio developer environment
