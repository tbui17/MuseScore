#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
"""Preserve exact formatter changes for review; never apply or publish them."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess

MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 32 * 1024 * 1024


def git(repository: Path, *args: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(repository), *args], check=True,
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60,
    ).stdout


def patch(repository: Path, scope: str) -> bytes:
    return git(repository, "diff", "--binary", "--full-index", "--no-ext-diff",
               "--no-textconv", "--no-renames", "--ignore-submodules=all", "HEAD", "--", scope)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def blob_id(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def collect(repository: Path, scope: str, output: Path) -> None:
    repository = repository.resolve(strict=True)
    # Refuse unusual mutations rather than silently omitting them from the evidence.
    fields = git(repository, "diff", "--name-status", "-z", "--no-renames",
                 "--ignore-submodules=all", "HEAD", "--").split(b"\0")
    fields.pop()  # Git terminates every record, including the empty result.
    if len(fields) % 2:
        raise ValueError("Malformed Git change list")
    records = []
    snapshots = []
    total = 0
    for status, encoded_path in zip(fields[::2], fields[1::2]):
        name = encoded_path.decode("utf-8")
        relative = PurePosixPath(name)
        if (status != b"M" or relative.is_absolute() or ".." in relative.parts
                or not name.startswith(scope + "/")):
            raise ValueError("Unexpected change outside the formatter's modification contract")
        path = repository.joinpath(*relative.parts)
        if any(part.is_symlink() for part in [path, *path.parents] if part != repository):
            raise ValueError("Refusing to collect a symlink")
        if not path.is_file() or path.stat().st_size > MAX_FILE_BYTES:
            raise ValueError("Formatter output must be a bounded regular file")
        before_size = int(git(repository, "cat-file", "-s", "HEAD:" + name))
        if before_size > MAX_FILE_BYTES:
            raise ValueError("Original source exceeds the evidence size limit")
        before = git(repository, "show", "HEAD:" + name)
        after = path.read_bytes()
        total += len(before) + len(after)
        if total > MAX_TOTAL_BYTES:
            raise ValueError("Formatter evidence exceeds the total size limit")
        records.append({"path": name, "before_blob": blob_id(before), "after_blob": blob_id(after),
                        "before_sha256": digest(before), "after_sha256": digest(after)})
        snapshots.append((relative, before, after))

    changes = patch(repository, scope)
    manifest = {"source_sha": git(repository, "rev-parse", "HEAD").decode().strip(),
                "scope": scope, "patch_sha256": digest(changes), "files": records}
    # Do not overwrite evidence from an earlier pass or retry.
    output.mkdir(parents=True, exist_ok=False)
    for relative, before, after in snapshots:
        for folder, data in (("before", before), ("after", after)):
            target = output / folder / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    (output / "changes.patch").write_bytes(changes)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def verify_stable(repository: Path, scope: str, output: Path) -> None:
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    previous = (output / "changes.patch").read_bytes()
    if (manifest["scope"] != scope
            or manifest["source_sha"] != git(repository, "rev-parse", "HEAD").decode().strip()
            or manifest["patch_sha256"] != digest(previous)):
        raise ValueError("Formatter evidence identity mismatch")
    if patch(repository, scope) != previous:
        raise ValueError("Formatting changed again on the second pass")
    (output / "idempotence.txt").write_text("Second formatting pass produced the identical patch.\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("collect", "verify-stable"))
    parser.add_argument("--repository", required=True, type=Path)
    parser.add_argument("--scope", required=True, choices=("src", "framework"))
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.operation == "collect":
        collect(args.repository, args.scope, args.output)
    else:
        verify_stable(args.repository, args.scope, args.output)


if __name__ == "__main__":
    main()
