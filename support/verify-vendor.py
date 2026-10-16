#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Verify repository-owned dependency archives without network access."""

import hashlib
import re
import sys
from pathlib import Path, PureWindowsPath


class VerificationError(Exception):
    """A vendored dependency or its manifest is invalid."""


def read_manifest(path):
    """Read the manifest's literal, quoted CMake set assignments."""
    source = path.read_text(encoding="utf-8")
    assignment = re.compile(
        r'set\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s+"([^"\\]*)"\s*\)'
    )
    whitespace_or_comment = re.compile(r"(?:\s+|\#[^\n]*(?:\n|$))*")
    values = {}
    position = 0
    while position < len(source):
        position = whitespace_or_comment.match(source, position).end()
        if position == len(source):
            break
        match = assignment.match(source, position)
        if match is None:
            line = source.count("\n", 0, position) + 1
            raise VerificationError(
                "manifest line {} must be a literal quoted set assignment".format(line)
            )
        key, value = match.groups()
        if key in values:
            raise VerificationError("duplicate manifest variable: {}".format(key))
        values[key] = value
        position = match.end()
    return values


def vendor_path(vendor_directory, relative_path, description):
    """Resolve a portable relative path, rejecting escapes through symlinks."""
    if (
        not relative_path
        or "\\" in relative_path
        or "\x00" in relative_path
        or Path(relative_path).is_absolute()
        or PureWindowsPath(relative_path).drive
    ):
        raise VerificationError("{} has an invalid relative path".format(description))
    resolved = (vendor_directory / relative_path).resolve()
    try:
        resolved.relative_to(vendor_directory)
    except ValueError:
        raise VerificationError(
            "{} escapes the vendor directory: {}".format(description, relative_path)
        ) from None
    if resolved == vendor_directory:
        raise VerificationError("{} must name a file".format(description))
    return resolved


def verify(vendor_directory):
    values = read_manifest(vendor_directory / "manifest.cmake")
    package_list = values.get("SLICER_VENDOR_PACKAGES", "")
    packages = package_list.split(";")
    if not package_list or any(
        re.fullmatch(r"[A-Za-z0-9_]+", package) is None for package in packages
    ):
        raise VerificationError("SLICER_VENDOR_PACKAGES must list nonempty package names")
    if len(set(packages)) != len(packages):
        raise VerificationError("SLICER_VENDOR_PACKAGES contains duplicate package names")

    expected_keys = {"SLICER_VENDOR_PACKAGES"}
    declarations = []
    for package in packages:
        fields = {}
        for field in ("FILE", "SHA256", "PARTS", "URL"):
            key = "SLICER_VENDOR_{}_{}".format(package, field)
            expected_keys.add(key)
            if not values.get(key):
                raise VerificationError("missing or empty manifest variable: {}".format(key))
            fields[field] = values[key]
        if re.fullmatch(r"[0-9a-fA-F]{64}", fields["SHA256"]) is None:
            raise VerificationError("{} has an invalid SHA256".format(package))
        vendor_path(vendor_directory, fields["FILE"], "{} FILE".format(package))
        parts = fields["PARTS"].split(";")
        if any(not part for part in parts) or len(set(parts)) != len(parts):
            raise VerificationError("{} PARTS must contain unique nonempty paths".format(package))
        paths = [
            vendor_path(vendor_directory, part, "{} PARTS".format(package))
            for part in parts
        ]
        if len(set(paths)) != len(paths):
            raise VerificationError("{} PARTS refers to the same file more than once".format(package))
        for part, path in zip(parts, paths):
            if not path.is_file():
                raise VerificationError("{} is missing archive part: {}".format(package, part))
        declarations.append((package, fields["SHA256"].lower(), paths))

    unexpected_keys = set(values) - expected_keys
    if unexpected_keys:
        raise VerificationError(
            "undeclared manifest variables: {}".format(", ".join(sorted(unexpected_keys)))
        )

    total_bytes = 0
    for package, expected_hash, paths in declarations:
        digest = hashlib.sha256()
        for path in paths:
            with path.open("rb") as archive_part:
                while True:
                    chunk = archive_part.read(1024 * 1024)
                    if not chunk:
                        break
                    digest.update(chunk)
                    total_bytes += len(chunk)
        actual_hash = digest.hexdigest()
        if actual_hash != expected_hash:
            raise VerificationError(
                "{} SHA256 mismatch: expected {}, got {}".format(
                    package, expected_hash, actual_hash
                )
            )
    return len(packages), total_bytes


def main():
    vendor_directory = (Path(__file__).resolve().parent / "deps" / "vendor").resolve()
    try:
        package_count, total_bytes = verify(vendor_directory)
    except (VerificationError, OSError, UnicodeError) as error:
        print("Vendor verification failed: {}".format(error), file=sys.stderr)
        return 1
    print("Verified {} vendored dependency archives ({} bytes).".format(package_count, total_bytes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
