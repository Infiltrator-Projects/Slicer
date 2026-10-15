#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Hardware-native Slicer build driver.
#
# "native" keeps the release optimisation level while specialising generated
# code for the machine that performs the build. "aggressive" deliberately goes
# further: it uses -O3 and a measured two-pass GCC PGO cycle. The script probes
# CPU flags before using them instead of assuming that a compiler accepts them.

set -euo pipefail

profile=native
jobs=
cxx=${CXX:-g++}
cc=${CC:-gcc}
clean=0
skip_tests=0
build_root=${SLICER_NATIVE_BUILD_ROOT:-build/native}

usage() {
    cat <<'EOF'
Usage: support/build-native.sh [options]

Options:
  --profile native|aggressive  Optimisation profile (default: native)
  --compiler PATH              C++ compiler (default: $CXX or g++)
  --jobs NUMBER                Parallel build jobs (default: online CPUs)
  --build-root PATH            Build root (default: build/native)
  --clean                      Remove the selected build root first
  --skip-tests                 Do not run the test suite
  -h, --help                   Show this help

Profiles:
  native       -O2 plus compiler-probed native CPU tuning.
  aggressive   -O3 plus native CPU tuning and two-pass GCC PGO.

The resulting application is left under:
  <build-root>/app/src/
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --profile)
            (($# >= 2)) || fail "--profile requires a value"
            profile=$2
            shift 2
            ;;
        --compiler)
            (($# >= 2)) || fail "--compiler requires a value"
            cxx=$2
            shift 2
            ;;
        --jobs)
            (($# >= 2)) || fail "--jobs requires a value"
            jobs=$2
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
        --skip-tests)
            skip_tests=1
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

[[ "$profile" == native || "$profile" == aggressive ]] ||
    fail "profile must be native or aggressive"

[[ -f CMakeLists.txt && -f version.inc && -d deps ]] ||
    fail "run this script from the Slicer repository root"

command -v cmake >/dev/null 2>&1 || fail "cmake is required"
command -v "$cxx" >/dev/null 2>&1 || fail "C++ compiler not found: $cxx"

compiler_path=$(command -v "$cxx")
compiler_name=$(basename "$compiler_path")

case "$compiler_name" in
    g++*|gcc*)
        if [[ "$compiler_name" == g++* ]]; then
            cc_candidate=${compiler_path%g++*}gcc${compiler_name#g++}
        else
            cc_candidate=$compiler_path
        fi
        ;;
    clang++*)
        cc_candidate=${compiler_path%clang++*}clang${compiler_name#clang++}
        ;;
    *)
        cc_candidate=$cc
        ;;
esac

if command -v "$cc_candidate" >/dev/null 2>&1; then
    cc=$(command -v "$cc_candidate")
elif command -v "$cc" >/dev/null 2>&1; then
    cc=$(command -v "$cc")
else
    fail "matching C compiler not found"
fi

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

mkdir -p "$build_root"
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/slicer-native-probe.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
printf 'int main(){return 0;}\n' > "$probe_dir/probe.cpp"

probe_cxx_flags() {
    "$compiler_path" -std=c++17 "$@" "$probe_dir/probe.cpp" -o "$probe_dir/probe" \
        >/dev/null 2>&1
}

native_flags=()
machine=$(uname -m)
case "$machine" in
    x86_64|amd64|i?86)
        probe_cxx_flags -march=native && native_flags+=(-march=native)
        probe_cxx_flags -mtune=native && native_flags+=(-mtune=native)
        ;;
    *)
        probe_cxx_flags -mcpu=native && native_flags+=(-mcpu=native)
        ;;
esac

((${#native_flags[@]})) ||
    fail "compiler accepted no hardware-native CPU tuning flag"

optimisation=-O2
if [[ "$profile" == aggressive ]]; then
    optimisation=-O3
    case "$compiler_name" in
        g++*|gcc*) ;;
        *)
            fail "aggressive PGO currently requires GCC/g++; use --compiler g++"
            ;;
    esac
    probe_cxx_flags -fprofile-generate="$probe_dir/pgo-probe" -fprofile-update=atomic ||
        fail "compiler does not support the required PGO generation flags"
fi

common_flags=("$optimisation" -pipe -DNDEBUG "${native_flags[@]}")
printf -v common_flags_text '%q ' "${common_flags[@]}"
common_flags_text=${common_flags_text% }

repo_root=$(pwd -P)
case "$build_root" in
    /*) ;;
    *) build_root="$repo_root/$build_root" ;;
esac

deps_build="$build_root/deps"
deps_prefix="$deps_build/destdir/usr/local"
app_build="$build_root/app"

echo "Slicer native build"
echo "  Profile:      $profile"
echo "  C compiler:   $cc"
echo "  C++ compiler: $compiler_path"
echo "  CPU:          $machine"
echo "  Jobs:         $jobs"
echo "  Flags:        $common_flags_text"

echo
echo "Building or refreshing static dependency bundle..."
cmake -S deps -B "$deps_build" \
    -DDEP_WX_GTK3=ON \
    -DDESTDIR="$deps_build/destdir" \
    -DCMAKE_BUILD_TYPE=Release
# Upstream explicitly recommends serialising the top-level dependency graph;
# individual external projects retain their own parallel build behaviour.
cmake --build "$deps_build" --parallel 1

configure_app() {
    local cflags=$1
    local cxxflags=$2
    local ldflags=${3:-}
    cmake -S . -B "$app_build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER="$cc" \
        -DCMAKE_CXX_COMPILER="$compiler_path" \
        -DCMAKE_C_FLAGS_RELEASE="$cflags" \
        -DCMAKE_CXX_FLAGS_RELEASE="$cxxflags" \
        -DCMAKE_EXE_LINKER_FLAGS_RELEASE="$ldflags" \
        -DCMAKE_SHARED_LINKER_FLAGS_RELEASE="$ldflags" \
        -DSLIC3R_STATIC=ON \
        -DSLIC3R_GTK=3 \
        -DSLIC3R_PCH=OFF \
        -DSLIC3R_BUILD_TESTS=ON \
        -DCMAKE_PREFIX_PATH="$deps_prefix"
}

run_tests() {
    if ((skip_tests)); then
        return
    fi
    if command -v xvfb-run >/dev/null 2>&1; then
        xvfb-run -a ctest --test-dir "$app_build" --output-on-failure --parallel "$jobs"
    else
        ctest --test-dir "$app_build" --output-on-failure --parallel "$jobs"
    fi
}

if [[ "$profile" == aggressive ]]; then
    pgo_dir="$build_root/pgo"
    rm -rf "$pgo_dir"
    mkdir -p "$pgo_dir"

    generate_flags="$common_flags_text -fprofile-generate=$pgo_dir -fprofile-update=atomic"
    echo
    echo "Building instrumented aggressive binary..."
    configure_app "$generate_flags" "$generate_flags" "-fprofile-generate=$pgo_dir"
    cmake --build "$app_build" --parallel "$jobs"

    echo
    echo "Training PGO profile on this machine..."
    run_tests
    slicer_binary="$app_build/src/prusa-slicer"
    [[ -x "$slicer_binary" ]] || fail "instrumented Slicer executable was not produced"
    "$slicer_binary" --help >/dev/null
    "$slicer_binary" --info tests/data/20mm_cube.obj >/dev/null

    find "$pgo_dir" -type f \( -name '*.gcda' -o -name '*.gcov' \) -print -quit |
        grep -q . || fail "PGO training produced no profile data"

    use_flags="$common_flags_text -fprofile-use=$pgo_dir -fprofile-correction -fprofile-partial-training -Wno-missing-profile"
    echo
    echo "Rebuilding aggressive binary using measured PGO profile..."
    cmake --build "$app_build" --target clean
    configure_app "$use_flags" "$use_flags" "-fprofile-use=$pgo_dir -fprofile-correction"
    cmake --build "$app_build" --parallel "$jobs"
    run_tests
else
    echo
    echo "Building native binary..."
    configure_app "$common_flags_text" "$common_flags_text"
    cmake --build "$app_build" --parallel "$jobs"
    run_tests
fi

echo
echo "Native build complete:"
echo "  $app_build/src/prusa-slicer"
