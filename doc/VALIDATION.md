# Validation

## Entry points

[Release engineering](RELEASE_ENGINE.md) defines current build commands, qualified assets and recovery. The inherited platform build notes do not expand the set of release-qualified platforms.

Fast source checks used by CI include:

```sh
cmake -P support/verify-product.cmake
python3 support/verify-vendor.py
python3 support/linux/verify-staging.py
python3 support/linux/verify-build-root.py
python3 support/native/verify-installer.py
python3 support/native/verify-driver.py
```

Installer fixtures use disposable repositories and paths. They exercise production extraction/driver behaviour, including spaces and corrupt payload rejection.

## Required release evidence

The exact candidate must pass source/product contracts, Linux application tests and package qualification, Windows build and installer qualification, and execution of the generated native installer in aggressive mode. The native workload includes engine tests, model parsing and G-code slicing before a final rebuild using the measured profile. CI stages that installation without installing it onto the persistent runner.

All three candidates are sealed with source commit, version and SHA-256. Publication verifies Debian identity, native installer identity, Windows PE structure and exact remote bytes before and after promotion. PE structure validation does not claim code signing.

## Scope and remaining environment evidence

Geometry tests and G-code fixtures validate deterministic engine behaviour. They do not establish physical print quality, printer firmware compatibility, device/network reliability, visual quality or usability on untested hardware. Record model/profile identity, source SHA, operating system, device/firmware and observed outcome with manual evidence.

macOS build notes remain inherited developer material; macOS is outside the current three-asset release contract. Printer/service adapters retain their own compatibility and credential boundaries.

## Regression discipline

Capture reproducible engine, UI, persistence or installer defects at the narrowest owning boundary. Keep Release checks executable; assert-based diagnostics are meaningful only where the test harness keeps them enabled. Never infer qualification from a job that skipped the relevant runtime.

Release-script fixtures also reject a source checkout or unrelated nonempty directory as a cleanup target, accept an owned empty build root, verify safe reuse/cleanup, and adopt legacy caches only when CMake identifies the same source owner. The compiler is stubbed after preflight; all deletion targets belong to the disposable fixture.
