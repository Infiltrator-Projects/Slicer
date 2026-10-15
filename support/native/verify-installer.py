#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Exercise the real self-extractor and Debian packaging using a small ELF fixture."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
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
        write(repo / "version.inc", f'set(SLIC3R_VERSION "{VERSION}")\n')
        write(repo / "LICENSE", "Fixture license retained in source archive.\n")
        write(repo / "deps/vendor/fixture.txt", "Pinned dependency source fixture.\n")
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
printf '[Desktop Entry]\nName=Slicer\nExec=slicer %%F\nIcon=InfiltratorSlicer\nType=Application\n' > "$stage/usr/share/applications/InfiltratorSlicer.desktop"
printf '<svg/>\n' > "$stage/usr/share/icons/hicolor/scalable/apps/InfiltratorSlicer.svg"
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
        assert f"Slicer {VERSION}" in run("bash", str(artifact), "--help")
        metadata = json.loads(run("bash", str(artifact), "--metadata"))
        assert metadata["version"] == VERSION and metadata["source_sha"] == sha

        build_dir = work / "build space $(touch injected)"
        run("bash", str(artifact), "--profile", "aggressive", "--jobs", "2", "--build-dir", str(build_dir), "--dry-run", "--no-install")
        assert not build_dir.exists(), "dry run must not create build state"
        extracted = work / "extracted source"
        run("bash", str(artifact), "--extract-only", str(extracted))
        assert (extracted / "LICENSE").read_text().startswith("Fixture license")
        assert (extracted / "deps/vendor/fixture.txt").is_file()
        assert not (extracted / "build").exists()
        assert not (extracted / ".git").exists()
        assert (extracted / ".slicer-source-sha").read_text().strip() == sha

        corrupt = work / "corrupt.run"
        payload = bytearray(artifact.read_bytes())
        payload[-20] ^= 1
        corrupt.write_bytes(payload)
        refused = subprocess.run(["bash", str(corrupt), "--extract-only", str(work / "corrupt source")], text=True, capture_output=True)
        assert refused.returncode and "SHA256 mismatch" in refused.stderr, refused.stderr
        assert not (work / "corrupt source").exists()
        refused = subprocess.run(["bash", str(artifact), "--extract-only", str(extracted)], capture_output=True)
        assert refused.returncode, "existing populated source must not be overwritten"

        # Host package detection is isolated; Debian's real library dependency
        # lookup and ELF packaging still run, and any sudo call is a failure.
        tools = work / "fixture tools"
        real_query = shutil.which("dpkg-query")
        write(tools / "dpkg-query", '#!/usr/bin/env bash\nif [[ $# == 3 && "$1" == -W && "$2" == \'-f=${Status}\' ]]; then\n printf "install ok installed"\nelse\n exec ' + repr(real_query) + ' "$@"\nfi\n', executable=True)
        write(tools / "id", '#!/usr/bin/env bash\nif [[ "$*" == -u ]]; then printf "1000\\n"; else exec /usr/bin/id "$@"; fi\n', executable=True)
        write(tools / "sudo", '#!/usr/bin/env bash\nprintf "unexpected privilege request\\n" >&2\nexit 89\n', executable=True)
        environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"])
        run("bash", str(artifact), "--profile", "aggressive", "--jobs", "2", "--build-dir", str(build_dir), "--no-install", env=environment)
        deb = build_dir / "packages" / f"infiltrator-slicer_{VERSION}_amd64.deb"
        assert run("dpkg-deb", "-f", str(deb), "Package").strip() == "infiltrator-slicer"
        assert run("dpkg-deb", "-f", str(deb), "Version").strip() == VERSION
        assert run("dpkg-deb", "-f", str(deb), "X-Slicer-Build-Profile").strip() == "aggressive"
        assert run("dpkg-deb", "-f", str(deb), "X-Slicer-Source-SHA").strip() == sha
        installed = work / "package extract"
        run("dpkg-deb", "--extract", str(deb), str(installed))
        assert run(str(installed / "usr/bin/slicer")).startswith("Slicer-" + VERSION)
        assert "Icon=InfiltratorSlicer" in (installed / "usr/share/applications/InfiltratorSlicer.desktop").read_text()
        assert not (work / "injected").exists()
    print("Native installer: deterministic bundle, verified extraction, corruption refusal, spaced paths, and real ELF Debian packaging passed.")


if __name__ == "__main__":
    main()
