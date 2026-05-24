# MuseScore Studio

## Build System

- **Generator**: CMake + Ninja via `ninja_build.bat` (Windows) or `ninja_build.sh` (macOS/Linux)
- **Windows wrapper**: `ninja_build.bat` sets up MSVC and calls `ninja_build.ps1`; `ninja_build.sh` remains the Unix-like implementation
- **Build directory**: `builds/b` (RelWithDebInfo)
- **Compiler**: MSVC 2022 (Windows), requires Visual Studio developer environment

## Building on Windows

**Always use the Visual Studio developer environment.** Direct `cmake --build` calls from a plain shell will fail with `fatal error C1083: Cannot open include file: 'vector'/'memory'/'stddef.h'` because the MSVC `INCLUDE`/`LIB` paths are missing.

### Release build (fast)

```powershell
.\ninja_build.bat
```

Auto-detects VS with `vswhere.exe`, runs `vcvars64.bat`, then delegates to `ninja_build.ps1`. Creates `build.release`.

### Debug build (for stepping through code)

```powershell
.\ninja_build.bat -t debug
```

Creates `build.debug` with no optimizations and assertions enabled.

### Targeted incremental build (fastest iteration on specific module)

```powershell
cmd /c "call \"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat\" > nul 2>&1 && cmake --build builds\b --target <target> 2>&1"
```

Reuses the existing `builds/b` tree. Only recompiles changed files.

### Common targets

| Target | What it builds |
|---|---|
| `appshell_qml` | App-shell QML module (CommandPaletteDialog, model, menu, etc.) |
| `appshell` | App-shell C++ library (actions, controller, config) |
| `app` | Full application |

### Build type comparison

| Build type | Method | Optimizations | Assertions | Use case |
|---|---|---|---|---|
| `RelWithDebInfo` | `ninja_build.bat` (default) or `builds/b` | On | Off | Daily iteration |
| `Debug` | `ninja_build.bat -t debug` | Off | On | Debugging, tracing bugs |

## Command Palette Feature

Files for the command palette (`Ctrl+Shift+P`):

| File | Purpose |
|---|---|
| `src/appshell/qml/MuseScore/AppShell/commandpalettemodel.h` | C++ model header |
| `src/appshell/qml/MuseScore/AppShell/commandpalettemodel.cpp` | C++ model implementation |
| `src/appshell/qml/MuseScore/AppShell/CommandPaletteDialog.qml` | QML dialog |

### Known build gotcha

`std::clamp(index, 0, m_items.size() - 1)` fails because `m_items.size()` is `qsizetype` (64-bit) while `index`/`0` are `int`. Always cast:

```cpp
std::clamp(index, 0, static_cast<int>(m_items.size()) - 1)
```

## License

GPL-3.0-only. See `LICENSE.GPL` for details.
