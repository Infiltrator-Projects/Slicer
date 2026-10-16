# Architecture

## Current implementation and provenance

Slicer owns product identity, distribution and current development of the desktop application and slicing engine. Existing model, preset and file-format compatibility remains part of the implementation contract. [Engineering philosophy](PHILOSOPHY.md) governs design and documentation; the project licence is in [LICENSE](../LICENSE).

## Dependency direction

- `src/libslic3r` owns geometry, model, configuration, slicing and G-code generation.
- `src/slic3r/GUI` owns the wxWidgets desktop, model editing, settings presentation and interaction.
- CLI entry points invoke the same engine contracts; the GUI must not become the sole authority for slicing policy.
- `support/resources` owns shipped product assets and profiles. Profile/schema compatibility remains distinct from the product release number.
- Printer hosts and external service integrations are adapters with provider-specific contracts.
- `support/deps`, including pinned vendor archives, owns third-party build inputs. `support` owns current Infiltrator build, package and installer mechanics.

Do not move engine policy into packaging or provider transport code. Geometry/model lifetime and thread/cancellation ownership remain engine/application concerns, rather than installer responsibilities.

## Identity

`support/VERSION` owns the product version. CMake reads it through `support/version.inc`; shell, Python and PowerShell release helpers read that same immutable source file. CMake derives build IDs and Windows resource versions. The inherited profile compatibility version remains a separate explicit value.

## Qualification and publication

`Verify` owns compilation and qualification for the portable DEB, Windows EXE and aggressive native source installer. It preserves source identity and hashes. `Publish release` consumes those artifacts and compares remote bytes without rebuilding. Detailed recovery contracts belong to [Release engineering](RELEASE_ENGINE.md).

The native installer downloads the exact release commit over HTTPS, including its pinned vendor archives, and uses the product-owned native driver. The downloaded dependency archives are checked against the release manifest before compilation; no source archive is embedded in the `.run`. Machine-specific optimisation belongs to local compilation, while the generic DEB retains portable CPU assumptions.

## Maintained and historical documentation

This file, [Validation](VALIDATION.md), the philosophy document and release engineering are maintained product contracts. Older platform build notes and localisation/dependency documents describe inherited implementation details and must be interpreted within current support boundaries.
