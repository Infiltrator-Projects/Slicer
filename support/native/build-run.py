#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build a small deterministic downloader for one exact Slicer release commit."""

import argparse
from pathlib import Path
import re
import subprocess


def git(repository, *arguments):
    return subprocess.check_output(["git", "-C", str(repository), *arguments])


def build(repository, source_ref, output_directory):
    repository = Path(repository).resolve()
    source_sha = git(repository, "rev-parse", "--verify", "--end-of-options",
                     source_ref + "^{commit}").decode().strip()
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise ValueError("Git returned an invalid release source revision")
    version = git(repository, "show", source_sha + ":support/VERSION").decode().strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("support/VERSION must contain a numeric semantic version")
    template = git(repository, "show", source_sha + ":support/native/bootstrap.sh.in").decode()
    replacements = {
        "@SLICER_VERSION@": version,
        "@SOURCE_SHA@": source_sha,
        "@SOURCE_URL@": "https://github.com/Infiltrator-Projects/Slicer/archive/" + source_sha + ".tar.gz",
    }
    for token, value in replacements.items():
        if token not in template:
            raise ValueError("bootstrap template lacks " + token)
        template = template.replace(token, value)
    if re.search(r"@[A-Z][A-Z0-9_]*@", template):
        raise ValueError("bootstrap template contains an unresolved release value")
    output_directory = Path(output_directory).resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    artifact = output_directory / ("slicer-" + version + "-native-installer.run")
    candidate = artifact.with_name(artifact.name + ".tmp")
    try:
        candidate.write_bytes(template.encode())
        candidate.chmod(0o755)
        candidate.replace(artifact)
    finally:
        candidate.unlink(missing_ok=True)
    print(artifact)
    return artifact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-ref", default="HEAD")
    parser.add_argument("--output-dir", default="dist")
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    arguments = parser.parse_args()
    build(arguments.repository, arguments.source_ref, arguments.output_dir)


if __name__ == "__main__":
    main()
