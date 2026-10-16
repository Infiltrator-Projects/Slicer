<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Contributing to Slicer

Slicer follows the Infiltrator Projects engineering and documentation standard in [Engineering philosophy](../docs/PHILOSOPHY.md).

Follow the durable contracts in [Architecture](../docs/ARCHITECTURE.md). Behavioural changes should update the owning tests; update documentation only when a documented contract changes.

`cmake -P support/verify-product.cmake` checks the product contracts. [Validation](../docs/VALIDATION.md) defines the complete fast source checks and required release evidence. Use `support/build-native.sh --profile native` for a Linux build with application tests, and `support/windows/build-release.ps1` for Windows packaging. The `Verify` workflow is the authoritative release qualification.

Dependency preparation is explicit: use the pinned inputs under `deps` and the [vendored dependency inventory](../support/deps/vendor/README.md). `python3 support/verify-vendor.py` verifies the bundled archive inventory and hashes.

Normal development stays on `main`. Keep changes focused, preserve the compiler and verification policies, and distinguish tested model, profile and printer behaviour from unverified assumptions. Published release tags and artifact bytes remain immutable.

Comments should explain non-obvious invariants, ownership, concurrency, units, ABI quirks and security boundaries rather than narrating straightforward code.
