#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare main for release and reuse the existing verification/publisher workflows."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit


RELEASE_RUN_NAME = "Release Slicer / all / main"
ARTIFACTS = {"slicer-release-assets", "slicer-linux-release",
             "slicer-native-release", "slicer-windows-release"}
ACTIVE = {"queued", "in_progress", "waiting", "requested", "pending"}


class ReleaseError(RuntimeError):
    pass


def run(*command):
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        raise ReleaseError(result.stderr.strip() or result.stdout.strip()
                           or f"{command[0]} failed")
    return result.stdout.strip()


def version_tuple(value):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", value):
        raise ReleaseError("Use a version such as 0.0.9 (three numbers separated by dots).")
    return tuple(map(int, value.split(".")))


def choose_version(current, requested, tags):
    current_parts = version_tuple(current)
    if requested:
        if version_tuple(requested) < current_parts:
            raise ReleaseError("The release version cannot go backwards.")
        if "v" + requested in tags:
            raise ReleaseError(f"Version {requested} already exists. Choose a new version.")
        return requested
    candidate = current
    while "v" + candidate in tags:
        major, minor, patch = version_tuple(candidate)
        candidate = f"{major}.{minor}.{patch + 1}"
    return candidate


def api_pages(endpoint, key):
    # Older supported gh versions emit consecutive JSON documents when paginating.
    payload = run("gh", "api", "--paginate", endpoint)
    decoder = json.JSONDecoder()
    pages = []
    while payload.strip():
        page, end = decoder.raw_decode(payload.lstrip())
        pages.append(page)
        payload = payload.lstrip()[end:]
    if not pages or any(not isinstance(page, dict) or not isinstance(page.get(key), list) for page in pages):
        raise ReleaseError("GitHub returned an unexpected response; no new build was requested.")
    return [item for page in pages for item in page[key]]


def eligible_run(item, repository, sha):
    return (item.get("head_sha") == sha and item.get("head_branch") == "main"
            and item.get("path") == ".github/workflows/ci.yml"
            and item.get("head_repository", {}).get("full_name") == repository
            and (item.get("event") == "push" or
                 (item.get("event") == "workflow_dispatch"
                  and (item.get("display_title") == RELEASE_RUN_NAME or
                       (item.get("display_title") == "Verify Slicer / all / main"
                        and item.get("status") == "completed"
                        and item.get("conclusion") == "success")))))


def summary(message):
    print(message)
    destination = os.environ.get("GITHUB_STEP_SUMMARY")
    if destination:
        with open(destination, "a") as stream:
            stream.write(message + "\n")


def request_release(repository, sha, version):
    endpoint = f"repos/{repository}/actions/workflows/ci.yml/runs?branch=main&head_sha={sha}&per_page=100"
    candidates = [item for item in api_pages(endpoint, "workflow_runs")
                  if eligible_run(item, repository, sha)]
    candidates.sort(key=lambda item: item["id"], reverse=True)
    for item in candidates:
        if item.get("status") in ACTIVE:
            summary(f"Slicer {version}: builds and checks are already running. "
                    f"Publication follows when they pass.\n\n[Follow progress]({item['html_url']})")
            return
    for item in candidates:
        if item.get("status") != "completed" or item.get("conclusion") != "success":
            continue
        artifacts = api_pages(f"repos/{repository}/actions/runs/{item['id']}/artifacts?per_page=100", "artifacts")
        available = {artifact["name"] for artifact in artifacts if artifact.get("expired") is False}
        if not ARTIFACTS <= available:
            continue
        # The existing publisher revalidates source, platform jobs and exact bytes.
        run("gh", "workflow", "run", "release.yml", "--repo", repository, "--ref", "main",
            "-f", f"qualified_run_id={item['id']}")
        summary(f"Slicer {version}: publication requested using the existing tested files.\n\n"
                f"[Follow publication](https://github.com/{repository}/actions/workflows/release.yml)")
        return
    run("gh", "workflow", "run", "ci.yml", "--repo", repository, "--ref", "main",
        "-f", "platform=all", "-f", "publish_release=true")
    summary(f"Slicer {version}: builds and checks requested. Publication follows when they pass.\n\n"
            f"[Follow progress](https://github.com/{repository}/actions/workflows/ci.yml)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="", help="Optional new version; otherwise use the next available patch version.")
    parser.add_argument("--dry-run", action="store_true", help="Show the version without changing files or starting workflows.")
    args = parser.parse_args()
    root = Path(run("git", "rev-parse", "--show-toplevel"))
    os.chdir(root)
    if run("git", "branch", "--show-current") != "main":
        raise ReleaseError("Release Slicer must run from main.")
    if run("git", "status", "--porcelain"):
        raise ReleaseError("Save and push your project changes first; release preparation needs a clean main.")
    run("git", "fetch", "--no-tags", "origin", "main")
    if run("git", "rev-parse", "HEAD") != run("git", "rev-parse", "FETCH_HEAD"):
        raise ReleaseError("This copy differs from GitHub main. Synchronise it before releasing.")
    tags = {line.split("\t", 1)[1].removeprefix("refs/tags/")
            for line in run("git", "ls-remote", "--tags", "origin").splitlines()}
    current = (root / "support/VERSION").read_text().strip()
    version = choose_version(current, args.version.strip(), tags)
    if args.dry_run:
        summary(f"Would release Slicer {version}. No files or workflows changed.")
        return
    repository = os.environ.get("GITHUB_REPOSITORY") or os.environ.get("GH_REPO")
    if not repository:
        origin = run("git", "remote", "get-url", "origin")
        repository = (urlsplit(origin).path if "://" in origin else origin.split(":", 1)[-1]).strip("/").removesuffix(".git")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ReleaseError("Cannot identify this GitHub repository.")
    if version != current:
        (root / "support/VERSION").write_text(version + "\n")
        run("git", "add", "--", "support/VERSION")
        run("git", "commit", "-m", f"release: prepare Slicer {version}")
        run("git", "push", "origin", "HEAD:refs/heads/main")
    sha = run("git", "rev-parse", "HEAD")
    # GITHUB_TOKEN pushes do not trigger push workflows. Explicit dispatch is
    # essential here, and on retries we reuse suitable builds instead of cancelling them.
    request_release(repository, sha, version)


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, ValueError, KeyError) as error:
        print(f"Release could not be completed: {error}\n"
              "Run Release Slicer again after resolving the reported problem. "
              "Published releases have not been replaced.", file=sys.stderr)
        sys.exit(1)
