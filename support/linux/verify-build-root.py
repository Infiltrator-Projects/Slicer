#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Exercise the production release script against disposable build roots."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

SCRIPT = Path(__file__).with_name("build-deb.sh")
with tempfile.TemporaryDirectory(prefix="slicer-build-root-") as temporary:
    base = Path(temporary).resolve()
    source = base / "source"
    (source / "support").mkdir(parents=True)
    (source / "support/VERSION").write_text("0.0.4\n")
    (source / "support/version.inc").write_text("# fixture\n")
    (source / "CMakeLists.txt").write_text("# fixture\n")
    sentinel = source / "keep-source"
    sentinel.write_text("preserve\n")
    binary = base / "bin"
    binary.mkdir()
    log = base / "cmake-called"
    for name, contents in {
        "pkg-config": "#!/bin/sh\nexit 0\n",
        "cmake": '#!/bin/sh\nprintf called >> "$FIXTURE_LOG"\nexit 42\n',
    }.items():
        path = binary / name
        path.write_text(contents)
        path.chmod(0o755)
    environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                       FIXTURE_LOG=str(log))
    def invoke(build, *options):
        log.unlink(missing_ok=True)
        return subprocess.run(["bash", str(SCRIPT), "--build-root", str(build), *options],
                              cwd=source, env=environment, capture_output=True, text=True)
    rejected = invoke(source, "--clean")
    assert rejected.returncode != 0 and not log.exists(), rejected.stdout + rejected.stderr
    assert sentinel.read_text() == "preserve\n"
    foreign = base / "foreign"
    foreign.mkdir()
    protected = foreign / "unrelated"
    protected.write_text("preserve\n")
    rejected = invoke(foreign, "--clean")
    assert rejected.returncode != 0 and not log.exists(), rejected.stdout + rejected.stderr
    assert protected.read_text() == "preserve\n"
    owned = base / "owned"
    configured = invoke(owned)
    assert configured.returncode == 42 and log.exists(), configured.stdout + configured.stderr
    assert (owned / ".slicer-release-owner").read_text().strip() == str(source)
    (owned / "stale").write_text("old build\n")
    configured = invoke(owned, "--clean")
    assert configured.returncode == 42 and log.exists(), configured.stdout + configured.stderr
    assert not (owned / "stale").exists() and sentinel.exists() and protected.exists()
    legacy = base / "legacy"
    (legacy / "deps").mkdir(parents=True)
    (legacy / "deps/CMakeCache.txt").write_text(
        "CMAKE_HOME_DIRECTORY:INTERNAL=" + str(source / "deps") + "\n")
    configured = invoke(legacy)
    assert configured.returncode == 42 and log.exists(), configured.stdout + configured.stderr
    assert (legacy / ".slicer-release-owner").exists()
print("Release build-root ownership contracts passed")
