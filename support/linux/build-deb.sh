#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Reproducible Linux release-package builder for Slicer.
# This is intentionally a portable release build: machine-specific optimisation
# belongs to support/build-native.sh, never to the distributable Debian package.

set -euo pipefail

jobs=
output_dir=dist
build_root=build/release-linux

usage() {
    cat <<'EOF'
Usage: support/linux/build-deb.sh [options]

Options:
  --jobs NUMBER       Parallel build jobs (default: online CPUs)
  --output-dir PATH   Release output directory (default: dist)
  --build-root PATH   Build root (default: build/release-linux)
  --clean             Remove release build state first
  -h, --help          Show this help
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

clean=0
while (($#)); do
    case "$1" in
        --jobs)
            (($# >= 2)) || fail "--jobs requires a value"
            jobs=$2
            shift 2
            ;;
        --output-dir)
            (($# >= 2)) || fail "--output-dir requires a value"
            output_dir=$2
            shift 2
            ;;
        --build-root)
            (($# >= 2)) || fail "--build-root requires a value"
            build_root=$2
            shift 2
            ;;
        --clean)
            clean=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ -f CMakeLists.txt && -f version.inc && -f support/VERSION ]] ||
    fail "run this script from the Slicer repository root"

for tool in cmake dpkg-deb dpkg-shlibdeps sed grep; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

arch=$(dpkg --print-architecture)
[[ "$arch" == amd64 ]] || fail "release .deb currently targets amd64; runner is $arch"

version=$(tr -d '[:space:]' < support/VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    fail "support/VERSION is not a semantic numeric version"
cmake_version=$(sed -n 's/^set(SLIC3R_VERSION "\([^"]*\)").*/\1/p' version.inc)
[[ "$cmake_version" == "$version" ]] ||
    fail "support/VERSION ($version) does not match version.inc ($cmake_version)"

if [[ -z "$jobs" ]]; then
    if command -v nproc >/dev/null 2>&1; then
        jobs=$(nproc)
    else
        jobs=2
    fi
fi
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive integer"

if ((clean)); then
    rm -rf -- "$build_root"
fi

repo_root=$(pwd -P)
deps_build="$repo_root/$build_root/deps"
deps_prefix="$deps_build/destdir/usr/local"
app_build="$repo_root/$build_root/app"
stage="$repo_root/$build_root/stage"
metadata="$repo_root/$build_root/package-meta"
output="$repo_root/$output_dir"
artifact="$output/infiltrator-slicer_${version}_amd64.deb"

rm -rf "$stage" "$metadata"
mkdir -p "$output"

echo "Building Slicer $version Linux release..."
cmake -S deps -B "$deps_build" \
    -DDEP_WX_GTK3=ON \
    -DDESTDIR="$deps_build/destdir" \
    -DCMAKE_BUILD_TYPE=Release
cmake --build "$deps_build" --parallel 1

cmake -S . -B "$app_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DSLIC3R_STATIC=ON \
    -DSLIC3R_GTK=3 \
    -DSLIC3R_PCH=OFF \
    -DSLIC3R_FHS=ON \
    -DSLIC3R_BUILD_TESTS=ON \
    -DCMAKE_PREFIX_PATH="$deps_prefix"
cmake --build "$app_build" --parallel "$jobs"

if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a ctest --test-dir "$app_build" --output-on-failure --parallel "$jobs"
else
    ctest --test-dir "$app_build" --output-on-failure --parallel "$jobs"
fi

DESTDIR="$stage" cmake --install "$app_build"
[[ -x "$stage/usr/bin/prusa-slicer" ]] ||
    fail "installed Slicer executable is missing"

mkdir -p "$metadata/debian"
cat > "$metadata/debian/control" <<EOF
Source: infiltrator-slicer
Section: graphics
Priority: optional
Maintainer: Infiltrator Projects
Standards-Version: 4.7.0

Package: infiltrator-slicer
Architecture: amd64
Description: Infiltrator Slicer
 Slicer converts 3D models into printer toolpaths and G-code.
EOF

depends=$(
    cd "$metadata"
    dpkg-shlibdeps -O -e"$stage/usr/bin/prusa-slicer" |
        sed -n 's/^shlibs:Depends=//p'
)
[[ -n "$depends" ]] || fail "dpkg-shlibdeps produced no runtime dependency set"

mkdir -p "$stage/DEBIAN"
installed_size=$(du -sk "$stage" | awk '{print $1}')
cat > "$stage/DEBIAN/control" <<EOF
Package: infiltrator-slicer
Version: $version
Section: graphics
Priority: optional
Architecture: amd64
Maintainer: Infiltrator Projects
Homepage: https://github.com/Infiltrator-Projects/Slicer
Depends: $depends
Conflicts: prusa-slicer
Replaces: prusa-slicer
Installed-Size: $installed_size
Description: Infiltrator Slicer
 Slicer converts 3D models into printer toolpaths and G-code.
EOF

rm -f "$artifact"
dpkg-deb --root-owner-group --build "$stage" "$artifact"

test "$(dpkg-deb -f "$artifact" Package)" = infiltrator-slicer
test "$(dpkg-deb -f "$artifact" Version)" = "$version"
test "$(dpkg-deb -f "$artifact" Architecture)" = amd64
dpkg-deb --contents "$artifact" >/dev/null

echo "Linux release artifact:"
echo "  $artifact"
