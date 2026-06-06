# MuseScore Studio

## Build System

- **Generator**: CMake + Ninja via `ninja_build.bat` (Windows) or `ninja_build.sh` (macOS/Linux)
- **Windows wrapper**: `ninja_build.bat` sets up MSVC and calls `ninja_build.ps1`; `ninja_build.sh` remains the Unix-like implementation
- **Build directory**: `build.release` (RelWithDebInfo), `build.debug` (Debug)
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
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"" > nul 2>&1 && cmake --build build.release --target <target> 2>&1"
```

Reuses the existing `build.release` tree. Only recompiles changed files.

### Common targets

| Target | What it builds |
|---|---|
| `appshell_qml` | App-shell QML module (CommandPaletteDialog, model, menu, etc.) |
| `appshell` | App-shell C++ library (actions, controller, config) |
| `app` | Full application |

### Build type comparison

| Build type | Method | Optimizations | Assertions | Use case |
|---|---|---|---|---|
| `RelWithDebInfo` | `ninja_build.bat` (default) or `cmake -P build.cmake` | On | Off | Daily iteration |
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

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze --index-only` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/project-gaffer/context` | Codebase overview, check index freshness |
| `gitnexus://repo/project-gaffer/clusters` | All functional areas |
| `gitnexus://repo/project-gaffer/processes` | All execution flows |
| `gitnexus://repo/project-gaffer/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
