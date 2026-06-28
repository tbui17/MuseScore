# Command Palette Action Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Python script using tree-sitter that scans the MuseScore codebase for `registerQmlUri` calls lacking corresponding `UiAction` registrations, and generates ready-to-paste code blocks to fill the gaps. Plus a managed skill that guides the agent through the audit workflow.

**Architecture:** A Python script (`audit_actions.py`) with two CLI modes (`--scan` and `--generate`) uses tree-sitter's C++ grammar to parse source files, compute the set difference between registered URIs and registered actions, and derive UiAction + handler code from the URI metadata. A managed skill (`audit-command-palette-actions`) wraps the workflow with deny-list rules and paste instructions.

**Tech Stack:** Python 3.13+, tree-sitter, tree-sitter-cpp, pytest

---

## Source Spec

- Approved design: `docs/superpowers/specs/2026-06-28-command-palette-action-audit-design.md`

## Commit Policy

Do not commit during execution unless the user explicitly asks for commits. Each task has a verification checkpoint instead of an automatic commit step.

## Scope Guardrails

Implement only:

- `audit_actions.py` with `--scan` and `--generate <uri>` modes
- tree-sitter-based C++ parsing for `registerQmlUri`, `UiAction`, and `dispatcher()->reg()`/`registerAction()` calls
- URI-to-action-code normalization with fuzzy matching
- Derivation rules (action code, title, module, controller class, UiCtx/CTX)
- Controller class lookup table
- Generate output format (ready-to-paste code blocks, print-only)
- `test_audit_actions.py` with unit tests for normalization, derivation, and integration tests against the codebase
- `requirements.txt` with tree-sitter and tree-sitter-cpp
- `README.md` with usage guide
- `audit-command-palette-actions` managed skill with deny-list rules and workflow

Do NOT implement:

- CI integration
- File writing (script prints only)
- QML popup discovery (popups not registered via `registerQmlUri`)
- Menu entry generation
- Shortcut binding generation

## File Structure

Create these files:

- `tools/action-audit/audit_actions.py` — Main script (scan + generate)
- `tools/action-audit/test_audit_actions.py` — Unit + integration tests
- `tools/action-audit/requirements.txt` — Python dependencies
- `tools/action-audit/README.md` — Usage guide

Create this managed skill:

- `~/.omp/agent/managed-skills/audit-command-palette-actions/SKILL.md` — Workflow guide + deny-list rules

No existing files are modified.

## Build And Test Commands

```powershell
# Install dependencies (one-time)
pip install -r tools/action-audit/requirements.txt

# Run unit tests
python -m pytest tools/action-audit/test_audit_actions.py -v

# Run the scan
python tools/action-audit/audit_actions.py --scan

# Generate code for a specific candidate
python tools/action-audit/audit_actions.py --generate musescore://playback/speeddialog
```

---

### Task 1: Set up project structure and dependencies

**Files:**
- Create: `tools/action-audit/requirements.txt`
- Create: `tools/action-audit/README.md`

- [ ] **Step 1: Create requirements.txt**

Create `tools/action-audit/requirements.txt`:

```
tree-sitter>=0.21.0
tree-sitter-cpp>=0.21.0
pytest>=8.0.0
```

- [ ] **Step 2: Create README.md**

Create `tools/action-audit/README.md`:

```markdown
# Command Palette Action Audit

Scans the MuseScore codebase for `registerQmlUri` calls that lack corresponding `UiAction` registrations, and generates ready-to-paste code blocks to fill the gaps.

## Prerequisites

```powershell
pip install -r tools/action-audit/requirements.txt
```

## Usage

### Scan for gaps

```powershell
python tools/action-audit/audit_actions.py --scan
```

Prints a list of candidate URIs that have `registerQmlUri` calls but no matching `UiAction` registration, with derived metadata (action code, title, module, controller class).

### Generate code for a candidate

```powershell
python tools/action-audit/audit_actions.py --generate musescore://notation/gotobeat
```

Prints three ready-to-paste code blocks (UiAction declaration, handler registration + method, registerQmlUri if missing) labeled with their target files and insertion points.

### Run tests

```powershell
python -m pytest tools/action-audit/test_audit_actions.py -v
```
```

- [ ] **Step 3: Install dependencies**

Run:
```powershell
pip install -r tools/action-audit/requirements.txt
```

Expected: `tree-sitter`, `tree-sitter-cpp`, and `pytest` install successfully.

- [ ] **Step 4: Verify tree-sitter-cpp loads**

Run:
```powershell
python -c "import tree_sitter_cpp; print('tree-sitter-cpp loaded')"
```

Expected: prints `tree-sitter-cpp loaded` with no errors.

---

### Task 2: Implement the tree-sitter C++ parser helpers

**Files:**
- Create: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for parser initialization**

Create `tools/action-audit/test_audit_actions.py`:

```python
import pytest
from audit_actions import CppParser


class TestCppParser:
    def test_parser_initializes(self):
        """Parser can be created and parses simple C++."""
        parser = CppParser()
        code = b'int main() { return 0; }'
        tree = parser.parse(code)
        assert tree is not None
        assert tree.root_node.type == 'translation_unit'
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestCppParser::test_parser_initializes -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'audit_actions'`

- [ ] **Step 3: Write the CppParser class**

Create `tools/action-audit/audit_actions.py`:

```python
#!/usr/bin/env python3
"""Command palette action audit tool.

Scans for registerQmlUri calls lacking UiAction registrations,
and generates ready-to-paste code blocks to fill the gaps.
"""

import sys
import os
import re
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

import tree_sitter_cpp
from tree_sitter import Language, Parser


class CppParser:
    """Wrapper around tree-sitter C++ parser."""

    def __init__(self):
        language = Language(tree_sitter_cpp.language())
        self._parser = Parser(language)

    def parse(self, source: bytes):
        return self._parser.parse(source)
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestCppParser::test_parser_initializes -v
```

Expected: PASS

---

### Task 3: Implement registerQmlUri extraction

**Files:**
- Modify: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for registerQmlUri extraction**

Add to `tools/action-audit/test_audit_actions.py`:

```python
class TestRegisterQmlUriExtraction:
    def test_extracts_simple_call(self):
        """Extracts URI, module, component from a registerQmlUri call."""
        code = b'''
        void Foo::bar() {
            ir->registerQmlUri(Uri("musescore://playback/speeddialog"), "MuseScore.Playback", "PlaybackSpeedDialog");
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_register_qml_uri_calls(tree, code, "src/playback/playbackmodule.cpp")
        assert len(results) == 1
        assert results[0].uri == "musescore://playback/speeddialog"
        assert results[0].qml_module == "MuseScore.Playback"
        assert results[0].component == "PlaybackSpeedDialog"
        assert results[0].source_file == "src/playback/playbackmodule.cpp"

    def test_extracts_multiple_calls(self):
        """Extracts multiple registerQmlUri calls from one file."""
        code = b'''
        void Foo::bar() {
            ir->registerQmlUri(Uri("musescore://notation/parts"), "MuseScore.NotationScene", "PartsDialog");
            ir->registerQmlUri(Uri("musescore://notation/settempo"), "MuseScore.NotationScene", "TempoDialog");
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_register_qml_uri_calls(tree, code, "src/notationscene/notationscenemodule.cpp")
        assert len(results) == 2
        assert results[0].uri == "musescore://notation/parts"
        assert results[1].uri == "musescore://notation/settempo"
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestRegisterQmlUriExtraction -v
```

Expected: FAIL with `NameError: name 'extract_register_qml_uri_calls' is not defined`

- [ ] **Step 3: Implement extract_register_qml_uri_calls**

Add to `tools/action-audit/audit_actions.py`:

```python
@dataclass
class RegisterQmlUriCall:
    """A registerQmlUri call found in source."""
    uri: str
    qml_module: str
    component: str
    source_file: str


def _extract_string_literal(node, source: bytes) -> Optional[str]:
    """Extract the value of a string literal node."""
    if node is None or node.type != 'string_literal':
        return None
    # tree-sitter returns the raw bytes including quotes
    raw = source[node.start_byte:node.end_byte].decode('utf-8')
    # Strip surrounding quotes (handle both "..." and "..." forms)
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    return raw


def _find_calls_by_name(root_node, source: bytes, method_name: str):
    """Find all method calls matching the given name."""
    calls = []
    cursor = root_node.walk()

    def traverse(node):
        if node.type == 'call_expression':
            # Get the function node
            func_node = node.child_by_field_name('function')
            if func_node is not None:
                # For method calls like ir->registerQmlUri(...), the function
                # is a field_expression or identifier
                func_text = source[func_node.start_byte:func_node.end_byte].decode('utf-8')
                if method_name in func_text:
                    calls.append(node)
        for child in node.children:
            traverse(child)

    traverse(root_node)
    return calls


def extract_register_qml_uri_calls(tree, source: bytes, source_file: str) -> list[RegisterQmlUriCall]:
    """Extract all registerQmlUri calls from a parsed C++ file.

    Looks for calls matching: ir->registerQmlUri(Uri("..."), "...", "...")
    """
    results = []
    calls = _find_calls_by_name(tree.root_node, source, 'registerQmlUri')

    for call_node in calls:
        args = call_node.child_by_field_name('arguments')
        if args is None:
            continue

        # The first argument is Uri("...") — a call_expression containing a string_literal
        # We need to find the string literal inside it
        uri = None
        qml_module = None
        component = None

        arg_nodes = [child for child in args.children if child.type in ('call_expression', 'string_literal', 'identifier')]

        # Find Uri("...") call - first argument
        for arg in arg_nodes:
            if arg.type == 'call_expression':
                func = arg.child_by_field_name('function')
                if func is not None:
                    func_text = source[func.start_byte:func.end_byte].decode('utf-8')
                    if 'Uri' in func_text:
                        # Find the string literal argument inside Uri(...)
                        inner_args = arg.child_by_field_name('arguments')
                        if inner_args:
                            for inner_child in inner_args.children:
                                if inner_child.type == 'string_literal':
                                    uri = _extract_string_literal(inner_child, source)
                                    break
                break

        # Find the remaining string_literal arguments
        string_args = []
        for arg in arg_nodes:
            if arg.type == 'string_literal':
                string_args.append(_extract_string_literal(arg, source))

        # If we didn't find URI via the Uri() call, try string_args directly
        if uri is None and len(string_args) >= 1:
            # Check if first string arg looks like a URI
            if string_args[0] and '://' in string_args[0]:
                uri = string_args[0]
                string_args = string_args[1:]

        # Assign remaining string args to module and component
        if uri is not None:
            non_uri_strings = [s for s in string_args if s and '://' not in s]
            if len(non_uri_strings) >= 2:
                qml_module = non_uri_strings[0]
                component = non_uri_strings[1]
            elif len(non_uri_strings) == 1:
                component = non_uri_strings[0]

        if uri and component:
            results.append(RegisterQmlUriCall(
                uri=uri,
                qml_module=qml_module or "",
                component=component,
                source_file=source_file
            ))

    return results
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestRegisterQmlUriExtraction -v
```

Expected: PASS (both tests)

---

### Task 4: Implement UiAction extraction

**Files:**
- Modify: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for UiAction extraction**

Add to `tools/action-audit/test_audit_actions.py`:

```python
class TestUiActionExtraction:
    def test_extracts_simple_action(self):
        """Extracts action code from a UiAction declaration."""
        code = b'''
        const UiActionList Foo::s_actions = {
            UiAction("play",
                     mu::context::UiCtxProjectOpened,
                     mu::context::CTX_NOTATION_FOCUSED,
                     TranslatableString("action", "Play")),
        };
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_ui_action_codes(tree, code)
        assert len(results) == 1
        assert results[0] == "play"

    def test_extracts_multiple_actions(self):
        """Extracts multiple UiAction codes from a file."""
        code = b'''
        const UiActionList Foo::s_actions = {
            UiAction("play", ...),
            UiAction("stop", ...),
            UiAction("rewind", ...),
        };
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_ui_action_codes(tree, code)
        assert len(results) == 3
        assert "play" in results
        assert "stop" in results
        assert "rewind" in results

    def test_extracts_action_with_protocol_prefix(self):
        """Extracts action codes with action:// prefix."""
        code = b'''
        UiAction("action://notation/copy", ...),
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_ui_action_codes(tree, code)
        assert len(results) == 1
        assert results[0] == "action://notation/copy"
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestUiActionExtraction -v
```

Expected: FAIL with `NameError: name 'extract_ui_action_codes' is not defined`

- [ ] **Step 3: Implement extract_ui_action_codes**

Add to `tools/action-audit/audit_actions.py`:

```python
def extract_ui_action_codes(tree, source: bytes) -> list[str]:
    """Extract all UiAction action codes from a parsed C++ file.

    Looks for calls matching: UiAction("action-code", ...)
    Returns the raw action code string (first argument).
    """
    results = []
    calls = _find_calls_by_name(tree.root_node, source, 'UiAction')

    for call_node in calls:
        args = call_node.child_by_field_name('arguments')
        if args is None:
            continue

        # First argument should be a string literal
        for child in args.children:
            if child.type == 'string_literal':
                code = _extract_string_literal(child, source)
                if code:
                    results.append(code)
                break

    return results
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestUiActionExtraction -v
```

Expected: PASS (all three tests)

---

### Task 5: Implement dispatcher->reg and registerAction extraction

**Files:**
- Modify: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for dispatcher and registerAction extraction**

Add to `tools/action-audit/test_audit_actions.py`:

```python
class TestDispatcherRegExtraction:
    def test_extracts_dispatcher_reg(self):
        """Extracts action code from dispatcher()->reg() calls."""
        code = b'''
        void Foo::init() {
            dispatcher()->reg(this, "play", [this]() { togglePlay(); });
            dispatcher()->reg(this, "stop", this, &Foo::stop);
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_dispatcher_reg_codes(tree, code)
        assert len(results) == 2
        assert "play" in results
        assert "stop" in results

    def test_extracts_register_action(self):
        """Extracts action code from registerAction() calls."""
        code = b'''
        void Foo::init() {
            registerAction("set-tempo", [this]() { openSetTempoDialog(); });
            registerAction("current-tempo", [this]() { announceCurrentTempo(); });
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_dispatcher_reg_codes(tree, code)
        assert len(results) == 2
        assert "set-tempo" in results
        assert "current-tempo" in results
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestDispatcherRegExtraction -v
```

Expected: FAIL with `NameError: name 'extract_dispatcher_reg_codes' is not defined`

- [ ] **Step 3: Implement extract_dispatcher_reg_codes**

Add to `tools/action-audit/audit_actions.py`:

```python
def extract_dispatcher_reg_codes(tree, source: bytes) -> list[str]:
    """Extract all action codes from dispatcher()->reg() and registerAction() calls.

    Looks for calls matching:
      dispatcher()->reg(this, "action-code", ...)
      registerAction("action-code", ...)
    Returns the action code string (the string literal argument).
    """
    results = []
    calls = _find_calls_by_name(tree.root_node, source, 'reg')
    calls += _find_calls_by_name(tree.root_node, source, 'registerAction')

    for call_node in calls:
        args = call_node.child_by_field_name('arguments')
        if args is None:
            continue

        # Find the first string_literal argument — that's the action code
        # For dispatcher()->reg(this, "code", ...), the string is the 2nd arg
        # For registerAction("code", ...), the string is the 1st arg
        for child in args.children:
            if child.type == 'string_literal':
                code = _extract_string_literal(child, source)
                if code:
                    results.append(code)
                break

    return results
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestDispatcherRegExtraction -v
```

Expected: PASS (both tests)

---

### Task 6: Implement URI-to-action-code normalization

**Files:**
- Modify: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for normalization**

Add to `tools/action-audit/test_audit_actions.py`:

```python
class TestNormalization:
    def test_strip_musescore_prefix(self):
        """Strips musescore:// prefix from URI."""
        assert normalize_uri("musescore://notation/settempo") == "settempo"

    def test_strip_muse_prefix(self):
        """Strips muse:// prefix from URI."""
        assert normalize_uri("muse://preferences") == "preferences"

    def test_strip_module_segment(self):
        """Strips the module segment (first path component)."""
        assert normalize_uri("musescore://playback/speeddialog") == "speeddialog"
        assert normalize_uri("musescore://project/export") == "export"

    def test_kebab_case_conversion(self):
        """Converts camelCase to kebab-case."""
        assert normalize_action_code("gotoMeasure") == "goto-measure"
        assert normalize_action_code("setTempo") == "set-tempo"

    def test_preserves_existing_kebab(self):
        """Preserves existing kebab-case action codes."""
        assert normalize_action_code("set-tempo") == "set-tempo"
        assert normalize_action_code("play") == "play"

    def test_fuzzy_match_removes_hyphens(self):
        """Fuzzy matching removes hyphens for comparison."""
        assert fuzzy_match("settempo", "set-tempo") is True
        assert fuzzy_match("speeddialog", "speed-dialog") is True
        assert fuzzy_match("play", "stop") is False

    def test_action_code_with_protocol_prefix(self):
        """Normalizes action codes with action:// prefix."""
        assert normalize_action_code("action://notation/copy") == "copy"
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestNormalization -v
```

Expected: FAIL with `NameError: name 'normalize_uri' is not defined`

- [ ] **Step 3: Implement normalization functions**

Add to `tools/action-audit/audit_actions.py`:

```python
def normalize_uri(uri: str) -> str:
    """Normalize a URI to a comparable form.

    1. Strip musescore:// or muse:// prefix
    2. Strip the module segment (first path component)
    3. Return the remaining segment(s) as-is (lowercase)
    """
    # Strip protocol prefix
    for prefix in ('musescore://', 'muse://'):
        if uri.startswith(prefix):
            uri = uri[len(prefix):]
            break

    # Strip module segment (first path component)
    if '/' in uri:
        parts = uri.split('/', 1)
        if len(parts) > 1:
            uri = parts[1]
        else:
            uri = parts[0]

    return uri.lower()


def normalize_action_code(code: str) -> str:
    """Normalize an action code to a comparable form.

    1. Strip action:// prefix and module segment if present
    2. Convert camelCase to kebab-case
    3. Return lowercase
    """
    # Strip action:// prefix
    if code.startswith('action://'):
        code = code[len('action://'):]
        # Strip module segment
        if '/' in code:
            parts = code.split('/', 1)
            if len(parts) > 1:
                code = parts[1]
            else:
                code = parts[0]

    # Convert camelCase to kebab-case
    # Insert hyphen before uppercase letters, then lowercase
    result = re.sub(r'([A-Z])', r'-\1', code)
    # Remove leading hyphen if any
    if result.startswith('-'):
        result = result[1:]

    return result.lower()


def fuzzy_match(normalized_uri: str, normalized_code: str) -> bool:
    """Check if a normalized URI and action code match.

    First tries exact match, then tries fuzzy match by removing hyphens.
    """
    if normalized_uri == normalized_code:
        return True

    # Fuzzy: remove all hyphens and compare
    uri_no_hyphens = normalized_uri.replace('-', '')
    code_no_hyphens = normalized_code.replace('-', '')
    return uri_no_hyphens == code_no_hyphens
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestNormalization -v
```

Expected: PASS (all seven tests)

---

### Task 7: Implement derivation rules

**Files:**
- Modify: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for derivation**

Add to `tools/action-audit/test_audit_actions.py`:

```python
class TestDerivation:
    def test_derive_action_code_from_uri(self):
        """Derives action code from URI last segment (kebab-case)."""
        assert derive_action_code("musescore://playback/speeddialog") == "playback-speed"

    def test_derive_title_from_component(self):
        """Derives title from component name minus 'Dialog', title case."""
        assert derive_title("PlaybackSpeedDialog") == "Playback speed"
        assert derive_title("GoToPositionDialog") == "Go to position"
        assert derive_title("ExportDialog") == "Export"

    def test_derive_module_from_file_path(self):
        """Derives module name from the source file path."""
        assert derive_module("src/playback/playbackmodule.cpp") == "playback"
        assert derive_module("src/notationscene/notationscenemodule.cpp") == "notationscene"
        assert derive_module("src/appshell/appshellmodule.cpp") == "appshell"

    def test_controller_class_lookup(self):
        """Looks up controller class by module name."""
        assert get_controller_class("playback") == "PlaybackController"
        assert get_controller_class("notationscene") == "NotationActionController"
        assert get_controller_class("appshell") == "ApplicationActionController"
        assert get_controller_class("project") == "ProjectActionController"
        assert get_controller_class("instrumentsscene") == "InstrumentsActionsController"

    def test_controller_class_unknown_module_returns_none(self):
        """Unknown module returns None."""
        assert get_controller_class("unknownmodule") is None
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestDerivation -v
```

Expected: FAIL with `NameError: name 'derive_action_code' is not defined`

- [ ] **Step 3: Implement derivation functions**

Add to `tools/action-audit/audit_actions.py`:

```python
# Controller class lookup table (from the design spec)
CONTROLLER_CLASS_MAP = {
    "playback": "PlaybackController",
    "notationscene": "NotationActionController",
    "appshell": "ApplicationActionController",
    "project": "ProjectActionController",
    "notation": "NotationActionController",
    "instrumentsscene": "InstrumentsActionsController",
}


def derive_action_code(uri: str) -> str:
    """Derive an action code from a URI.

    Takes the last segment, converts to kebab-case, prepends the module segment.
    Example: musescore://playback/speeddialog → playback-speed
    """
    # Strip protocol
    for prefix in ('musescore://', 'muse://'):
        if uri.startswith(prefix):
            uri = uri[len(prefix):]
            break

    parts = uri.split('/')
    if len(parts) >= 2:
        module = parts[0]
        last_segment = parts[-1]
        # Convert last segment to kebab-case (insert hyphen before capitals)
        kebab = re.sub(r'([A-Z])', r'-\1', last_segment).lstrip('-').lower()
        return f"{module}-{kebab}"
    elif len(parts) == 1:
        return re.sub(r'([A-Z])', r'-\1', parts[0]).lstrip('-').lower()
    return uri.lower()


def derive_title(component: str) -> str:
    """Derive a user-facing title from a component name.

    Strips 'Dialog' suffix, converts camelCase to space-separated title case.
    Example: PlaybackSpeedDialog → "Playback speed"
    """
    # Strip 'Dialog' suffix
    name = component
    if name.endswith('Dialog'):
        name = name[:-6]

    # Convert camelCase to spaces
    spaced = re.sub(r'([A-Z])', r' \1', name).strip()
    # Lowercase everything except first word
    words = spaced.split(' ')
    if words:
        words = [words[0].capitalize()] + [w.lower() for w in words[1:]]
    return ' '.join(words)


def derive_module(source_file: str) -> str:
    """Derive module name from the source file path.

    Extracts the directory name under src/.
    Example: src/playback/playbackmodule.cpp → playback
    """
    # Normalize path separators
    normalized = source_file.replace('\\', '/')
    parts = normalized.split('/')
    if 'src' in parts:
        idx = parts.index('src')
        if idx + 1 < len(parts):
            return parts[idx + 1]
    return ""


def get_controller_class(module: str) -> Optional[str]:
    """Look up the controller class name for a module.

    Returns None if the module is not in the lookup table.
    """
    return CONTROLLER_CLASS_MAP.get(module)
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestDerivation -v
```

Expected: PASS (all five tests)

---

### Task 8: Implement the scan command

**Files:**
- Modify: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for scan (integration test against codebase)**

Add to `tools/action-audit/test_audit_actions.py`:

```python
class TestScanCommand:
    def test_scan_finds_known_gaps(self):
        """Scan against the real codebase finds known candidates."""
        # Run scan against the actual src/ directory
        candidates = scan_codebase("src")
        # Should find at least some candidates (URIs without UiActions)
        # We don't assert exact count because it changes as actions get added,
        # but we verify the scan produces output with the right structure
        assert isinstance(candidates, list)
        for c in candidates:
            assert hasattr(c, 'uri')
            assert hasattr(c, 'component')
            assert hasattr(c, 'source_file')
            assert c.uri.startswith('musescore://') or c.uri.startswith('muse://')

    def test_scan_excludes_already_registered(self):
        """Scan does not include URIs that have matching UiActions."""
        candidates = scan_codebase("src")
        # musescore://notation/settempo has UiAction "set-tempo" — should NOT appear
        candidate_uris = [c.uri for c in candidates]
        assert "musescore://notation/settempo" not in candidate_uris
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestScanCommand -v
```

Expected: FAIL with `NameError: name 'scan_codebase' is not defined`

- [ ] **Step 3: Implement scan_codebase**

Add to `tools/action-audit/audit_actions.py`:

```python
@dataclass
class Candidate:
    """A URI registered via registerQmlUri that lacks a UiAction."""
    uri: str
    qml_module: str
    component: str
    source_file: str
    module: str = ""
    action_code: str = ""
    title: str = ""
    controller_class: Optional[str] = None


def _find_files_by_pattern(root: str, pattern: str) -> list[str]:
    """Find all files matching a glob pattern under root."""
    return [str(p) for p in Path(root).rglob(pattern)]


def scan_codebase(src_dir: str) -> list[Candidate]:
    """Scan the codebase for registerQmlUri calls lacking UiAction registrations.

    1. Find all *module.cpp files, extract registerQmlUri calls
    2. Find all *uiactions.cpp files, extract UiAction codes
    3. Find all *controller.cpp and *actioncontroller.cpp files, extract dispatcher codes
    4. Normalize and compute set difference
    5. Derive metadata for each candidate
    """
    parser = CppParser()

    # Step 1: Collect all registerQmlUri calls
    all_qml_uris: list[RegisterQmlUriCall] = []
    module_files = _find_files_by_pattern(src_dir, "*module.cpp")
    for file_path in module_files:
        source = Path(file_path).read_bytes()
        tree = parser.parse(source)
        calls = extract_register_qml_uri_calls(tree, source, file_path.replace('\\', '/'))
        all_qml_uris.extend(calls)

    # Step 2: Collect all UiAction codes
    all_action_codes: set[str] = set()
    uiaction_files = _find_files_by_pattern(src_dir, "*uiactions.cpp")
    for file_path in uiaction_files:
        source = Path(file_path).read_bytes()
        tree = parser.parse(source)
        codes = extract_ui_action_codes(tree, source)
        all_action_codes.update(codes)

    # Step 3: Collect all dispatcher->reg / registerAction codes
    controller_patterns = ["*controller.cpp", "*actioncontroller.cpp"]
    for pattern in controller_patterns:
        for file_path in _find_files_by_pattern(src_dir, pattern):
            source = Path(file_path).read_bytes()
            tree = parser.parse(source)
            codes = extract_dispatcher_reg_codes(tree, source)
            all_action_codes.update(codes)

    # Step 4: Normalize and compute set difference
    normalized_action_codes = {normalize_action_code(c) for c in all_action_codes}

    candidates: list[Candidate] = []
    for qml_call in all_qml_uris:
        norm_uri = normalize_uri(qml_call.uri)
        # Check if any action code matches (exact or fuzzy)
        is_registered = any(
            fuzzy_match(norm_uri, norm_code)
            for norm_code in normalized_action_codes
        )
        if not is_registered:
            module = derive_module(qml_call.source_file)
            candidates.append(Candidate(
                uri=qml_call.uri,
                qml_module=qml_call.qml_module,
                component=qml_call.component,
                source_file=qml_call.source_file,
                module=module,
                action_code=derive_action_code(qml_call.uri),
                title=derive_title(qml_call.component),
                controller_class=get_controller_class(module),
            ))

    return candidates
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestScanCommand -v
```

Expected: PASS (both tests). The integration test runs against the real codebase.

---

### Task 9: Implement the generate command

**Files:**
- Modify: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for generate**

Add to `tools/action-audit/test_audit_actions.py`:

```python
class TestGenerateCommand:
    def test_generate_produces_three_blocks(self):
        """Generate produces UiAction, handler, and registerQmlUri blocks."""
        candidate = Candidate(
            uri="musescore://playback/speeddialog",
            qml_module="MuseScore.Playback",
            component="PlaybackSpeedDialog",
            source_file="src/playback/playbackmodule.cpp",
            module="playback",
            action_code="playback-speed",
            title="Playback speed",
            controller_class="PlaybackController",
        )
        output = generate_code_blocks(candidate)
        # Should contain all three block markers
        assert "=== CANDIDATE:" in output
        assert "Block 1: UiAction declaration" in output
        assert "Block 2: Handler registration" in output
        # Block 3 may be "already present" since the URI is already registered
        assert "Block 3:" in output

    def test_generate_includes_action_code(self):
        """Generate output includes the derived action code."""
        candidate = Candidate(
            uri="musescore://playback/speeddialog",
            qml_module="MuseScore.Playback",
            component="PlaybackSpeedDialog",
            source_file="src/playback/playbackmodule.cpp",
            module="playback",
            action_code="playback-speed",
            title="Playback speed",
            controller_class="PlaybackController",
        )
        output = generate_code_blocks(candidate)
        assert "playback-speed" in output

    def test_generate_includes_interactive_open(self):
        """Generate output includes interactive()->open with the URI."""
        candidate = Candidate(
            uri="musescore://playback/speeddialog",
            qml_module="MuseScore.Playback",
            component="PlaybackSpeedDialog",
            source_file="src/playback/playbackmodule.cpp",
            module="playback",
            action_code="playback-speed",
            title="Playback speed",
            controller_class="PlaybackController",
        )
        output = generate_code_blocks(candidate)
        assert 'interactive()->open("musescore://playback/speeddialog")' in output

    def test_generate_warns_on_unknown_controller(self):
        """Generate warns when controller class is unknown."""
        candidate = Candidate(
            uri="musescore://unknown/something",
            qml_module="MuseScore.Unknown",
            component="SomethingDialog",
            source_file="src/unknown/unknownmodule.cpp",
            module="unknown",
            action_code="unknown-something",
            title="Something",
            controller_class=None,
        )
        output = generate_code_blocks(candidate)
        assert "WARNING" in output or "unknown" in output.lower()
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestGenerateCommand -v
```

Expected: FAIL with `NameError: name 'generate_code_blocks' is not defined`

- [ ] **Step 3: Implement generate_code_blocks**

Add to `tools/action-audit/audit_actions.py`:

```python
def generate_code_blocks(candidate: Candidate) -> str:
    """Generate ready-to-paste code blocks for a candidate.

    Produces:
    - Block 1: UiAction declaration (for *uiactions.cpp)
    - Block 2: dispatcher()->reg() handler + method (for *controller.cpp + .h)
    - Block 3: registerQmlUri (only if the URI isn't already registered — usually it is)
    """
    lines = []
    lines.append(f"=== CANDIDATE: {candidate.uri} ===")
    lines.append("")

    # Derive target file paths
    module = candidate.module
    uiactions_file = f"src/{module}/internal/{module}uiactions.cpp"
    controller_file = f"src/{module}/internal/{module.replace('scene', '')}controller.cpp"
    controller_header = controller_file.replace('.cpp', '.h')
    module_file = candidate.source_file

    # Block 1: UiAction declaration
    lines.append("--- Block 1: UiAction declaration ---")
    lines.append(f"Target: {uiactions_file}")
    lines.append("Insert: after the last UiAction in the initializer list")
    lines.append("")
    lines.append(f'    UiAction("{candidate.action_code}",')
    lines.append('             mu::context::UiCtxProjectOpened,')
    lines.append('             mu::context::CTX_NOTATION_OPENED,')
    lines.append(f'             TranslatableString("action", "{candidate.title}"),')
    lines.append(f'             TranslatableString("action", "{candidate.title}")),')
    lines.append("")

    # Block 2: Handler registration + method
    if candidate.controller_class is None:
        lines.append("--- Block 2: Handler registration + method ---")
        lines.append("WARNING: No controller class found for this module.")
        lines.append(f"The agent must manually determine the controller class and target files.")
        lines.append("")
    else:
        handler_method = f"open{candidate.component.replace('Dialog', '')}Dialog"
        lines.append("--- Block 2: Handler registration + method ---")
        lines.append(f"Target: {controller_file} + {controller_header}")
        lines.append(f"Insert .cpp: in init(), after the last dispatcher()->reg() call")
        lines.append(f"Insert .h: after the last private method declaration")
        lines.append("")
        lines.append(f'// .cpp, in init():')
        lines.append(f'    dispatcher()->reg(this, "{candidate.action_code}", [this]() {{ {handler_method}(); }});')
        lines.append("")
        lines.append(f'// .cpp, method definition:')
        lines.append(f'void {candidate.controller_class}::{handler_method}()')
        lines.append('{')
        lines.append(f'    interactive()->open("{candidate.uri}");')
        lines.append('}')
        lines.append("")
        lines.append(f'// .h, declaration:')
        lines.append(f'    void {handler_method}();')
        lines.append("")

    # Block 3: registerQmlUri (usually already present)
    lines.append("--- Block 3: registerQmlUri ---")
    lines.append(f"Already present in {module_file}")
    lines.append(f"(If not, add: ir->registerQmlUri(Uri(\"{candidate.uri}\"), \"{candidate.qml_module}\", \"{candidate.component}\"));")

    return '\n'.join(lines)
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestGenerateCommand -v
```

Expected: PASS (all four tests)

---

### Task 10: Implement CLI entry point and scan output formatting

**Files:**
- Modify: `tools/action-audit/audit_actions.py`
- Test: `tools/action-audit/test_audit_actions.py`

- [ ] **Step 1: Write the failing test for CLI argument parsing**

Add to `tools/action-audit/test_audit_actions.py`:

```python
class TestCliOutput:
    def test_scan_output_format(self, capsys):
        """Scan output contains candidate info in readable format."""
        candidates = [
            Candidate(
                uri="musescore://playback/speeddialog",
                qml_module="MuseScore.Playback",
                component="PlaybackSpeedDialog",
                source_file="src/playback/playbackmodule.cpp",
                module="playback",
                action_code="playback-speed",
                title="Playback speed",
                controller_class="PlaybackController",
            ),
        ]
        print_scan_results(candidates)
        captured = capsys.readouterr()
        assert "musescore://playback/speeddialog" in captured.out
        assert "PlaybackSpeedDialog" in captured.out
        assert "playback-speed" in captured.out

    def test_generate_output_for_known_uri(self):
        """Generate finds a candidate by URI and produces code blocks."""
        candidates = scan_codebase("src")
        # Find a candidate to test with
        if not candidates:
            pytest.skip("No candidates found in codebase")
        test_candidate = candidates[0]
        output = generate_for_uri(test_candidate.uri, candidates)
        assert "=== CANDIDATE:" in output
        assert test_candidate.uri in output
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestCliOutput -v
```

Expected: FAIL with `NameError: name 'print_scan_results' is not defined`

- [ ] **Step 3: Implement CLI functions and main entry point**

Add to `tools/action-audit/audit_actions.py`:

```python
def print_scan_results(candidates: list[Candidate]):
    """Print scan results in a readable table format."""
    if not candidates:
        print("No candidates found — all registerQmlUri calls have matching UiAction registrations.")
        return

    print(f"Found {len(candidates)} candidate(s):\n")
    for c in candidates:
        print(f"CANDIDATE: {c.uri}")
        print(f"  Module:        {c.module}")
        print(f"  Component:     {c.component}")
        print(f"  Derived code:  {c.action_code}")
        print(f"  Derived title: \"{c.title}\"")
        print(f"  Controller:    {c.controller_class or 'UNKNOWN'}")
        print(f"  File:          {c.source_file}")
        print()


def generate_for_uri(uri: str, candidates: list[Candidate]) -> str:
    """Find a candidate by URI and generate code blocks for it."""
    for c in candidates:
        if c.uri == uri:
            return generate_code_blocks(c)
    return f"ERROR: URI '{uri}' not found in candidates. Run --scan first."


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Audit command palette actions for missing UiAction registrations."
    )
    parser.add_argument(
        '--scan',
        action='store_true',
        help='Scan for registerQmlUri calls lacking UiAction registrations'
    )
    parser.add_argument(
        '--generate',
        metavar='URI',
        help='Generate code blocks for a specific candidate URI'
    )
    parser.add_argument(
        '--src-dir',
        default='src',
        help='Source directory to scan (default: src)'
    )

    args = parser.parse_args()

    if args.scan:
        candidates = scan_codebase(args.src_dir)
        print_scan_results(candidates)
    elif args.generate:
        candidates = scan_codebase(args.src_dir)
        output = generate_for_uri(args.generate, candidates)
        print(output)
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py::TestCliOutput -v
```

Expected: PASS (both tests)

---

### Task 11: Run full test suite and verify scan against real codebase

**Files:**
- No new files. Verification only.

- [ ] **Step 1: Run all tests**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py -v
```

Expected: ALL tests PASS (no failures).

- [ ] **Step 2: Run the scan against the real codebase**

Run:
```powershell
python tools/action-audit/audit_actions.py --scan
```

Expected: Prints a list of candidates. Verify that:
- `musescore://notation/settempo` is NOT in the list (it has `set-tempo` UiAction)
- `musescore://diagnostics/engraving/elements` IS in the list (no UiAction)
- `musescore://project/upload/progress` IS in the list (no UiAction)
- `musescore://commandpalette` IS in the list (it has `command-palette` UiAction — but the URI is `commandpalette` and the action is `command-palette`; verify the fuzzy match handles this correctly)

- [ ] **Step 3: Run generate for a known candidate**

Pick a candidate from the scan output and run:
```powershell
python tools/action-audit/audit_actions.py --generate musescore://project/export
```

Expected: Prints three code blocks (UiAction, handler, registerQmlUri) with correct derived metadata. The action code should be `project-export`, the title should be `"Export"`, the controller class should be `ProjectActionController`.

- [ ] **Step 4: Verify generate for unknown controller module**

Run:
```powershell
python tools/action-audit/audit_actions.py --generate musescore://diagnostics/engraving/elements
```

Expected: Prints Block 1 (UiAction) and Block 3, but Block 2 should contain a WARNING about unknown controller class (engraving module is dev-only and not in the lookup table).

---

### Task 12: Create the managed skill

**Files:**
- Create: `~/.omp/agent/managed-skills/audit-command-palette-actions/SKILL.md`

- [ ] **Step 1: Create the SKILL.md**

Use the `manage_skill` tool to create the skill:

```markdown
# Audit Command Palette Actions

Find dialogs registered with `registerQmlUri` that lack `UiAction` registrations, and generate the missing command palette action code. Run periodically to catch gaps.

## When to Use

- "audit command palette"
- "find missing actions"
- "command palette gap"
- "registerQmlUri audit"
- When you want to check if any dialogs are missing from the command palette

## Prerequisites

Install dependencies (one-time):
```powershell
pip install -r tools/action-audit/requirements.txt
```

## Workflow

### Step 1: Scan for gaps

```powershell
python tools/action-audit/audit_actions.py --scan
```

This prints all `registerQmlUri` calls that lack corresponding `UiAction` registrations, with derived metadata (action code, title, module, controller class).

### Step 2: Apply deny-list rules

Review the candidate list and SKIP these categories:

| Rule | Pattern | Example | Action |
|---|---|---|---|
| Diagnostics | URI contains `diagnostics` | `musescore://diagnostics/engraving/elements` | Skip — dev-only |
| Internal flow | URI contains `upload`, `migration`, `welcome`, `firstlaunch`, `asksavelocation`, `alsoshareaudiocom` | `musescore://project/upload/progress` | Skip — internal flow |
| Recursive/meta | URI equals `musescore://commandpalette` | `musescore://commandpalette` | Skip — recursive |
| Contextual sub-dialog | Dialog requires specific selection context | `palette/properties` needs palette cell selected | Skip if contextual |

For contextual sub-dialogs: check whether the dialog makes sense as a standalone command. If it requires a specific selection or panel context to function, skip it. If it's a standalone dialog (like "Export" or "Preferences"), include it.

### Step 3: Generate code for each approved candidate

For each candidate you decide to include:

```powershell
python tools/action-audit/audit_actions.py --generate <uri>
```

This prints three ready-to-paste code blocks:
1. **UiAction declaration** — paste into the module's `*uiactions.cpp` file
2. **Handler registration + method** — paste into the module's `*controller.cpp` and `.h` files
3. **registerQmlUri** — usually already present, skip if so

### Step 4: Review and correct derived code

The script derives metadata automatically. Review and correct:
- **Action code**: Should follow kebab-case convention (e.g., `set-playback-speed`, not `playback-speeddialog`)
- **Title**: Should be user-friendly (e.g., "Set playback speed", not "Playback speed dialog")
- **UiCtx/CTX**: Defaults to `UiCtxProjectOpened` / `CTX_NOTATION_OPENED` — adjust if the action should be available in different contexts
- **Controller class**: If the script printed UNKNOWN, manually determine the correct controller class

### Step 5: Paste and build-check

1. Paste each code block into the indicated file at the insertion point
2. Build-check after each insertion:
   ```powershell
   .\dev.ps1 build -j 8
   ```
3. If the build fails, fix the issue and rebuild

### Step 6: Commit when all approved candidates are added

```powershell
git add <modified files>
git commit -m "feat: add missing UiAction registrations for command palette"
```

## Known Gaps (as of 2026-06-28)

These URIs are known to lack UiAction registrations but should NOT be added (deny-list):
- `musescore://diagnostics/engraving/*` — dev-only diagnostic dialogs
- `musescore://project/upload/*` — internal upload flow
- `musescore://project/migration` — auto-shown on file open
- `musescore://welcomedialog` — startup dialog
- `musescore://firstLaunchSetup` — one-time setup
- `musescore://commandpalette` — recursive
- `musescore://palette/properties` — contextual (needs palette selection)
- `musescore://palette/cellproperties` — contextual (needs cell selection)

These URIs are known to lack UiAction registrations and SHOULD be considered:
- `musescore://playback/soundprofilesdialog` — standalone playback config dialog
- `musescore://notation/editgridsize` — standalone notation dialog
- `musescore://musesounds/musesoundsreleaseinfo` — informational (judgment call)

## Testing

```powershell
python -m pytest tools/action-audit/test_audit_actions.py -v
```
```

Use the `manage_skill` tool with:
- action: `create`
- name: `audit-command-palette-actions`
- description: "Find dialogs registered with registerQmlUri that lack UiAction registrations, and generate the missing command palette action code. Run periodically to catch gaps."
- body: the full markdown content above

- [ ] **Step 2: Verify the skill was created**

Run:
```powershell
python -c "from pathlib import Path; p = Path.home() / '.omp/agent/managed-skills/audit-command-palette-actions/SKILL.md'; print(p.exists())"
```

Expected: prints `True`

- [ ] **Step 3: Verify skill is discoverable**

Read the skill back:
```powershell
type "%USERPROFILE%\.omp\agent\managed-skills\audit-command-palette-actions\SKILL.md"
```

Expected: prints the full SKILL.md content with frontmatter.

---

### Task 13: Final verification and commit

**Files:**
- No new files. Verification only.

- [ ] **Step 1: Run the complete test suite one final time**

Run:
```powershell
python -m pytest tools/action-audit/test_audit_actions.py -v
```

Expected: ALL tests PASS.

- [ ] **Step 2: Run --scan and verify output is sensible**

Run:
```powershell
python tools/action-audit/audit_actions.py --scan
```

Expected: Prints candidates with correct derived metadata. No crashes. URIs with known UiActions (like `set-tempo`) are excluded.

- [ ] **Step 3: Run --generate for a real candidate**

Run:
```powershell
python tools/action-audit/audit_actions.py --generate musescore://project/export
```

Expected: Prints three code blocks with correct, compilable-looking C++ code. The derived action code, title, and controller class are sensible.

- [ ] **Step 4: Commit all new files**

```powershell
git add tools/action-audit/audit_actions.py tools/action-audit/test_audit_actions.py tools/action-audit/requirements.txt tools/action-audit/README.md
git commit -m "feat: add command palette action audit tool

- Python script using tree-sitter to scan for registerQmlUri calls
  lacking UiAction registrations
- --scan mode finds candidates with derived metadata
- --generate mode produces ready-to-paste code blocks
- Managed skill with deny-list rules and workflow guide
- Unit and integration tests"
```

Expected: commit succeeds.

---

## Self-Review Notes

- Spec coverage: scan logic (Task 8), generate logic (Task 9), derivation rules (Task 7), normalization (Task 6), deny-list (Task 12 skill), CLI (Task 10), testing (Tasks 1-11), file structure (Task 1), managed skill (Task 12) — all mapped to tasks.
- Controller class lookup table matches the corrected spec (instrumentsscene → InstrumentsActionsController, preferences/musesounds have no controller).
- Normalization includes fuzzy matching for hyphen differences (settempo vs set-tempo).
- Generate output includes WARNING for unknown controller classes.
- Integration tests run against the real codebase.
- No placeholders — all code blocks are complete.
