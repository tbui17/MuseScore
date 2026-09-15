#!/usr/bin/env python3
"""Trusted fork pipeline control. Never execute code from release artifacts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = "tbui17/MuseScore"
SHA = re.compile(r"[0-9a-f]{40}")
TAG = re.compile(r"fork-[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]*")
IDENTITIES = ("repository", "requested_source_ref", "source_sha", "framework_url", "framework_sha", "workflow_sha", "run_id", "run_attempt")


def command(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE).stdout.strip()


def api(path, method="GET", data=None, missing_ok=False):
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request("https://api.github.com/" + path, headers=headers, method=method,
                                     data=None if data is None else json.dumps(data).encode())
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if missing_ok and error.code == 404:
            return None
        raise RuntimeError(f"GitHub {method} {path}: HTTP {error.code}") from None


def valid_sha(value):
    if not SHA.fullmatch(value):
        raise ValueError("Expected a full lowercase commit SHA")
    return value


def valid_ref(value):
    if not value or len(value) > 200 or value.startswith("-") or not re.fullmatch(r"[A-Za-z0-9_./-]+", value):
        raise ValueError("Source must be a repository branch, tag, or full commit SHA")
    if not SHA.fullmatch(value):
        command("git", "check-ref-format", "refs/heads/" + value)
    return value


def valid_tag(value):
    if not TAG.fullmatch(value):
        raise ValueError("Release tag must be fork-YYYY.MM.DD.N, with positive N")
    command("git", "check-ref-format", "refs/tags/" + value)
    return value

def resolve_effective_use_cache(event, requested):
    """Resolve the single cache policy used by preflight and every cache step."""
    requested = (requested or "").strip().lower()
    if requested not in ("", "true", "false"):
        raise ValueError("use_cache must be true or false")
    if event == "pull_request":
        return False
    if requested == "false":
        return False
    return event in ("push", "workflow_dispatch")


def check_submodule(source, repository):
    owner = "tbui17" if repository == REPOSITORY else "musescore"
    expected_url = f"https://github.com/{owner}/muse_framework.git"
    actual = command("git", "config", "-f", ".gitmodules", "submodule.muse_framework.url", cwd=source)
    if actual != expected_url:
        raise ValueError(f"Framework URL must be {expected_url}, got {actual}")
    entry = command("git", "ls-tree", "HEAD", "--", "muse", cwd=source).split()
    if len(entry) != 4 or entry[:2] != ["160000", "commit"] or entry[3] != "muse":
        raise ValueError("muse must be an exact committed gitlink")
    expected_sha = valid_sha(entry[2])
    command("git", "submodule", "update", "--init", "--recursive", "--", "muse", cwd=source)
    actual_sha = command("git", "rev-parse", "HEAD", cwd=source / "muse")
    if actual_sha != expected_sha:
        raise ValueError("Framework checkout does not match committed gitlink")
    status = command("git", "submodule", "status", "--recursive", cwd=source)
    if any(line.startswith(("-", "+", "U")) for line in status.splitlines()):
        raise ValueError("Recursive submodule checkout is incomplete or mismatched")
    if owner == "musescore":
        command("git", "fetch", "origin", "main", cwd=source / "muse")
        command("git", "merge-base", "--is-ancestor", expected_sha, "FETCH_HEAD", cwd=source / "muse")
    return expected_url, expected_sha


def preflight(args):
    repository = os.environ["GITHUB_REPOSITORY"]
    if repository != REPOSITORY:
        raise ValueError("Fork pipeline only supports " + REPOSITORY)
    event = os.environ["GITHUB_EVENT_NAME"]
    release = os.environ.get("CREATE_RELEASE", "false") == "true"
    workflow_sha = valid_sha(os.environ["WORKFLOW_SHA"])
    effective_use_cache = resolve_effective_use_cache(event, os.environ.get("USE_CACHE"))
    requested = valid_ref(os.environ.get("SOURCE_REF", "main")) if event == "workflow_dispatch" else valid_sha(os.environ["GITHUB_SHA"])
    if release:
        if event != "workflow_dispatch" or os.environ["GITHUB_REF"] != "refs/heads/main":
            raise ValueError("Releases require manual dispatch of the approved main workflow")
        valid_tag(os.environ.get("RELEASE_TAG", ""))
    commit = api(f"repos/{repository}/commits/{urllib.parse.quote(requested, safe='')}")
    source_sha = valid_sha(commit["sha"])
    if release:
        # Reviewed source policy: release commits must already be on main history.
        comparison = api(f"repos/{repository}/compare/{source_sha}...main")
        if comparison["status"] not in ("ahead", "identical"):
            raise ValueError("Release source must be reviewed and merged into main first")
    source = args.source.resolve()
    command("git", "clone", "--filter=blob:none", "--no-checkout", f"https://github.com/{repository}.git", str(source))
    command("git", "fetch", "--depth=1", "origin", source_sha, cwd=source)
    command("git", "checkout", "--detach", source_sha, cwd=source)
    url, framework_sha = check_submodule(source, repository)
    if not (source / "muse/buildscripts/cmake/deps/dependencies.lock.cmake").is_file():
        raise ValueError("Selected source lacks the committed framework dependency repair; update its gitlink through review")
    provenance = dict(repository=repository, requested_source_ref=requested, source_sha=source_sha,
                      framework_url=url, framework_sha=framework_sha, workflow_sha=workflow_sha,
                      run_id=os.environ["GITHUB_RUN_ID"], run_attempt=os.environ["GITHUB_RUN_ATTEMPT"],
                      effective_use_cache="true" if effective_use_cache else "false")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            for name, value in provenance.items():
                output.write(f"{name}={value}\n")
    print(json.dumps(provenance, indent=2))

def verify_artifact(directory, expected):
    directory = directory.resolve()
    manifest_path = directory / "build-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    for name in IDENTITIES:
        if str(manifest.get(name)) != str(expected[name]):
            raise ValueError(f"Artifact provenance mismatch: {name}")
    package = manifest["package"]
    name = package["filename"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]+\.zip", name):
        raise ValueError("Unsafe package filename")
    required = {name, "build-manifest.json", "SHA256SUMS.txt"}
    if {p.name for p in directory.iterdir()} != required:
        raise ValueError("Expected exactly package, manifest and checksum files")
    for path in directory.iterdir():
        if path.is_symlink() or not path.is_file():
            raise ValueError("Artifact must contain regular files only")
    archive = directory / name
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if package["size"] != archive.stat().st_size or package["size"] <= 0 or digest != package["sha256"]:
        raise ValueError("Package size or SHA-256 mismatch")
    sums = (directory / "SHA256SUMS.txt").read_text(encoding="utf-8-sig").strip()
    if sums != f"{digest}  {name}":
        raise ValueError("Checksum file does not identify the exact package bytes")
    return manifest


def release(args):
    if os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch" or os.environ.get("GITHUB_REF") != "refs/heads/main" or os.environ.get("CREATE_RELEASE") != "true":
        raise ValueError("Draft release is manual-only from main")
    tag = valid_tag(os.environ["RELEASE_TAG"])
    expected = json.loads(args.provenance.read_text(encoding="utf-8"))
    if expected["repository"] != REPOSITORY or expected["workflow_sha"] != os.environ["WORKFLOW_SHA"]:
        raise ValueError("Unexpected repository or workflow identity")
    manifest = verify_artifact(args.artifacts, expected)
    base = f"repos/{REPOSITORY}"
    # Deliberately fail closed on ALL collisions, including partial prior operations.
    # Recovery uses a new tag; never overwrite, move or automatically delete state.
    if api(f"{base}/git/ref/tags/{tag}", missing_ok=True) or api(f"{base}/releases/tags/{tag}", missing_ok=True):
        raise ValueError("Tag/release already exists. Inspect partial state and use a new tag; nothing was changed")
    comparison = api(f"{base}/compare/{valid_sha(expected['source_sha'])}...main")
    if comparison["status"] not in ("ahead", "identical"):
        raise ValueError("Release source is not in reviewed main history")
    api(f"{base}/git/refs", method="POST", data={"ref": f"refs/tags/{tag}", "sha": expected["source_sha"]})
    body = ("Unsigned Windows x64 extract-and-run archive, development channel, RelWithDebInfo. "
            "Not an MSI installer or a PortableApps package. Extract the complete ZIP before launching. "
            "External crash upload and upstream auto-update are disabled.\n\n"
            f"Application: https://github.com/{REPOSITORY}/tree/{expected['source_sha']}\n"
            f"Framework: https://github.com/tbui17/muse_framework/tree/{expected['framework_sha']}\n"
            f"Validated run: https://github.com/{REPOSITORY}/actions/runs/{expected['run_id']}\n\n"
            "Preserve bundled license notices. Before public distribution, review corresponding-source obligations "
            "including submodules and dependencies. Automated tests do not establish NVDA/JAWS/device behavior. "
            "Publication is a separate owner action.\n")
    record = api(f"{base}/releases", method="POST", data={"tag_name": tag, "name": tag, "body": body, "draft": True, "prerelease": True})
    files = [args.artifacts / manifest["package"]["filename"], args.artifacts / "SHA256SUMS.txt", args.artifacts / "build-manifest.json"]
    command("gh", "release", "upload", tag, *(str(path.resolve()) for path in files), "--repo", REPOSITORY)
    result = api(f"{base}/releases/{record['id']}")
    target = api(f"{base}/git/ref/tags/{tag}")
    if target["object"]["type"] != "commit" or target["object"]["sha"] != expected["source_sha"] or not result["draft"] or not result["prerelease"]:
        raise ValueError("Created release identity verification failed; inspect draft manually")
    assets = {asset["name"]: asset for asset in result["assets"]}
    if set(assets) != {path.name for path in files}:
        raise ValueError("Release asset list mismatch; inspect incomplete draft")
    # Server digest is independently computed after upload, not artifact-provided metadata.
    for path in files:
        with path.open("rb") as stream:
            digest = "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest()
        if assets[path.name].get("digest") != digest or assets[path.name]["size"] != path.stat().st_size:
            raise ValueError(f"Uploaded asset verification failed: {path.name}")
    print(result["html_url"])


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="operation", required=True)
    p = sub.add_parser("preflight")
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p = sub.add_parser("submodule")
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--repository", required=True)
    p = sub.add_parser("release")
    p.add_argument("--artifacts", type=Path, required=True)
    p.add_argument("--provenance", type=Path, required=True)
    args = parser.parse_args()
    if args.operation == "preflight":
        preflight(args)
    elif args.operation == "submodule":
        print(check_submodule(args.source.resolve(), args.repository))
    else:
        release(args)


if __name__ == "__main__":
    main()
