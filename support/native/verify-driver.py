#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Run the production native driver through real GCC PGO and CMake staging."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def main():
    with tempfile.TemporaryDirectory(prefix="slicer native PGO ") as temporary:
        repo = Path(temporary) / "source with spaces"
        repo.mkdir()
        build = Path(temporary) / "build with spaces"
        stage = Path(temporary) / "stage with spaces"
        write(repo / "support/version.inc", 'set(SLIC3R_VERSION "0.0.2")\n')
        write(repo / "support/VERSION", "0.0.2\n")
        write(repo / "support/deps/vendor/manifest.cmake", "# No external libraries in this compiler fixture.\n")
        write(repo / "support/verify-vendor.py", "print('Compiler fixture has no external dependencies.')\n")
        write(repo / "support/tests/data/default_fff.ini", "# Fixture configuration\n")
        write(repo / "support/tests/data/20mm_cube.obj", "# Fixture model\n")
        write(repo / "support/deps/CMakeLists.txt", "cmake_minimum_required(VERSION 3.13)\nproject(dependency_fixture NONE)\n")
        write(repo / "CMakeLists.txt", r'''cmake_minimum_required(VERSION 3.13)
project(native_driver_fixture LANGUAGES C CXX)
add_executable(prusa-slicer main.cpp)
set_target_properties(prusa-slicer PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/src")
enable_testing()
add_test(NAME real_native_program COMMAND prusa-slicer --info fixture.obj)
install(TARGETS prusa-slicer RUNTIME DESTINATION bin)
install(CODE "execute_process(COMMAND \"${CMAKE_COMMAND}\" -E create_symlink $<TARGET_FILE_NAME:prusa-slicer> \"\$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/bin/slicer\")")
''')
        write(repo / "main.cpp", r'''#include <fstream>
#include <iostream>
#include <string>
int main(int argc, char **argv) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (std::string(argv[i]) == "--output") {
            std::ofstream out(argv[i + 1]);
            out << "G28\nG1 X20 Y20\n";
        }
    }
    std::cout << "Slicer native compiler fixture\n";
    return 0;
}
''')
        driver = ROOT / "support/build-native.sh"
        command = ["bash", str(driver), "--profile", "aggressive", "--jobs", "2",
                   "--build-root", str(build), "--stage-dir", str(stage), "--install-prefix", "/usr"]
        result = subprocess.run(command, cwd=repo, text=True, capture_output=True)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        assert "Building instrumented aggressive binary" in result.stdout
        assert "Rebuilding aggressive binary using measured PGO profile" in result.stdout
        assert result.stdout.count("100% tests passed") == 2
        assert list((build / "pgo").rglob("*.gcda")), "actual GCC training data missing"
        assert (build / "pgo/training-cube.gcode").stat().st_size > 0
        assert (stage / "usr/bin/slicer").is_symlink()
        assert os.access(stage / "usr/bin/slicer", os.X_OK)
        cache = (build / "app/CMakeCache.txt").read_text()
        assert "-fprofile-use=" in cache and "-march=native" in cache
        assert "CMAKE_POLICY_DEFAULT_CMP0087:UNINITIALIZED=NEW" in cache

        # A cache created for aggressive PGO must refuse ordinary native reuse.
        changed = command.copy()
        changed[changed.index("aggressive")] = "native"
        refused = subprocess.run(changed, cwd=repo, text=True, capture_output=True)
        assert refused.returncode and "build settings changed" in refused.stderr
        if shutil.which("clang++"):
            selected = subprocess.run(["bash", str(driver), "--compiler", "clang++", "--print-config"],
                                      cwd=repo, text=True, capture_output=True, check=True)
            cc_line = next(line for line in selected.stdout.splitlines() if "C compiler:" in line)
            assert "clang" in cc_line, cc_line
    print("Native driver: real two-pass GCC PGO, tests, slicing training, spaced paths, staged launcher and incompatible-cache refusal passed.")


if __name__ == "__main__":
    main()
