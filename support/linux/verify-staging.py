#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Check release launcher staging using the app's actual CMake policy and rules."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[2]


def run(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def main():
    minimum = re.search(
        r"^cmake_minimum_required\([^\n]+\)$",
        (REPO / "CMakeLists.txt").read_text(),
        re.MULTILINE,
    ).group()
    source = (REPO / "src/CMakeLists.txt").read_text()
    rules = [
        line.strip()
        for line in source.splitlines()
        if 'install(TARGETS PrusaSlicer RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")' in line
        or ('install(CODE ' in line and 'create_symlink' in line)
    ]
    assert len(rules) == 3, "Update the fixture for changed production install rules."
    builder = (REPO / "support/linux/build-deb.sh").read_text()
    app_configure = builder.split('cmake -S . -B "$app_build"', 1)[1].split(
        'cmake --build "$app_build"', 1
    )[0]
    policy = re.search(r"-DCMAKE_POLICY_DEFAULT_CMP0087=(\w+)", app_configure)
    assert policy and policy.group(1) == "NEW", "Release app configure must enable CMP0087 NEW."

    with tempfile.TemporaryDirectory(prefix="slicer-staging-") as temporary:
        root = Path(temporary)
        for name, flags in (("legacy", []), ("production", [policy.group()])):
            fixture = root / name
            fixture.mkdir()
            (fixture / "CMakeLists.txt").write_text(
                minimum
                + '\nproject(SlicerStagingRegression LANGUAGES C)\n'
                + 'include(GNUInstallDirs)\n'
                + 'add_executable(PrusaSlicer main.c)\n'
                + 'set_target_properties(PrusaSlicer PROPERTIES OUTPUT_NAME "prusa-slicer")\n'
                + "\n".join(rules)
                + "\n"
            )
            (fixture / "main.c").write_text(
                '#include <stdio.h>\nint main(void) { puts("Slicer staging regression"); return 0; }\n'
            )
            build = fixture / "build"
            stage = fixture / "stage"
            run(["cmake", "-S", str(fixture), "-B", str(build), "-DCMAKE_INSTALL_PREFIX=/usr", *flags])
            run(["cmake", "--build", str(build)])
            run(["cmake", "--install", str(build)], env=dict(os.environ, DESTDIR=str(stage)))
            for launcher in ("slicer", "prusa-gcodeviewer"):
                path = stage / "usr/bin" / launcher
                assert path.is_symlink(), f"Missing staged launcher: {launcher}"
                if name == "legacy":
                    assert os.readlink(path) == "$<TARGET_FILE_NAME:PrusaSlicer>"
                    assert not path.exists(), "Legacy policy should reproduce the broken link."
                else:
                    assert os.readlink(path) == "prusa-slicer", "Launcher target must be relative."
                    assert os.access(path, os.X_OK), f"Staged launcher is not executable: {launcher}"
                    assert run([str(path)]).strip() == "Slicer staging regression"
    print("Staging regression passed: actual legacy policy fails; production policy resolves both relative launchers.")


if __name__ == "__main__":
    main()
