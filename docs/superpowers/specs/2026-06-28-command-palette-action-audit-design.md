# Command Palette Action Audit — Design Spec

**Date:** 2026-06-28
**Status:** Approved (pending implementation)

## Problem

MuseScore's command palette discovers actions through `IUiActionsRegister::actionList()`, which aggregates `UiAction` declarations from each module's `*uiactions.cpp` file. However, dialogs registered via `registerQmlUri` in `*module.cpp` files are not automatically surfaced as command palette actions. Each requires manual wiring across 3-4 files (`UiAction` declaration, `dispatcher()->reg()` handler, `registerQmlUri`, and sometimes a menu entry). This manual process has led to gaps — dialogs that users should be able to reach from the command palette but can't.

Example: `musescore://playback/speeddialog` (if it existed) would be invisible to the command palette because no `UiAction` is registered for it. The playback speed popup is currently toggled only via a toolbar button.

## Goal

A periodic manual audit tool that:
1. Scans the codebase for `registerQmlUri` calls lacking corresponding `UiAction` registrations
2. Derives the full registration code for each gap (UiAction, handler, registerQmlUri)
3. Prints ready-to-paste code blocks for the agent to review and insert

The tool runs on-demand when the user wants to find and fill gaps. It is not CI.

## Architecture

Two artifacts:

### 1. Python script: `tools/action-audit/audit_actions.py`

Uses `tree-sitter` with the `tree-sitter-cpp` grammar to parse C++ source files reliably (handles templates, macros, multi-line declarations). Two CLI modes:

**`--scan` mode:**
- Parses all `*module.cpp` files in `src/` for `registerQmlUri(Uri("..."), "Module", "Component")` calls
- Parses all `*uiactions.cpp` files for `UiAction("action-code", ...)` declarations
- Parses `*actioncontroller.cpp` and `*controller.cpp` files for `dispatcher()->reg(this, "action-code", ...)` and `registerAction("action-code", ...)` calls
- Normalizes URIs and action codes for comparison (strip `musescore://` prefix + module segment, convert to kebab-case)
- Computes set difference: URIs without corresponding action codes
- For each candidate, derives metadata (action code, title, module, controller class, UiCtx/CTX)
- Prints a candidate report

**`--generate <uri>` mode:**
- Takes a candidate URI (must be one found by `--scan`)
- Derives three code blocks:
  1. `UiAction` declaration (for `*uiactions.cpp`)
  2. `dispatcher()->reg()` handler + method declaration/definition (for `*controller.cpp` + `.h`)
  3. `registerQmlUri` (only if the URI isn't already registered — usually it is)
- Uses tree-sitter to find insertion points (end of `UiActionList` initializer, end of `init()` method body)
- Prints each block labeled with its target file and insertion point
- Does NOT write to files — prints only

### 2. Managed skill: `audit-command-palette-actions`

A `SKILL.md` in `~/.omp/agent/managed-skills/audit-command-palette-actions/` that guides the agent through:
- Running `--scan` to find candidates
- Applying deny-list rules to filter false positives
- Running `--generate` for each approved candidate
- Reviewing and correcting derived code
- Pasting into the correct files
- Build-checking after insertions

## Data Flow

```
registerQmlUri calls  ─┐
UiAction declarations ─┼── tree-sitter parse ──→ set diff ──→ candidates
dispatcher()->reg()    ─┘                                      │
                                                              ▼
                                              ┌── deny-list filter (agent judgment)
                                              │
                                              ▼
                                    --generate <uri> ──→ derived code blocks
                                              │
                                              ▼
                                    agent reviews + corrects + pastes
                                              │
                                              ▼
                                        build-check
```

## Derivation Rules

The script derives metadata for each candidate from the `registerQmlUri` call:

| Field | Derivation rule | Example |
|---|---|---|
| Action code | URI last segment, kebab-case | `speeddialog` → `playback-speed` |
| Title | Component name minus "Dialog", title case | `PlaybackSpeedDialog` → `"Playback speed"` |
| Module | From file path containing `registerQmlUri` | `playback` |
| Controller class | Module name + lookup table | `playback` → `PlaybackController` |
| UiCtx | Default: `mu::context::UiCtxProjectOpened` | (agent may override) |
| CTX | Default: `mu::context::CTX_NOTATION_OPENED` | (agent may override) |
| Handler body | `interactive()->open("<uri>")` | `interactive()->open("musescore://playback/speeddialog")` |

### Controller class lookup table

The script maintains a mapping from module name to controller class name, since the naming isn't fully regular:

| Module | Controller class | UiActions file |
|---|---|---|
| `playback` | `PlaybackController` | `playback/internal/playbackuiactions.cpp` |
| `notationscene` | `NotationActionController` | `notationscene/internal/notationuiactions.cpp` |
| `appshell` | `ApplicationActionController` | `appshell/internal/applicationuiactions.cpp` |
| `project` | `ProjectActionController` | `project/internal/projectuiactions.cpp` |
| `notation` | `NotationActionController` | (shares notationscene's controller) |
| `palette` | *(none — uses direct dispatch)* | `palette/internal/paletteuiactions.cpp` |
| `preferences` | `ApplicationActionController` | (uses appshell's controller) |
| `instrumentsscene` | `NotationActionController` | (shares notationscene's controller) |
| `musesounds` | `ApplicationActionController` | (uses appshell's controller) |
| `engraving` | *(dev-only — diagnostics)* | N/A |

If a module isn't in the table, the script prints a warning and skips `--generate` for that candidate. The agent can add the mapping manually.

## URI-to-Action-Code Normalization

URIs and action codes don't match directly. The script normalizes both:

- URI `musescore://notation/settempo` → normalize → `set-tempo`
- Action code `set-tempo` → normalize → `set-tempo`
- Match!

Normalization steps:
1. Strip `musescore://` prefix
2. Strip the module segment (first path component, e.g., `notation/`, `playback/`)
3. Convert remaining segment(s) to kebab-case (insert `-` before capitals, lowercase)

If a normalized URI matches a normalized action code, the URI is considered "already registered" and excluded from candidates.

## Deny-List Rules

The script prints ALL candidates without filtering. The agent applies these rules during review (documented in the skill):

| Rule | Pattern | Example | Action |
|---|---|---|---|
| Diagnostics | URI contains `diagnostics` | `musescore://diagnostics/engraving/elements` | Skip — dev-only |
| Internal flow | URI contains `upload`, `migration`, `welcome`, `firstlaunch`, `asksavelocation`, `alsoshareaudiocom` | `musescore://project/upload/progress` | Skip — internal flow |
| Recursive/meta | URI equals `musescore://commandpalette` | `musescore://commandpalette` | Skip — recursive |
| Already has UiAction | Normalized code matches existing action | `set-tempo` already registered | Skip — already done |
| Contextual sub-dialog | Agent checks if dialog requires specific selection context | `palette/properties` needs palette cell selected | Skip if contextual |

## Generate Output Format

For each candidate, `--generate` prints:

```
=== CANDIDATE: musescore://playback/speeddialog ===

--- Block 1: UiAction declaration ---
Target: src/playback/internal/playbackuiactions.cpp
Insert: after the last UiAction in the initializer list (line ~N)

    UiAction("playback-speed",
             mu::context::UiCtxProjectOpened,
             mu::context::CTX_NOTATION_OPENED,
             TranslatableString("action", "Playback speed"),
             TranslatableString("action", "Set playback speed percentage")),

--- Block 2: Handler registration + method ---
Target: src/playback/internal/playbackcontroller.cpp + .h
Insert .cpp: in init(), after the last dispatcher()->reg() call
Insert .h: after the last private method declaration

// .cpp, in init():
    dispatcher()->reg(this, "playback-speed", [this]() { openPlaybackSpeedDialog(); });

// .cpp, method definition:
void PlaybackController::openPlaybackSpeedDialog()
{
    interactive()->open("musescore://playback/speeddialog");
}

// .h, declaration:
    void openPlaybackSpeedDialog();

--- Block 3: registerQmlUri (already present) ---
Skipped: URI already registered in src/playback/playbackmodule.cpp
```

## Skill Workflow

The `SKILL.md` instructs the agent to:

1. Run: `python tools/action-audit/audit_actions.py --scan`
2. Review the candidate list
3. Apply deny-list rules (table documented in the skill)
4. For each approved candidate:
   a. Run: `python tools/action-audit/audit_actions.py --generate <uri>`
   b. Review the derived code blocks
   c. Correct any wrong derivations (action code, title, context, controller class)
   d. Paste each block into the indicated file at the insertion point
   e. Build-check: `.\dev.ps1 build -j 8`
5. Commit when all approved candidates are added

## Dependencies

- Python 3.13+ (already installed on workstation)
- `tree-sitter` Python package (`pip install tree-sitter`)
- `tree-sitter-cpp` Python package (`pip install tree-sitter-cpp`)

Both are lightweight pure-Python packages with no system dependencies.

## Scope Boundaries

**In scope:**
- Scanning `src/` for `registerQmlUri` / `UiAction` / `dispatcher()->reg()` gaps
- Deriving UiAction + handler + registerQmlUri code blocks
- Managed skill with deny-list rules and workflow guide
- Print-only output (no file writes)

**Out of scope:**
- CI integration (this is a manual audit tool)
- Auto-writing to source files
- QML popup discovery (popups not registered via `registerQmlUri` — like the playback speed popup — are a separate problem)
- Menu entry generation (agent adds manually if needed)
- Shortcut binding (agent adds manually if needed)

## Testing

- Unit tests for the normalization function (URI → action code mapping)
- Unit tests for the derivation rules (component name → title, module → controller class)
- Integration test: run `--scan` against the current codebase, verify known gaps are found
- Integration test: run `--generate` for a known candidate, verify code blocks are syntactically correct

Tests live in `tools/action-audit/test_audit_actions.py` and run via `python -m pytest tools/action-audit/`.

## File Structure

```
tools/action-audit/
├── audit_actions.py          # Main script (scan + generate)
├── test_audit_actions.py     # Unit + integration tests
├── requirements.txt           # tree-sitter, tree-sitter-cpp
└── README.md                  # Usage guide

~/.omp/agent/managed-skills/
└── audit-command-palette-actions/
    └── SKILL.md               # Workflow guide + deny-list rules
```
