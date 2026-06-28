# Command Palette Action Audit Tool

Scans the MuseScore codebase for `registerQmlUri` calls that lack corresponding
`UiAction` registrations, and generates ready-to-paste code blocks to fill the gaps.

## Requirements

```
pip install -r requirements.txt
```

Dependencies:
- `tree-sitter` — parsing library
- `tree-sitter-cpp` — C++ grammar
- `pytest` — test runner

## Usage

Run all commands from the repository root so the tool can find the `src/` directory.

### Scan mode

Find every `registerQmlUri` call with no matching `UiAction`:

```bash
python tools/action-audit/audit_actions.py --scan
```

Prints one block per candidate URI showing the module, component, derived action
code, derived title, controller class, and source file.

Override the source directory (defaults to `src`):

```bash
python tools/action-audit/audit_actions.py --scan --src-dir path/to/src
```

### Generate mode

Produce ready-to-paste code blocks for a specific candidate URI:

```bash
python tools/action-audit/audit_actions.py --generate musescore://project/export
```

Outputs three blocks:
1. **UiAction declaration** — paste into the module's `*uiactions.cpp`.
2. **Handler registration + method** — paste into the module's controller `.cpp`/`.h`.
3. **registerQmlUri** — usually already present; printed for reference.

If the module has no known controller class, a `WARNING` is emitted and the agent
must determine the controller class and target files manually.

## Running tests

```bash
python -m pytest tools/action-audit/test_audit_actions.py -v
```

From the repo root, add the tool directory to `PYTHONPATH` so the test module can
import `audit_actions`:

```bash
set PYTHONPATH=tools\action-audit && python -m pytest tools/action-audit/test_audit_actions.py -v
```

On Linux/macOS:

```bash
PYTHONPATH=tools/action-audit python -m pytest tools/action-audit/test_audit_actions.py -v
```

## How it works

1. Find all `*module.cpp` files and extract `registerQmlUri(Uri("..."), "...", "...")` calls.
2. Find all `*uiactions.cpp` files and extract `UiAction("...")` action codes.
3. Find all `*controller.cpp` / `*actioncontroller.cpp` files and extract
   `dispatcher()->reg(...)` and `registerAction(...)` action codes.
4. Normalize URIs and action codes (strip protocol/module segments, convert
   camelCase to kebab-case), then compute the set difference with fuzzy matching
   (hyphens ignored).
5. Any `registerQmlUri` URI with no matching action code is reported as a candidate.
