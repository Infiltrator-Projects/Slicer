#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Exercise release-source downloads and Debian packaging with a real ELF fixture."""

import gzip
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
VERSION = (ROOT / "support/VERSION").read_text().strip()


def run(*args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise AssertionError(f"{args!r}:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def write(path, text, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


def main():
    module_spec = importlib.util.spec_from_file_location("build_run", ROOT / "support/native/build-run.py")
    builder = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(builder)
    with tempfile.TemporaryDirectory(prefix="slicer installer fixture ") as temp:
        work = Path(temp)
        repo = work / "source fixture"
        repo.mkdir()
        run("git", "init", "-q", "-b", "main", str(repo))
        write(repo / "support/VERSION", VERSION + "\n")
        write(repo / "support/version.inc", f'set(SLIC3R_VERSION "{VERSION}")\n')
        write(repo / "LICENSE", "Fixture license retained in source archive.\n")
        write(repo / "support/deps/vendor/fixture.txt", "Pinned dependency source fixture.\n")
        write(repo / "support/deps/vendor/manifest.cmake", "# Pinned fixture archive inventory.\n")
        write(repo / "CMakeLists.txt", "# Fixture CMake project\n")
        write(repo / "support/native/bootstrap.sh.in", (ROOT / "support/native/bootstrap.sh.in").read_text())
        write(repo / "support/build-native.sh", r'''#!/usr/bin/env bash
set -euo pipefail
stage=
profile=
while (($#)); do
    case "$1" in
        --stage-dir) stage=$2; shift 2 ;;
        --profile) profile=$2; shift 2 ;;
        --compiler|--jobs|--build-root|--install-prefix) shift 2 ;;
        --skip-tests) shift ;;
        *) exit 71 ;;
    esac
done
[[ "$profile" == native || "$profile" == aggressive ]]
[[ -n "$stage" ]]
mkdir -p "$stage/usr/bin" "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/scalable/apps"
version=$(cat support/VERSION)
printf '#include <stdio.h>\nint main(void){puts("Slicer-%s fixture");return 0;}\n' "$version" > fixture.c
gcc fixture.c -o "$stage/usr/bin/slicer"
printf '[Desktop Entry]\nName=Slicer\nExec=slicer %%F\nIcon=Slicer\nType=Application\n' > "$stage/usr/share/applications/Slicer.desktop"
printf '<svg/>\n' > "$stage/usr/share/icons/hicolor/scalable/apps/Slicer.svg"
''', executable=True)
        run("git", "-C", str(repo), "add", ".")
        run("git", "-C", str(repo), "-c", "user.name=Installer Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "core.hooksPath=/dev/null", "commit", "--no-gpg-sign", "-q", "-m", "Installer fixture")
        sha = run("git", "-C", str(repo), "rev-parse", "HEAD").strip()
        # Untracked build output must never enter the distributable.
        write(repo / "build/should-not-bundle", "untracked output\n")
        artifact = builder.build(repo, "HEAD", work / "first output")
        repeated = builder.build(repo, "HEAD", work / "second output")
        assert artifact.read_bytes() == repeated.read_bytes(), "same Git commit must produce identical bytes"
        help_text = run("bash", str(artifact), "--help")
        assert f"Slicer {VERSION}" in help_text
        assert "--install-prerequisites" not in help_text, "prerequisite installation must not require an opt-in switch"
        metadata = json.loads(run("bash", str(artifact), "--metadata"))
        assert metadata["version"] == VERSION and metadata["source_sha"] == sha
        assert artifact.stat().st_size < 16384, "installer must contain no source payload"
        expected_url = "https://github.com/Infiltrator-Projects/Slicer/archive/" + sha + ".tar.gz"
        assert metadata["source_url"] == expected_url
        archive = work / "release-source.tar.gz"
        archive.write_bytes(gzip.compress(subprocess.check_output(
            ["git", "-C", str(repo), "archive", "--format=tar", "--prefix=Slicer-" + sha + "/", "HEAD"]), mtime=0))
        tools = work / "fixture tools"
        write(tools / "curl", "#!" + sys.executable + "\n" + r'''import os, pathlib, shutil, sys
assert sys.argv[-1] == os.environ["LSM_FIXTURE_SOURCE_URL"]
if os.environ.get("LSM_FIXTURE_DOWNLOAD_FAILURE"):
    sys.exit(22)
output = pathlib.Path(sys.argv[sys.argv.index("--output") + 1])
if os.environ.get("LSM_FIXTURE_CORRUPT_ARCHIVE"):
    output.write_bytes(b"invalid source archive")
else:
    shutil.copyfile(os.environ["LSM_FIXTURE_ARCHIVE"], output)
''', executable=True)
        environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                           LSM_FIXTURE_SOURCE_URL=expected_url, LSM_FIXTURE_ARCHIVE=str(archive))

        build_dir = work / "build space $(touch injected)"
        run("bash", str(artifact), "--profile", "aggressive", "--jobs", "2", "--build-dir", str(build_dir), "--dry-run", "--no-install")
        assert not build_dir.exists(), "dry run must not create build state"
        extracted = work / "extracted source"
        run("bash", str(artifact), "--download-only", str(extracted), env=environment)
        assert (extracted / "LICENSE").read_text().startswith("Fixture license")
        assert (extracted / "support/deps/vendor/fixture.txt").is_file()
        assert not (extracted / "build").exists()
        assert not (extracted / ".git").exists()
        assert (extracted / ".slicer-source-sha").read_text().strip() == sha

        for name, failure in (("failed download", "LSM_FIXTURE_DOWNLOAD_FAILURE"),
                              ("corrupt download", "LSM_FIXTURE_CORRUPT_ARCHIVE")):
            destination = work / name
            refused = subprocess.run(["bash", str(artifact), "--download-only", str(destination)],
                                     env=dict(environment, **{failure: "1"}), text=True, capture_output=True)
            assert refused.returncode and not destination.exists(), refused.stderr
        refused = subprocess.run(["bash", str(artifact), "--download-only", str(extracted)],
                                 env=environment, capture_output=True)
        assert refused.returncode, "existing populated source must not be overwritten"

        # Host package detection is isolated. One prerequisite is deliberately
        # reported missing so the ordinary installer path must invoke APT via
        # sudo automatically before the real ELF package fixture is built.
        tools = work / "fixture tools"
        real_query = shutil.which("dpkg-query")
        write(tools / "dpkg-query", '#!/usr/bin/env bash\nif [[ $# == 3 && "$1" == -W && "$2" == \'-f=${Status}\' ]]; then\n if [[ "$3" == libglu1-mesa-dev ]]; then exit 1; fi\n printf "install ok installed"\nelse\n exec ' + repr(real_query) + ' "$@"\nfi\n', executable=True)
        write(tools / "id", '#!/usr/bin/env bash\nif [[ "$*" == -u ]]; then printf "1000\\n"; else exec /usr/bin/id "$@"; fi\n', executable=True)
        sudo_log = work / "sudo.log"
        write(tools / "sudo", '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$SLICER_FIXTURE_SUDO_LOG"\nexit 0\n', executable=True)
        environment = dict(environment, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                           SLICER_FIXTURE_SUDO_LOG=str(sudo_log))
        run("bash", str(artifact), "--profile", "aggressive", "--jobs", "2", "--build-dir", str(build_dir), "--no-install", env=environment)
        sudo_calls = sudo_log.read_text().splitlines()
        assert sudo_calls[0] == "apt-get update", sudo_calls
        assert any(call.startswith("apt-get install --no-install-recommends ") and "libglu1-mesa-dev" in call
                   for call in sudo_calls), sudo_calls
        deb = build_dir / "packages" / f"slicer_{VERSION}_amd64.deb"
        assert run("dpkg-deb", "-f", str(deb), "Package").strip() == "slicer"
        assert run("dpkg-deb", "-f", str(deb), "Version").strip() == VERSION
        assert run("dpkg-deb", "-f", str(deb), "Description").splitlines()[0] == "Slicer"
        control = run("dpkg-deb", "--field", str(deb))
        assert not any(line.startswith(("Provides:", "Replaces:", "Conflicts:"))
                       for line in control.splitlines()), control
        assert run("dpkg-deb", "-f", str(deb), "X-Slicer-Build-Profile").strip() == "aggressive"
        assert run("dpkg-deb", "-f", str(deb), "X-Slicer-Source-SHA").strip() == sha
        installed = work / "package extract"
        run("dpkg-deb", "--extract", str(deb), str(installed))
        assert run(str(installed / "usr/bin/slicer")).startswith("Slicer-" + VERSION)
        assert "Icon=Slicer" in (installed / "usr/share/applications/Slicer.desktop").read_text()
        assert not (work / "injected").exists()
    print("Native installer: automatic prerequisite installation, small deterministic downloader, exact source URL, download/corruption refusal, spaced paths, and real ELF Debian packaging passed.")


if __name__ == "__main__":
    main()
