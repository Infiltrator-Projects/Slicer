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


def verify_cleanup(repo, work, driver):
    """Stop at CMake after production preflight; all deletion targets are disposable."""
    tools = work / "cleanup tools"
    tools.mkdir()
    log = work / "cleanup-cmake.log"
    cmake = tools / "cmake"
    write(cmake, '#!/bin/sh\nif [ "$1" = --version ]; then printf "cmake version 3.31.6\\n"; exit 0; fi\nprintf called >> "$SLICER_CLEANUP_LOG"\nexit 42\n')
    cmake.chmod(0o755)
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       SLICER_CLEANUP_LOG=str(log))

    def invoke(build, *options):
        log.unlink(missing_ok=True)
        return subprocess.run(["bash", str(driver), "--build-root", str(build),
                               "--jobs", "1", "--skip-tests", *options],
                              cwd=repo, env=environment, text=True, capture_output=True)

    def rejected(build, *options):
        result = invoke(build, *options)
        assert result.returncode and not log.exists(), result.stdout + result.stderr

    sentinel = repo / "src/keep-source"
    write(sentinel, "source\n")
    foreign = work / "unrelated"
    write(foreign / "keep-data", "unrelated\n")
    file_target = work / "not-a-directory"
    write(file_target, "file\n")
    for target in (repo, repo.parent, repo / "src", foreign, file_target):
        rejected(target, "--clean")
        rejected(target)
    assert sentinel.read_text() == "source\n"
    assert (foreign / "keep-data").read_text() == "unrelated\n"
    assert file_target.read_text() == "file\n"

    # In-source CMake caches and copied markers cannot authorize source removal.
    write(repo / "src/.slicer-native-owner", str(repo) + "\n")
    write(repo / "src/deps/CMakeCache.txt", f"CMAKE_HOME_DIRECTORY:INTERNAL={repo / 'support/deps'}\n")
    rejected(repo / "src", "--clean")
    assert sentinel.exists()
    source_alias = work / "source alias"
    source_alias.symlink_to(repo / "src", target_is_directory=True)
    rejected(source_alias, "--clean")
    rejected(work / "fresh build", "--stage-dir", str(source_alias))
    assert sentinel.exists()

    build = work / "empty build"
    for stage in (repo, repo.parent, repo / "src", foreign, file_target, build,
                  build / "stage", work):
        rejected(build, "--stage-dir", str(stage))
    assert not build.exists(), "failed staging preflight must not claim a build directory"
    assert sentinel.exists() and (foreign / "keep-data").exists()

    marked = work / "other checkout build"
    write(marked / ".slicer-native-owner", "/another/checkout\n")
    write(marked / "app/CMakeCache.txt", f"CMAKE_HOME_DIRECTORY:INTERNAL={repo}\n")
    rejected(marked, "--clean")
    assert (marked / "app/CMakeCache.txt").exists()
    stage = work / "other checkout stage"
    stage_owner = Path(str(stage) + ".slicer-native-stage-owner")
    write(stage_owner, "/another/checkout\n")
    rejected(build, "--stage-dir", str(stage))
    stage_owner.unlink()
    linked_owner = work / "linked owner"
    write(linked_owner, str(repo) + "\n")
    stage_owner.symlink_to(linked_owner)
    rejected(build, "--stage-dir", str(stage))

    fingerprint = work / "fingerprint without ownership"
    write(fingerprint / ".slicer-native-config", "native-build-format=2\n")
    write(fingerprint / "app/CMakeCache.txt", "CMAKE_HOME_DIRECTORY:INTERNAL=/another/checkout\n")
    rejected(fingerprint, "--clean")
    assert (fingerprint / ".slicer-native-config").exists()

    dry = invoke(build, "--stage-dir", str(work / "fresh stage"), "--print-config")
    assert dry.returncode == 0 and not log.exists(), dry.stdout + dry.stderr
    assert not build.exists() and not (work / "fresh stage").exists()
    assert not (work / "fresh stage.slicer-native-stage-owner").exists()

    prepared = invoke(build)
    assert prepared.returncode == 42 and log.exists(), prepared.stdout + prepared.stderr
    assert (build / ".slicer-native-owner").read_text().strip() == str(repo)
    write(build / "stale", "old output\n")
    refreshed = invoke(build, "--clean")
    assert refreshed.returncode == 42 and log.exists(), refreshed.stdout + refreshed.stderr
    assert not (build / "stale").exists()

    for component, source in (("app", repo), ("deps", repo / "support/deps")):
        legacy = work / ("legacy " + component)
        write(legacy / component / "CMakeCache.txt", f"CMAKE_HOME_DIRECTORY:INTERNAL={source}\n")
        adopted = invoke(legacy, "--clean")
        assert adopted.returncode == 42 and log.exists(), adopted.stdout + adopted.stderr
        assert (legacy / ".slicer-native-owner").read_text().strip() == str(repo)


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
        verify_cleanup(repo, Path(temporary), driver)
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
        assert Path(str(stage) + ".slicer-native-stage-owner").read_text().strip() == str(repo)
        assert {path.name for path in stage.iterdir()} == {"usr"}, "ownership metadata must not enter the package"

        # Repeat real cleanup and staging with owned output, retaining the
        # unrelated directories protected by the preflight fixtures above.
        write(build / "stale-build", "old output\n")
        write(stage / "stale-stage", "old output\n")
        repeated = subprocess.run(command + ["--clean"], cwd=repo, text=True, capture_output=True)
        assert repeated.returncode == 0, repeated.stdout + repeated.stderr
        assert not (build / "stale-build").exists() and not (stage / "stale-stage").exists()
        assert os.access(stage / "usr/bin/slicer", os.X_OK)
        assert (repo / "src/keep-source").exists()
        assert (Path(temporary) / "unrelated/keep-data").exists()

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
    print("Native driver: cleanup ownership/refusal, legacy adoption, repeated staging, real two-pass GCC PGO, tests, slicing training, spaced paths, staged launcher and incompatible-cache refusal passed.")


if __name__ == "__main__":
    main()
