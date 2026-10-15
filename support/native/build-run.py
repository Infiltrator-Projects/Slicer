#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Build a deterministic, self-contained native installer from a Git commit."""

import argparse
import gzip
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def git(repository, *arguments):
    return subprocess.check_output(["git", "-C", str(repository), *arguments])


def build(repository, source_ref, output_directory):
    repository = Path(repository).resolve()
    source_sha = git(repository, "rev-parse", "--verify", "--end-of-options",
                     source_ref + "^{commit}").decode().strip()
    version = git(repository, "show", source_sha + ":support/VERSION").decode().strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("support/VERSION must contain a numeric semantic version")
    version_source = git(repository, "show", source_sha + ":version.inc").decode()
    match = re.search(r'^set\(SLIC3R_VERSION "([^"]+)"\)', version_source, re.MULTILINE)
    if not match or match.group(1) != version:
        raise ValueError("support/VERSION and version.inc differ at the selected commit")
    template = git(repository, "show", source_sha + ":support/native/bootstrap.sh.in").decode()
    roots = git(repository, "ls-tree", "--name-only", "-z", source_sha).decode().split("\0")
    roots = [path for path in roots if path and path not in (".git", "build", "dist")]
    output_directory = Path(output_directory).resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    artifact = output_directory / ("infiltrator-slicer-" + version + "-native-installer.run")

    with tempfile.TemporaryDirectory(prefix="slicer-native-bundle-") as temporary:
        payload = Path(temporary) / "source.tar.gz"
        # git archive supplies stable ordering, modes, symlinks and commit times.
        # The archive includes deps/vendor verbatim; no dependency is fetched.
        with payload.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw,
                               compresslevel=6, mtime=0) as compressed:
                process = subprocess.Popen(
                    ["git", "-C", str(repository), "archive", "--format=tar", source_sha,
                     "--", *roots], stdout=subprocess.PIPE)
                try:
                    shutil.copyfileobj(process.stdout, compressed, length=1024 * 1024)
                finally:
                    process.stdout.close()
                if process.wait():
                    raise RuntimeError("git archive failed")
        digest = hashlib.sha256()
        with payload.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        replacements = {
            "@SLICER_VERSION@": version,
            "@SOURCE_SHA@": source_sha,
            "@PAYLOAD_SHA256@": digest.hexdigest(),
            "@ARCHIVE_SIZE@": str(payload.stat().st_size),
            # Fixed width makes the byte offset independent of its value.
            "@PAYLOAD_OFFSET@": "0" * 20,
        }
        header = template
        for token, value in replacements.items():
            if token not in header:
                raise ValueError("bootstrap template lacks " + token)
            header = header.replace(token, value)
        header_bytes = header.encode()
        offset = len(header_bytes) + 1  # tail -c uses one-based offsets.
        header_bytes = header_bytes.replace(b"0" * 20, str(offset).zfill(20).encode())
        candidate = output_directory / (artifact.name + ".tmp")
        try:
            with candidate.open("wb") as output, payload.open("rb") as source:
                output.write(header_bytes)
                shutil.copyfileobj(source, output, length=1024 * 1024)
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
