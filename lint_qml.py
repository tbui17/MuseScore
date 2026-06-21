#!/usr/bin/env python3
"""MuseScore QML lint script — runs qmllint in parallel on all QML files."""

import argparse
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def find_import_roots(build_dir: Path) -> list[str]:
    """Find QML import path roots from build output qmldir files."""
    roots: set[str] = set()
    for qmldir in build_dir.rglob("qmldir"):
        muse_dir = qmldir.parent.parent
        leaf = muse_dir.name
        if leaf in ("Muse", "MuseScore", "MuseApi"):
            roots.add(str(muse_dir.parent))
    return sorted(roots)


def find_qml_files(repo_root: Path) -> list[Path]:
    """Find all .qml files in src/ and muse/."""
    files: list[Path] = []
    for subdir in ("src", "muse"):
        root = repo_root / subdir
        if root.is_dir():
            files.extend(root.rglob("*.qml"))
    return files


def run_qmllint(qmllint_exe: str, import_args: list[str], file_path: Path, fix: bool) -> list[str]:
    """Run qmllint on a single file, return only Warning:/Info: lines."""
    cmd = [qmllint_exe]
    if fix:
        cmd.append("--fix")
    cmd.extend(import_args)
    cmd.append(str(file_path))
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    return [l for l in output.splitlines() if re.match(r"^(Warning:|Info:)", l)]


def main():
    parser = argparse.ArgumentParser(description="MuseScore QML linter")
    parser.add_argument("--filter", default="", help="Only lint files matching pattern")
    parser.add_argument("--accessible-only", action="store_true", help="Only show accessible-related warnings")
    parser.add_argument("--fix", action="store_true", help="Auto-fix where possible")
    parser.add_argument("--throttle", type=int, default=16, help="Parallel worker count")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent
    build_dir = repo_root / "build.debug"

    if not build_dir.is_dir():
        print(f"Build directory not found: {build_dir}", file=sys.stderr)
        print("Run '.\\dev.ps1 build' first to generate QML module info.", file=sys.stderr)
        sys.exit(1)

    qmllint_exe = None
    import shutil
    qmllint_exe = shutil.which("qmllint")
    if not qmllint_exe:
        print("qmllint not found on PATH. Ensure Qt bin directory is in PATH.", file=sys.stderr)
        sys.exit(1)

    import_roots = find_import_roots(build_dir)
    import_args: list[str] = []
    for root in import_roots:
        import_args.extend(["-I", root])

    qml_files = find_qml_files(repo_root)
    if args.filter:
        pattern = re.compile(args.filter, re.IGNORECASE)
        qml_files = [f for f in qml_files if pattern.search(str(f))]

    total = len(qml_files)
    print(f"Linting {total} QML files with {len(import_roots)} import paths (parallel)...")

    errors = 0
    warnings = 0
    results: list[tuple[str, list[str]]] = []

    with ThreadPoolExecutor(max_workers=args.throttle) as pool:
        futures = {
            pool.submit(run_qmllint, qmllint_exe, import_args, f, args.fix): f
            for f in qml_files
        }
        for future in as_completed(futures):
            file_path = futures[future]
            try:
                lines = future.result()
            except Exception as e:
                print(f"Error linting {file_path}: {e}", file=sys.stderr)
                continue
            if lines:
                results.append((str(file_path), lines))

    for file_path, lines in sorted(results):
        rel = os.path.relpath(file_path, repo_root)
        for line in lines:
            line = line.replace(file_path, rel)
            if args.accessible_only and "accessible" not in line.lower():
                continue
            if "[missing-property]" in line or "[syntax]" in line or "unknown grouped property scope accessible" in line:
                print(line)
                errors += 1
            elif line.startswith("Warning:"):
                print(line)
                warnings += 1
            else:
                print(line)

    print(f"\nDone: {total} files checked, {warnings} warnings, {errors} errors")


if __name__ == "__main__":
    main()
