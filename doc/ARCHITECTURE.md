# Architecture

## Current implementation and provenance

Slicer owns product identity, distribution and subsequent development over the inherited PrusaSlicer 2.9.6 engine. This is an evolving product architecture, not a claim that all engine code was newly written. LICENSE-AGPL-3.0.txt and source notices retain the applicable legal attribution.

## Dependency direction

- `src/libslic3r` owns geometry, model, configuration, slicing and G-code generation.
- `src/slic3r/GUI` owns the wxWidgets desktop, model editing, settings presentation and interaction.
- CLI entry points invoke the same engine contracts; the GUI must not become the sole authority for slicing policy.
- `resources` owns shipped product assets and profiles. Profile/schema compatibility remains distinct from the product release number.
- Printer hosts and external service integrations are adapters with provider-specific contracts.
- `deps`, including pinned vendor archives, owns third-party build inputs. `support` owns current Infiltrator build, package and installer mechanics.

Do not move engine policy into packaging or provider transport code. Geometry/model lifetime and thread/cancellation ownership remain engine/application concerns, rather than installer responsibilities.

## Identity

`support/VERSION` owns the product version. CMake reads it through `version.inc`; shell, Python and PowerShell release helpers read that same immutable source file. CMake derives build IDs and Windows resource versions. The inherited profile compatibility version remains a separate explicit value.

## Qualification and publication

`Verify` owns compilation and qualification for the portable DEB, Windows EXE and aggressive native source installer. It preserves source identity and hashes. `Publish release` consumes those artifacts and compares remote bytes without rebuilding. Detailed recovery contracts belong to [Release engineering](RELEASE_ENGINE.md).

The native installer embeds exact Git source and vendor archives, verifies its payload before extraction, and uses the product-owned native driver. Machine-specific optimisation belongs to local compilation, while the generic DEB retains portable CPU assumptions.

## Maintained and historical documentation

This file, [Validation](VALIDATION.md), the root philosophy and release engineering are maintained product contracts. Older platform build notes and localisation/dependency documents describe inherited implementation details and must be interpreted within current support boundaries.
