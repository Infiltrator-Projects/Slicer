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

[[ -f CMakeLists.txt && -f support/version.inc && -f support/VERSION ]] ||
    fail "run this script from the Slicer repository root"

for tool in realpath awk cmake dpkg dpkg-deb dpkg-shlibdeps du sed pkg-config; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

arch=$(dpkg --print-architecture)
[[ "$arch" == amd64 ]] || fail "release .deb currently targets amd64; runner is $arch"

version=$(tr -d '[:space:]' < support/VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    fail "support/VERSION is not a semantic numeric version"

# Check the app's system HID backend before the long dependency build.
if ! pkg-config --exists hidapi-hidraw && ! pkg-config --exists hidapi-libusb; then
    fail "HIDAPI development files are required; install libhidapi-dev before building."
fi

if [[ -z "$jobs" ]]; then
    if command -v nproc >/dev/null 2>&1; then
        jobs=$(nproc)
    else
        jobs=2
    fi
fi
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive integer"

repo_root=$(pwd -P)
case "$build_root" in
    /*) build_base=$build_root ;;
    *)  build_base="$repo_root/$build_root" ;;
esac
case "$output_dir" in
    /*) output=$output_dir ;;
    *)  output="$repo_root/$output_dir" ;;
esac

build_base=$(realpath -m -- "$build_base")
[[ "$build_base" != / ]] || fail "build root cannot be the filesystem root"
case "$repo_root/" in
    "$build_base/"*) fail "build root cannot contain the source checkout" ;;
esac
owner="$build_base/.slicer-release-owner"
if [[ -f "$owner" ]]; then
    [[ "$(cat "$owner")" == "$repo_root" ]] ||
        fail "build root belongs to another source checkout"
elif [[ -d "$build_base" && -n "$(find "$build_base" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    # Adopt pre-marker caches only when CMake proves this checkout owns them.
    if ! grep -Fxq "CMAKE_HOME_DIRECTORY:INTERNAL=$repo_root" "$build_base/app/CMakeCache.txt" 2>/dev/null &&
       ! grep -Fxq "CMAKE_HOME_DIRECTORY:INTERNAL=$repo_root/support/deps" "$build_base/deps/CMakeCache.txt" 2>/dev/null &&
       ! grep -Fxq "CMAKE_HOME_DIRECTORY:INTERNAL=$repo_root/deps" "$build_base/deps/CMakeCache.txt" 2>/dev/null; then
        fail "nonempty build root has no matching Slicer ownership"
    fi
fi
if ((clean)); then
    rm -rf -- "$build_base"
fi
mkdir -p "$build_base"
printf '%s\n' "$repo_root" > "$owner"


deps_build="$build_base/deps"
deps_prefix="$deps_build/destdir/usr/local"
app_build="$build_base/app"
stage="$build_base/stage"
metadata="$build_base/package-meta"
artifact="$output/slicer_${version}_amd64.deb"

rm -rf "$stage" "$metadata"
mkdir -p "$output"

echo "Building Slicer $version Linux release..."
# Retain dependency objects and installed libraries when moving the same
# checkout's superbuild. Only its generated top-level CMake metadata names the
# old source location; foreign caches remain protected by the owner gate.
if grep -Fxq "CMAKE_HOME_DIRECTORY:INTERNAL=$repo_root/deps" "$deps_build/CMakeCache.txt" 2>/dev/null; then
    rm -f -- "$deps_build/CMakeCache.txt"
    rm -rf -- "$deps_build/CMakeFiles"
fi
cmake -S support/deps -B "$deps_build" \
    -DDEP_WX_GTK3=ON \
    -DDESTDIR="$deps_build/destdir" \
    -DCMAKE_BUILD_TYPE=Release
# The upstream dependency graph contains nested build systems that perform
# their own parallelism. Serialising this outer graph avoids races between
# dependency install steps while retaining internal compiler parallelism.
cmake --build "$deps_build" --parallel 1

cmake -S . -B "$app_build" \
    -DCMAKE_POLICY_DEFAULT_CMP0087=NEW \
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
[[ -x "$stage/usr/bin/slicer" ]] ||
    fail "installed Slicer executable is missing"

mkdir -p "$metadata/debian"
cat > "$metadata/debian/control" <<EOF
Source: slicer
Section: graphics
Priority: optional
Maintainer: Infiltrator Projects
Standards-Version: 4.7.0

Package: slicer
Architecture: amd64
Description: Slicer
 Slicer converts 3D models into printer toolpaths and G-code.
EOF

depends=$(
    cd "$metadata"
    dpkg-shlibdeps -O -e"$stage/usr/bin/slicer" |
        sed -n 's/^shlibs:Depends=//p'
)
[[ -n "$depends" ]] || fail "dpkg-shlibdeps produced no runtime dependency set"

mkdir -p "$stage/DEBIAN"
installed_size=$(du -sk "$stage" | awk '{print $1}')
cat > "$stage/DEBIAN/control" <<EOF
Package: slicer
Version: $version
Section: graphics
Priority: optional
Architecture: amd64
Maintainer: Infiltrator Projects
Homepage: https://github.com/Infiltrator-Projects/Slicer
Depends: $depends
Conflicts: prusa-slicer, infiltrator-slicer
Replaces: prusa-slicer, infiltrator-slicer
Provides: infiltrator-slicer (= $version)
Installed-Size: $installed_size
Description: Slicer
 Slicer converts 3D models into printer toolpaths and G-code.
EOF

rm -f "$artifact"
dpkg-deb --root-owner-group --build "$stage" "$artifact"

test "$(dpkg-deb -f "$artifact" Package)" = slicer
test "$(dpkg-deb -f "$artifact" Version)" = "$version"
test "$(dpkg-deb -f "$artifact" Architecture)" = amd64
dpkg-deb --contents "$artifact" >/dev/null

echo "Linux release artifact:"
echo "  $artifact"
