#!/usr/bin/env python3
"""Command palette action audit tool.

Scans for registerQmlUri calls lacking UiAction registrations,
and generates ready-to-paste code blocks to fill the gaps.
"""

import sys
import os
import re
import argparse
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


@dataclass
class RegisterQmlUriCall:
    """A registerQmlUri call found in source."""
    uri: str
    qml_module: str
    component: str
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


# Controller class lookup table (from the design spec)
CONTROLLER_CLASS_MAP = {
    "playback": "PlaybackController",
    "notationscene": "NotationActionController",
    "appshell": "ApplicationActionController",
    "project": "ProjectActionController",
    "notation": "NotationActionController",
    "instrumentsscene": "InstrumentsActionsController",
}


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
                # Match the method name as the trailing token after ->, ::, or .,
                # or as the whole function text. A bare substring match would let
                # 'reg' match 'registerAction', so anchor to the end of the text.
                # E.g. 'ir->registerQmlUri', 'dispatcher()->reg', 'UiAction', 'registerAction'.
                if re.search(re.escape(method_name) + r'$', func_text):
                    calls.append(node)
        for child in node.children:
            traverse(child)

    traverse(root_node)
    return calls
def _find_first_string_literal(node) -> Optional[object]:
    """Recursively find the first string_literal node within a node's subtree.

    tree-sitter may wrap arguments in intermediate nodes (e.g. parameter_pack_expansion
    when '...' appears), so a direct child lookup can miss string literals.
    """
    if node is None:
        return None
    if node.type == 'string_literal':
        return node
    for child in node.children:
        found = _find_first_string_literal(child)
        if found is not None:
            return found
    return None


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

        # First argument is a string literal. It may be nested inside an
        # intermediate node (e.g. parameter_pack_expansion when '...' is used),
        # so search recursively for the first string literal.
        str_node = _find_first_string_literal(args)
        if str_node is not None:
            code = _extract_string_literal(str_node, source)
            if code:
                results.append(code)

    return results


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

        # Find the first string literal argument — that's the action code.
        # For dispatcher()->reg(this, "code", ...), the string is the 2nd arg;
        # for registerAction("code", ...), the string is the 1st arg.
        # Search recursively since the literal may be nested.
        str_node = _find_first_string_literal(args)
        if str_node is not None:
            code = _extract_string_literal(str_node, source)
            if code:
                results.append(code)

    return results


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
        # Strip a trailing 'dialog' so the derived code matches the component's
        # action name (e.g. speeddialog -> speed, giving 'playback-speed').
        if last_segment.lower().endswith('dialog'):
            last_segment = last_segment[:-len('dialog')]
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
