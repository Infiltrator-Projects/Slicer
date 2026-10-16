# SLA time-estimate development tool

This directory contains a standalone development application for the SLA time-estimate library. It is separate from Slicer's release-qualified desktop packages.

## Build

From the repository root, prepare the pinned JSON dependency and configure the standalone target:

```sh
cmake -S deps -B build/sla-deps -DCMAKE_BUILD_TYPE=Release
cmake --build build/sla-deps --target dep_json
cmake -S src/sla-time-estimates -B build/sla-time-estimates \
  -DCMAKE_PREFIX_PATH="$PWD/build/sla-deps/destdir/usr/local"
cmake --build build/sla-time-estimates
```

The executable target is `sla_time_estimate_app`. Its local [CMakeLists.txt](CMakeLists.txt) owns the C++17 and `nlohmann_json` dependency contract.

## Evidence

A standalone tool run does not qualify the desktop application or establish physical printer timing. Record the input, source revision and observed estimate when using it for development. Follow the repository's [validation boundaries](../../docs/VALIDATION.md).

