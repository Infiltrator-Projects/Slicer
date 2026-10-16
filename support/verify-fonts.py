#!/usr/bin/env python3
"""Verify the MB font bytes and native font families in source or an installer."""
import hashlib
import json
from pathlib import Path
import struct
import sys


ROOT = Path(__file__).resolve().parents[1]


def families(data):
    assert data[:4] == b"\x00\x01\x00\x00", "Expected a native TrueType font"
    tables = struct.unpack_from(">H", data, 4)[0]
    for index in range(tables):
        tag, _, offset, _ = struct.unpack_from(">4sIII", data, 12 + index * 16)
        if tag == b"name":
            break
    else:
        raise AssertionError("Missing font name table")
    _, count, strings = struct.unpack_from(">HHH", data, offset)
    result = set()
    for index in range(count):
        platform, _, _, name, length, start = struct.unpack_from(">6H", data, offset + 6 + index * 12)
        if name in (1, 16) and platform in (0, 3):
            result.add(data[offset + strings + start:offset + strings + start + length].decode("utf-16-be"))
    return result


def verify(directory):
    manifest = json.loads((ROOT / "support/resources/fonts/manifest.json").read_text())
    expected = {font["file"] for font in manifest["fonts"]}
    actual = {path.name for path in directory.iterdir()
              if path.suffix.lower() in (".ttf", ".ttc", ".otf", ".woff", ".woff2")}
    assert actual == expected, f"Unexpected bundled font inventory: {actual ^ expected}"
    for font in manifest["fonts"]:
        data = (directory / font["file"]).read_bytes()
        assert hashlib.sha256(data).hexdigest() == font["sha256"], font["file"]
        assert font["family"] in families(data), font["file"]
    print("Verified all three bundled MB fonts: exact bytes and native font families.")


if __name__ == "__main__":
    verify(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "support/resources/fonts")
