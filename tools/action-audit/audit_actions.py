#!/usr/bin/env python3
"""Command palette action audit tool.

Scans for registerQmlUri calls lacking UiAction registrations,
and generates ready-to-paste code blocks to fill the gaps.

Matching strategy: trace the actual handler chain instead of guessing by name.
  URI -> (method that contains the URI string) -> (action code registered
  to that method via reg()/registerAction()) -> (UiAction for that code).
A URI is a "gap" if any link in this chain is missing.
"""

import sys
import os
import re
import argparse
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional
from collections import defaultdict

import tree_sitter_cpp
from tree_sitter import Language, Parser


class CppParser:
    """Wrapper around tree-sitter C++ parser."""

    def __init__(self):
        language = Language(tree_sitter_cpp.language())
        self._parser = Parser(language)

    def parse(self, source: bytes):
        return self._parser.parse(source)


@dataclass
class RegisterQmlUriCall:
    """A registerQmlUri call found in source."""
    uri: str
    qml_module: str
    component: str
    source_file: str


@dataclass
class OpenCall:
    """An interactive()->open("uri") call or URI string literal found in a controller."""
    uri: str
    method_name: str  # enclosing method that contains the URI
    source_file: str


@dataclass
class Registration:
    """An action registration: reg("code", handler) or registerAction("code", handler)."""
    action_code: str
    method_name: str  # handler method name
    source_file: str


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
    reason: str = ""  # "no-handler", "handler-not-registered", "no-uiaction"


# Controller class lookup table (from the design spec)
CONTROLLER_CLASS_MAP = {
    "playback": "PlaybackController",
    "notationscene": "NotationActionController",
    "appshell": "ApplicationActionController",
    "project": "ProjectActionsController",
    "notation": "NotationActionController",
    "instrumentsscene": "InstrumentsActionsController",
}


def _extract_string_literal(node, source: bytes) -> Optional[str]:
    """Extract the value of a string literal node."""
    if node is None or node.type != 'string_literal':
        return None
    raw = source[node.start_byte:node.end_byte].decode('utf-8')
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    return raw


def _find_calls_by_name(root_node, source: bytes, method_name: str):
    """Find all method calls matching the given name (anchored to the trailing token)."""
    calls = []

    def traverse(node):
        if node.type == 'call_expression':
            func_node = node.child_by_field_name('function')
            if func_node is not None:
                func_text = source[func_node.start_byte:func_node.end_byte].decode('utf-8')
                if re.search(re.escape(method_name) + r'$', func_text):
                    calls.append(node)
        for child in node.children:
            traverse(child)

    traverse(root_node)
    return calls


def _find_first_string_literal(node) -> Optional[object]:
    """Recursively find the first string_literal node within a node's subtree."""
    if node is None:
        return None
    if node.type == 'string_literal':
        return node
    for child in node.children:
        found = _find_first_string_literal(child)
        if found is not None:
            return found
    return None


def _extract_function_name(func_def_node, source: bytes) -> Optional[str]:
    """Extract the method name from a function_definition node."""
    declarator = func_def_node.child_by_field_name('declarator')
    if declarator is None:
        return None
    name_node = declarator
    while name_node is not None:
        if name_node.type in ('identifier', 'qualified_identifier'):
            break
        child = name_node.child_by_field_name('declarator')
        if child is None:
            break
        name_node = child
    if name_node is None or name_node.type not in ('identifier', 'qualified_identifier'):
        name_node = declarator
    name_text = source[name_node.start_byte:name_node.end_byte].decode('utf-8')
    if '::' in name_text:
        name_text = name_text.rsplit('::', 1)[-1]
    name_text = name_text.split('(')[0].strip()
    return name_text if name_text else None


def _find_enclosing_method_name(node, source: bytes) -> Optional[str]:
    """Walk up parents to find the enclosing function_definition and return its name."""
    current = node.parent
    while current is not None:
        if current.type == 'function_definition':
            return _extract_function_name(current, source)
        current = current.parent
    return None


def _resolve_uri_variable(source: bytes, var_name: str) -> Optional[str]:
    """Find a Uri variable declaration and extract its URI string.

    Handles patterns like:
      static const Uri VAR_NAME("musescore://...")
      Uri VAR_NAME("musescore://...")
      VAR_NAME = Uri("musescore://...")
    """
    # Pattern: Uri VAR_NAME( "uri" ) -- only whitespace between ( and the string
    pattern = rf'Uri\s+{re.escape(var_name)}\s*\(\s*"([^"]+)"'.encode()
    match = re.search(pattern, source)
    if match:
        return match.group(1).decode('utf-8')
    # Pattern: VAR_NAME = Uri("uri")
    pattern2 = rf'{re.escape(var_name)}\s*=\s*Uri\s*\(\s*"([^"]+)"'.encode()
    match2 = re.search(pattern2, source)
    if match2:
        return match2.group(1).decode('utf-8')
    return None
def _resolve_action_code_variable(source: bytes, var_name: str) -> Optional[str]:
    """Find an ActionCode variable declaration and extract its string value.

    Handles patterns like:
      static const ActionCode VAR_NAME("action-code")
      ActionCode VAR_NAME("action-code")
    """
    pattern = rf'ActionCode\s+{re.escape(var_name)}\s*\(\s*"([^"]+)"'.encode()
    match = re.search(pattern, source)
    if match:
        return match.group(1).decode('utf-8')
    return None


def _extract_handler_method_name(handler_text: str) -> Optional[str]:
    """Extract method name from a handler argument's raw text.

    Handles:
      [this]() { methodName(); }         -- lambda with method call
      [this]() { this->methodName(); }    -- lambda with this-> call
      &Controller::methodName             -- function pointer
      &methodName                         -- simple function pointer
    """
    if '{' in handler_text:
        body = handler_text[handler_text.index('{'):]
        keywords = {'if', 'for', 'while', 'switch', 'return', 'else', 'catch', 'sizeof'}
        for match in re.finditer(r'(?:->|::)?(\w+)\s*\(', body):
            name = match.group(1)
            if name not in keywords:
                return name
        return None
    if '::' in handler_text:
        parts = handler_text.rsplit('::', 1)
        last = parts[-1].strip()
        match = re.match(r'(\w+)', last)
        if match:
            return match.group(1)
    match = re.match(r'&?\s*(\w+)', handler_text.strip())
    if match:
        return match.group(1)
    return None


def extract_register_qml_uri_calls(tree, source: bytes, source_file: str) -> list[RegisterQmlUriCall]:
    """Extract all registerQmlUri calls from a parsed C++ file."""
    results = []
    calls = _find_calls_by_name(tree.root_node, source, 'registerQmlUri')

    for call_node in calls:
        args = call_node.child_by_field_name('arguments')
        if args is None:
            continue

        uri = None
        qml_module = None
        component = None

        arg_nodes = [child for child in args.children if child.type in ('call_expression', 'string_literal', 'identifier')]

        for arg in arg_nodes:
            if arg.type == 'call_expression':
                func = arg.child_by_field_name('function')
                if func is not None:
                    func_text = source[func.start_byte:func.end_byte].decode('utf-8')
                    if 'Uri' in func_text:
                        inner_args = arg.child_by_field_name('arguments')
                        if inner_args:
                            for inner_child in inner_args.children:
                                if inner_child.type == 'string_literal':
                                    uri = _extract_string_literal(inner_child, source)
                                    break
                break

        string_args = []
        for arg in arg_nodes:
            if arg.type == 'string_literal':
                string_args.append(_extract_string_literal(arg, source))

        if uri is None and len(string_args) >= 1:
            if string_args[0] and '://' in string_args[0]:
                uri = string_args[0]
                string_args = string_args[1:]

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


def extract_ui_action_codes(tree, source: bytes) -> list[str]:
    """Extract all UiAction action codes from a parsed C++ file."""
    results = []
    calls = _find_calls_by_name(tree.root_node, source, 'UiAction')

    for call_node in calls:
        args = call_node.child_by_field_name('arguments')
        if args is None:
            continue
        str_node = _find_first_string_literal(args)
        if str_node is not None:
            code = _extract_string_literal(str_node, source)
            if code:
                results.append(code)

    return results


def extract_open_calls(tree, source: bytes, source_file: str) -> list[OpenCall]:
    """Extract all interactive()->open("uri") calls from a parsed C++ file.

    Handles three argument patterns:
      1. interactive()->open("musescore://...")          -- string literal
      2. interactive()->open(Uri("musescore://..."))      -- Uri() call
      3. interactive()->open(EXPORT_URI)                  -- Uri variable (resolved)
    """
    results = []
    calls = _find_calls_by_name(tree.root_node, source, 'open')

    for call_node in calls:
        func_node = call_node.child_by_field_name('function')
        if func_node is None:
            continue
        func_text = source[func_node.start_byte:func_node.end_byte].decode('utf-8')
        if 'interactive' not in func_text:
            continue

        args = call_node.child_by_field_name('arguments')
        if args is None:
            continue

        uri = None

        # Case 1 & 2: string literal or Uri("...") call
        str_node = _find_first_string_literal(args)
        if str_node is not None:
            uri = _extract_string_literal(str_node, source)

        # Case 3: identifier (Uri variable) -- resolve via file-wide search
        if uri is None:
            for child in args.children:
                if child.type == 'identifier':
                    var_name = source[child.start_byte:child.end_byte].decode('utf-8')
                    uri = _resolve_uri_variable(source, var_name)
                    if uri:
                        break

        if not uri:
            continue

        method_name = _find_enclosing_method_name(call_node, source) or ""
        results.append(OpenCall(uri=uri, method_name=method_name, source_file=source_file))

    return results


def extract_uri_literals_in_methods(tree, source: bytes, source_file: str) -> list[OpenCall]:
    """Find URI string literals in any method and map them to the enclosing method.

    This is a broad search that catches cases where the URI is assigned to a
    variable, passed through UriQuery, or constructed in if/else branches before
    being opened. It complements extract_open_calls() which only traces direct
    interactive()->open() calls.

    Only searches for strings starting with 'musescore://' or 'muse://' to avoid
    false positives from non-URI strings.
    """
    results = []

    def traverse(node):
        if node.type == 'string_literal':
            text = _extract_string_literal(node, source)
            if text and (text.startswith('musescore://') or text.startswith('muse://')):
                method_name = _find_enclosing_method_name(node, source)
                if method_name:
                    results.append(OpenCall(uri=text, method_name=method_name, source_file=source_file))
        for child in node.children:
            traverse(child)

    traverse(tree.root_node)
    return results


def extract_registrations(tree, source: bytes, source_file: str) -> list[Registration]:
    """Extract action registrations from dispatcher()->reg() and registerAction() calls.

    Returns (action_code, handler_method_name) pairs.
    Handles:
      dispatcher()->reg(this, "code", [this]() { methodName(); })
      dispatcher()->reg(this, "code", this, &Controller::methodName)
      registerAction("code", [this]() { methodName(); })
      registerAction("code", &Controller::methodName)
    """
    results = []
    calls = _find_calls_by_name(tree.root_node, source, 'reg')
    calls += _find_calls_by_name(tree.root_node, source, 'registerAction')

    for call_node in calls:
        args = call_node.child_by_field_name('arguments')
        if args is None:
            continue

        action_code_node = None
        str_node = _find_first_string_literal(args)
        if str_node is None:
            # The action code might be an ActionCode constant variable (e.g., PLAYBACK_SETUP)
            # Try to resolve it by searching for its declaration in the file
            action_code = None
            action_code_node = None  # track which node was the action code
            for child in args.children:
                if child.type == 'identifier':
                    var_name = source[child.start_byte:child.end_byte].decode('utf-8')
                    action_code = _resolve_action_code_variable(source, var_name)
                    if action_code:
                        action_code_node = child
                        break
            if not action_code:
                continue
        else:
            action_code = _extract_string_literal(str_node, source)
            if not action_code:
                continue

        method_name = None
        for child in args.children:
            if child.type == 'string_literal':
                continue
            if child is action_code_node:
                continue  # skip the action code variable when looking for handler
            text = source[child.start_byte:child.end_byte].decode('utf-8').strip()
            if text == 'this' or text == '':
                continue
            method_name = _extract_handler_method_name(text)
            if method_name:
                break

        results.append(Registration(
            action_code=action_code,
            method_name=method_name or "",
            source_file=source_file
        ))

    return results


def derive_action_code(uri: str) -> str:
    """Derive an action code from a URI.

    Takes the last segment, strips trailing 'dialog', converts to kebab-case,
    prepends the module segment.
    """
    for prefix in ('musescore://', 'muse://'):
        if uri.startswith(prefix):
            uri = uri[len(prefix):]
            break

    parts = uri.split('/')
    if len(parts) >= 2:
        module = parts[0]
        last_segment = parts[-1]
        if last_segment.lower().endswith('dialog'):
            last_segment = last_segment[:-6]
        kebab = re.sub(r'([A-Z])', r'-\1', last_segment).lstrip('-').lower()
        return f"{module}-{kebab}" if kebab else module.lower()
    elif len(parts) == 1:
        seg = parts[0]
        if seg.lower().endswith('dialog'):
            seg = seg[:-6]
        return re.sub(r'([A-Z])', r'-\1', seg).lstrip('-').lower()
    return uri.lower()


def derive_title(component: str) -> str:
    """Derive a user-facing title from a component name.

    Strips 'Dialog' suffix, converts camelCase to space-separated title case.
    """
    name = component
    if name.endswith('Dialog'):
        name = name[:-6]
    spaced = re.sub(r'([A-Z])', r' \1', name).strip()
    words = spaced.split(' ')
    if words:
        words = [words[0].capitalize()] + [w.lower() for w in words[1:]]
    return ' '.join(words)


def derive_module(source_file: str) -> str:
    """Derive module name from the source file path."""
    normalized = source_file.replace('\\', '/')
    parts = normalized.split('/')
    if 'src' in parts:
        idx = parts.index('src')
        if idx + 1 < len(parts):
            return parts[idx + 1]
    return ""


def get_controller_class(module: str) -> Optional[str]:
    """Look up the controller class name for a module."""
    return CONTROLLER_CLASS_MAP.get(module)


def _find_files_by_pattern(root: str, pattern: str) -> list[str]:
    """Find all files matching a glob pattern under root."""
    return [str(p) for p in Path(root).rglob(pattern)]
def _trace_method_calls(tree, source: bytes, uri_to_methods: dict[str, set[str]]):
    """Build a method call graph and add caller methods to uri_to_methods.

    For each method M that contains a URI, find methods that call M and add
    them to the URI's method set. This catches cases like:
      openPreferencesDialog() -> doOpenPreferencesDialog() -> open("muse://preferences")
    where the URI is in a helper method, not the registered method.
    """
    # Collect all method names that contain URIs
    all_uri_methods = set()
    for methods in uri_to_methods.values():
        all_uri_methods.update(methods)

    if not all_uri_methods:
        return

    # For each function_definition in the file, check if it calls any URI-containing method
    def traverse(node):
        if node.type == 'function_definition':
            caller_name = _extract_function_name(node, source)
            if caller_name is None:
                return
            # Get the body text of this function
            body_text = source[node.start_byte:node.end_byte].decode('utf-8', errors='replace')
            # Check if it calls any method that contains a URI
            for target_method in all_uri_methods:
                if target_method == caller_name:
                    continue  # skip self-calls
                # Look for method call pattern: target_method( or this->target_method( or &Class::target_method
                if re.search(rf'\b{re.escape(target_method)}\s*\(', body_text):
                    # This caller calls the URI-containing method.
                    # Add the caller to all URIs that the target method contains.
                    for uri, methods in uri_to_methods.items():
                        if target_method in methods:
                            methods.add(caller_name)
        for child in node.children:
            traverse(child)

    traverse(tree.root_node)


def scan_codebase(src_dir: str) -> list[Candidate]:
    """Scan the codebase for registerQmlUri calls lacking UiAction registrations.

    Uses handler-chain tracing instead of name matching:
    1. Collect all registerQmlUri calls (URIs to check)
    2. Collect all UiAction codes (palette-visible actions)
    3. Collect all URI string literals from ALL .cpp files -> URI -> method names
       (broad search catches URIs in scenarios, models, and dynamic constructions)
    4. Collect all reg()/registerAction() calls from controller files -> method -> action codes
    5. For each URI, trace: URI -> method -> action code -> UiAction
       If the full chain exists, the URI is NOT a gap.
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
    uiaction_codes: set[str] = set()
    uiaction_files = _find_files_by_pattern(src_dir, "*uiactions.cpp")
    for file_path in uiaction_files:
        source = Path(file_path).read_bytes()
        tree = parser.parse(source)
        codes = extract_ui_action_codes(tree, source)
        uiaction_codes.update(codes)

    # Step 3: Collect URI -> method mappings from ALL .cpp files (broad search)
    # This catches URIs in scenario files, model files, and dynamic constructions
    uri_to_methods: dict[str, set[str]] = defaultdict(set)
    all_cpp_files = _find_files_by_pattern(src_dir, "*.cpp")
    for file_path in all_cpp_files:
        lower_path = file_path.lower()
        if 'test' in lower_path or 'mock' in lower_path or 'qrc_' in lower_path:
            continue
        source = Path(file_path).read_bytes()
        tree = parser.parse(source)

        # URI string literals in any method -> URI -> methods
        for oc in extract_uri_literals_in_methods(tree, source, file_path):
            clean_uri = oc.uri.split('?')[0]  # strip query params
            uri_to_methods[clean_uri].add(oc.method_name)

        # Direct open calls for precise Uri variable resolution
        for oc in extract_open_calls(tree, source, file_path):
            clean_uri = oc.uri.split('?')[0]
            uri_to_methods[clean_uri].add(oc.method_name)

    # Step 4: Collect method -> action_code mappings from controller files only
    method_to_codes: dict[str, set[str]] = defaultdict(set)
    controller_sources: list[tuple[bytes, str]] = []  # (source, file_path) for call tracing
    controller_patterns = ["*controller.cpp", "*actioncontroller.cpp", "*actionscontroller.cpp"]
    seen_files = set()
    for pattern in controller_patterns:
        for file_path in _find_files_by_pattern(src_dir, pattern):
            if file_path in seen_files:
                continue
            seen_files.add(file_path)
            source = Path(file_path).read_bytes()
            tree = parser.parse(source)
            controller_sources.append((source, file_path))
            for reg in extract_registrations(tree, source, file_path):
                if reg.method_name:
                    method_to_codes[reg.method_name].add(reg.action_code)

    # Step 4b: Build method call graph for transitive tracing
    # If method A (registered) calls method B (contains URI), A should also map to the URI.
    # This catches cases like openPreferencesDialog() -> doOpenPreferencesDialog() -> open("uri")
    for source, file_path in controller_sources:
        tree = parser.parse(source)
        _trace_method_calls(tree, source, uri_to_methods)

    # Step 5: Trace the chain for each URI
    candidates: list[Candidate] = []
    for qml_call in all_qml_uris:
        methods = uri_to_methods.get(qml_call.uri, set())
        action_codes: set[str] = set()
        for method in methods:
            action_codes.update(method_to_codes.get(method, set()))

        has_uiaction = any(code in uiaction_codes for code in action_codes)

        if has_uiaction:
            continue

        # Determine the reason for the gap
        if not methods:
            reason = "no-handler"
        elif not action_codes:
            reason = "handler-not-registered"
        else:
            reason = "no-uiaction"

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
            reason=reason,
        ))

    return candidates


def generate_code_blocks(candidate: Candidate) -> str:
    """Generate ready-to-paste code blocks for a candidate."""
    lines = []
    lines.append(f"=== CANDIDATE: {candidate.uri} ===")
    lines.append(f"Gap reason: {candidate.reason}")
    lines.append("")

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
        lines.append("The agent must manually determine the controller class and target files.")
        lines.append("")
    else:
        handler_method = f"open{candidate.component.replace('Dialog', '')}Dialog"
        lines.append("--- Block 2: Handler registration + method ---")
        lines.append(f"Target: {controller_file} + {controller_header}")
        lines.append(f"Insert .cpp: in init(), after the last dispatcher()->reg() call")
        lines.append(f"Insert .h: after the last private method declaration")
        lines.append("")
        lines.append(f'// .cpp, in init():')
        lines.append(f'    dispatcher()->reg(this, "{candidate.action_code}", this, &{candidate.controller_class}::{handler_method});')
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
    lines.append(f'(If not, add: ir->registerQmlUri(Uri("{candidate.uri}"), "{candidate.qml_module}", "{candidate.component}"));')

    return '\n'.join(lines)


def print_scan_results(candidates: list[Candidate]):
    """Print scan results in a readable format."""
    if not candidates:
        print("No candidates found -- all registerQmlUri calls have matching UiAction registrations.")
        return

    print(f"Found {len(candidates)} candidate(s):\n")
    for c in candidates:
        print(f"CANDIDATE: {c.uri}")
        print(f"  Module:        {c.module}")
        print(f"  Component:     {c.component}")
        print(f"  Derived code:  {c.action_code}")
        print(f"  Derived title: \"{c.title}\"")
        print(f"  Controller:    {c.controller_class or 'UNKNOWN'}")
        print(f"  Gap reason:    {c.reason}")
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
