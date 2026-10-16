<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Engineering Philosophy

This repository follows the canonical [Infiltrator Engineering Philosophy](https://github.com/Infiltrator-Projects/Libraries/blob/main/docs/PHILOSOPHY.md).

The standard is Mercedes-Benz engineering excellence as an execution benchmark, not a branding claim or affiliation: technical depth, quality, reliability, trust, effortless operation, disciplined reduction, elegance and craftsmanship. The strongest justified solution wins regardless of age or fashion; complexity must earn its place; and simplicity must come from complete engineering rather than removed capability.

Substantive code commentary and maintained technical documentation are held to a postgraduate / university master's-level engineering standard: precise, complete, current and focused on invariants, ownership, reasoning, failure/recovery, compatibility and other non-obvious contracts rather than narration of obvious syntax.

Repository-specific design, architecture, safety and validation documents may strengthen or specialise this standard, but must not silently weaken or contradict it.

## Slicer contracts

The slicing engine owns geometry, model transformation, toolpath and G-code semantics. The desktop application presents those contracts. Platform adapters, packaging and deployment must not redefine slicing behaviour. Printer and service integrations remain explicit compatibility boundaries.

Keep one authority per concern. Product versions, profile compatibility, build inputs and publication each have an explicit owner. Qualification produces artifacts; publication promotes those exact bytes. Published release tags and assets remain immutable.

Geometry tests, application smoke tests, installer qualification and physical printer validation establish different claims. Record unsupported or unverified behaviour explicitly. [Architecture](ARCHITECTURE.md) and [Validation](VALIDATION.md) specialise the shared standard for this product.

