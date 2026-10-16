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
install_prefix=/usr/local
stage_dir=
print_config=0
install_prefix_set=0

usage() {
    cat <<'EOF'
Usage: support/build-native.sh [options]

Options:
  --profile native|aggressive  Optimisation profile (default: native)
  --compiler PATH              C++ compiler (default: $CXX or g++)
  --jobs NUMBER                Parallel build jobs (default: CPU and memory limit)
  --build-root PATH            Build root (default: build/native)
  --install-prefix PATH        Installed prefix (default: /usr/local; /usr when staging)
  --stage-dir PATH             Stage installation under PATH after build/tests
  --clean                      Remove the selected build root first
  --skip-tests                 Do not run the test suite
  --print-config               Probe and print settings without building
  -h, --help                   Show this help

Profiles:
  native       -O2 plus compiler-probed native CPU tuning.
  aggressive   -O3 plus native CPU tuning and two-pass GCC PGO.

The resulting application is left under:
  <build-root>/app/src/

--stage-dir creates a filesystem installation tree; this script never installs
into the running system. Reuse a build root only with matching build settings,
or pass --clean to rebuild it with different settings.
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
        --install-prefix)
            (($# >= 2)) || fail "--install-prefix requires a value"
            install_prefix=$2
            install_prefix_set=1
            shift 2
            ;;
        --stage-dir)
            (($# >= 2)) || fail "--stage-dir requires a value"
            stage_dir=$2
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
        --print-config)
            print_config=1
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

[[ -f CMakeLists.txt && -f support/version.inc && -d support/deps ]] ||
    fail "run this script from the Slicer repository root"

for tool in cmake python3 realpath sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
command -v "$cxx" >/dev/null 2>&1 || fail "C++ compiler not found: $cxx"

compiler_path=$(command -v "$cxx")
compiler_name=$(basename "$compiler_path")

case "$compiler_name" in
    *clang++*)
        cc_candidate=${compiler_path%clang++*}clang${compiler_name##*clang++}
        ;;
    *g++*)
        cc_candidate=${compiler_path%g++*}gcc${compiler_name##*g++}
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
    if [[ -r /proc/meminfo ]]; then
        memory_jobs=$(awk '/^MemAvailable:/ {n=int($2/3145728); print (n > 0 ? n : 1)}' /proc/meminfo)
        if [[ "$memory_jobs" =~ ^[1-9][0-9]*$ ]] && ((memory_jobs < jobs)); then
            jobs=$memory_jobs
        fi
    fi
fi
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive integer"

repo_root=$(pwd -P)
[[ -n "$build_root" ]] || fail "--build-root must not be empty"
build_root=$(realpath -m -- "$build_root")
[[ "$build_root" != / && "$build_root" != "$repo_root" && "$repo_root" != "$build_root/"* ]] ||
    fail "--build-root must not be the repository root or one of its parents"
[[ "$install_prefix" == /* && "$install_prefix" != / ]] ||
    fail "--install-prefix must be an absolute directory other than /"
install_prefix=$(realpath -m -- "$install_prefix")
[[ "$install_prefix" != / ]] || fail "--install-prefix must not resolve to /"
if [[ -n "$stage_dir" ]]; then
    stage_dir=$(realpath -m -- "$stage_dir")
    [[ "$stage_dir" != / && "$stage_dir" != "$repo_root" && "$repo_root" != "$stage_dir/"* ]] ||
        fail "--stage-dir must not be the repository root or one of its parents"
    [[ "$build_root" != "$stage_dir" && "$build_root" != "$stage_dir/"* ]] ||
        fail "--stage-dir must not contain the build root"
    if ((!install_prefix_set)); then
        install_prefix=/usr
    fi
fi

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
    compiler_macros=$("$compiler_path" -dM -E -x c++ /dev/null)
    [[ "$compiler_macros" == *'define __GNUC__ '* && "$compiler_macros" != *'define __clang__ '* ]] ||
        fail "aggressive PGO currently requires GCC/g++; use --compiler g++"
    probe_cxx_flags -fprofile-generate="$probe_dir/pgo-probe" -fprofile-update=atomic ||
        fail "compiler does not support the required PGO generation flags"
fi

common_flags=("$optimisation" -pipe -DNDEBUG "${native_flags[@]}")
printf -v common_flags_text '%q ' "${common_flags[@]}"
common_flags_text=${common_flags_text% }

deps_build="$build_root/deps"
deps_prefix="$deps_build/destdir/usr/local"
app_build="$build_root/app"
fhs=OFF
if [[ -n "$stage_dir" ]] || ((install_prefix_set)); then
    fhs=ON
fi

# CMake 4 removed compatibility with the old policy levels used by several
# bundled projects. External projects already set this in AddCMakeProject.cmake;
# the application needs the same setting for its add_subdirectory projects.
policy_args=(-DCMAKE_POLICY_DEFAULT_CMP0087=NEW)
cmake_version=$(cmake --version)
if [[ "$cmake_version" =~ cmake\ version\ ([0-9]+)\. ]] && ((BASH_REMATCH[1] >= 4)); then
    policy_args+=(-DCMAKE_POLICY_VERSION_MINIMUM=3.5)
fi

echo "Slicer native build"
echo "  Profile:      $profile"
echo "  C compiler:   $cc"
echo "  C++ compiler: $compiler_path"
echo "  CPU:          $machine"
echo "  Jobs:         $jobs"
echo "  Flags:        $common_flags_text"
echo "  Build root:   $build_root"
echo "  Prefix:       $install_prefix"
echo "  FHS layout:   $fhs"
echo "  Stage:        ${stage_dir:-none}"
echo "  Tests:        $((1 - skip_tests))"

if ((print_config)); then
    exit 0
fi

# Compare effective compiler/profile/install settings before touching an old
# cache. In particular, PGO and non-PGO objects must never be mixed silently.
configuration=$(printf '%s\n' \
    'native-build-format=2' \
    "profile=$profile" \
    "cpu=$machine" \
    "cpu-tuning=$(awk '/^(model name|flags|Features|CPU part)[[:space:]]*:/ {print}' /proc/cpuinfo | sort -u | sha256sum)" \
    "cc=$(realpath -- "$cc")" \
    "cxx=$(realpath -- "$compiler_path")" \
    "cc-version=$("$cc" --version)" \
    "cxx-version=$("$compiler_path" --version)" \
    "flags=$common_flags_text" \
    "prefix=$install_prefix" \
    "fhs=$fhs" \
    "cmake=$cmake_version" \
    "version=$(sha256sum support/version.inc support/VERSION)" \
    "vendor=$(sha256sum support/deps/vendor/manifest.cmake)")
if ((clean)); then
    rm -rf -- "$build_root"
elif [[ -f "$build_root/.slicer-native-config" ]]; then
    [[ "$(cat "$build_root/.slicer-native-config")" == "$configuration" ]] ||
        fail "build settings changed in $build_root; use --clean or a different --build-root"
elif [[ -d "$deps_build" || -d "$app_build" ]]; then
    fail "unidentified existing build cache in $build_root; use --clean or a different --build-root"
fi

python3 support/verify-vendor.py
mkdir -p "$build_root"
printf '%s\n' "$configuration" > "$build_root/.slicer-native-config"

# Custom Autotools dependency recipes run at build time, so keep the chosen
# toolchain in the environment as well as forwarding it through CMake.
export CC="$cc" CXX="$compiler_path"
export CFLAGS="$common_flags_text" CXXFLAGS="$common_flags_text" LDFLAGS=

echo
echo "Building or refreshing static dependency bundle..."
cmake -S support/deps -B "$deps_build" \
    "${policy_args[@]}" \
    -DDEP_WX_GTK3=ON \
    -DDEP_MAX_THREADS="$jobs" \
    -DDESTDIR="$deps_build/destdir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$cc" \
    -DCMAKE_CXX_COMPILER="$compiler_path" \
    -DCMAKE_C_FLAGS= \
    -DCMAKE_CXX_FLAGS= \
    -DCMAKE_C_FLAGS_RELEASE="$common_flags_text" \
    -DCMAKE_CXX_FLAGS_RELEASE="$common_flags_text"
# Upstream explicitly recommends serialising the top-level dependency graph;
# individual external projects retain their own parallel build behaviour.
cmake --build "$deps_build" --parallel 1

configure_app() {
    local cflags=$1
    local cxxflags=$2
    local ldflags=${3:-}
    cmake -S . -B "$app_build" \
        "${policy_args[@]}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$install_prefix" \
        -DCMAKE_C_COMPILER="$cc" \
        -DCMAKE_CXX_COMPILER="$compiler_path" \
        -DCMAKE_C_FLAGS= \
        -DCMAKE_CXX_FLAGS= \
        -DCMAKE_C_FLAGS_RELEASE="$cflags" \
        -DCMAKE_CXX_FLAGS_RELEASE="$cxxflags" \
        -DCMAKE_EXE_LINKER_FLAGS_RELEASE="$ldflags" \
        -DCMAKE_SHARED_LINKER_FLAGS_RELEASE="$ldflags" \
        -DSLIC3R_STATIC=ON \
        -DSLIC3R_GTK=3 \
        -DSLIC3R_FHS="$fhs" \
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

    # Quote the option value for CMake's generated compiler command lines.
    # Bash's %q uses $'...' for some paths, which /bin/sh does not interpret.
    pgo_option_path=${pgo_dir//\\/\\\\}
    pgo_option_path=${pgo_option_path//\"/\\\"}
    pgo_option_path=${pgo_option_path//\$/\\\$}
    pgo_option_path=${pgo_option_path//\`/\\\`}
    pgo_generate="-fprofile-generate=\"$pgo_option_path\""
    pgo_use="-fprofile-use=\"$pgo_option_path\""
    generate_flags="$common_flags_text $pgo_generate -fprofile-update=atomic"
    echo
    echo "Building instrumented aggressive binary..."
    configure_app "$generate_flags" "$generate_flags" "$pgo_generate"
    cmake --build "$app_build" --parallel "$jobs"

    echo
    echo "Training PGO profile on this machine..."
    run_tests
    slicer_binary="$app_build/src/prusa-slicer"
    [[ -x "$slicer_binary" ]] || fail "instrumented Slicer executable was not produced"
    "$slicer_binary" --help >/dev/null
    "$slicer_binary" --info support/tests/data/20mm_cube.obj >/dev/null
    "$slicer_binary" --load support/tests/data/default_fff.ini --export-gcode \
        --output "$pgo_dir/training-cube.gcode" support/tests/data/20mm_cube.obj
    [[ -s "$pgo_dir/training-cube.gcode" ]] || fail "PGO slicing training produced no G-code"

    find "$pgo_dir" -type f \( -name '*.gcda' -o -name '*.gcov' \) -print -quit |
        grep -q . || fail "PGO training produced no profile data"

    use_flags="$common_flags_text $pgo_use -fprofile-correction -fprofile-partial-training -Wno-missing-profile"
    echo
    echo "Rebuilding aggressive binary using measured PGO profile..."
    cmake --build "$app_build" --target clean
    configure_app "$use_flags" "$use_flags" "$pgo_use -fprofile-correction"
    cmake --build "$app_build" --parallel "$jobs"
    run_tests
else
    echo
    echo "Building native binary..."
    configure_app "$common_flags_text" "$common_flags_text"
    cmake --build "$app_build" --parallel "$jobs"
    run_tests
fi

if [[ -n "$stage_dir" ]]; then
    rm -rf -- "$stage_dir"
    mkdir -p "$stage_dir"
    DESTDIR="$stage_dir" cmake --install "$app_build"
    [[ -x "$stage_dir$install_prefix/bin/slicer" ]] ||
        fail "staged Slicer executable is missing"
    echo "Staged installation: $stage_dir$install_prefix"
fi

echo
echo "Native build complete:"
echo "  $app_build/src/prusa-slicer"
