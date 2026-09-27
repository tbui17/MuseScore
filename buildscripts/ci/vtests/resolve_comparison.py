#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
"""Validate immutable visual-test inputs before allowing expensive CI jobs."""
import json
import os
from pathlib import Path
import re
import sys


def commit_sha(value: object, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", value):
        raise ValueError(f"{label} must be a full 40-character commit SHA")
    if value == "0" * 40:
        raise ValueError(f"{label} must not be the zero SHA")
    return value.lower()


def artifact_name(value: str) -> str:
    forbidden = set('":<>|*?/\\')
    cleaned = "".join(c if c.isprintable() and c not in forbidden else "_" for c in value)
    return cleaned.encode("utf-8")[:200].decode("utf-8", errors="ignore").strip()


def resolve(event_name: str, event: object, candidate: object, build_number: str) -> dict[str, str]:
    if not isinstance(event, dict):
        raise ValueError("Event payload must be an object")
    current = commit_sha(candidate, "Candidate")
    if not re.fullmatch(r"[0-9]{1,20}", build_number):
        raise ValueError("Build number must contain 1 to 20 decimal digits")

    if event_name == "pull_request":
        pr = event.get("pull_request")
        if not isinstance(pr, dict) or not isinstance(pr.get("base"), dict):
            raise ValueError("Pull request base metadata is missing")
        reference = commit_sha(pr["base"].get("sha"), "Pull request base")
        number = event.get("number")
        if type(number) is not int or number <= 0:
            raise ValueError("Pull request number must be a positive integer")
        title = pr.get("title", "")
        if not isinstance(title, str):
            raise ValueError("Pull request title must be text")
        description = f"PR {number} {title}"
    elif event_name == "workflow_dispatch":
        inputs = event.get("inputs")
        if not isinstance(inputs, dict):
            raise ValueError("Manual runs require reference_sha")
        reference = commit_sha(inputs.get("reference_sha"), "Manual reference")
        description = f"manual {reference[:12]}"
    else:
        raise ValueError("Unsupported visual-test event")

    if reference == current:
        raise ValueError("Reference and candidate must be different commits")
    return {
        "do_run": "true",
        "reference_ref": reference,
        "candidate_ref": current,
        "artifact_name": artifact_name(f"VTests Comparison {build_number} {description}"),
    }


def main() -> int:
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
        values = resolve(os.environ["GITHUB_EVENT_NAME"], event, os.environ["GITHUB_SHA"],
                         os.environ["BUILD_NUMBER"])
        # Emit nothing until every input passes. Values cannot inject output lines.
        output = "".join(f"{key}={value}\n" for key, value in values.items())
        with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
            stream.write(output)
    except (KeyError, OSError, ValueError) as error:
        print(f"Invalid visual-test inputs: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
