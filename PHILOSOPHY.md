# Engineering philosophy

Slicer applies the Infiltrator Projects standard: the best or nothing. That means coherent ownership, explicit lifetime and failure semantics, justified mechanisms and complete qualification of the claims being shipped.

[The shared engineering philosophy](https://github.com/Infiltrator-Projects/Infiltrator-Libraries/blob/main/docs/PHILOSOPHY.md) is the family baseline. Slicer's architecture and validation documents specialise it for this product.

## Product and provenance

Slicer is developed from the PrusaSlicer 2.9.6 codebase. Existing slicing, profile and file-format behaviour has substantial inherited compatibility obligations. Product-owned changes must preserve accurate source attribution and licensing. A planned rewrite is not evidence that inherited implementation has already been replaced.

## Ownership and complexity

The slicing engine owns geometry, model transformation, toolpath and G-code semantics. The desktop shell presents those contracts. Platform adapters, packaging and deployment must not redefine slicing behaviour. Printer and service integrations remain explicit compatibility boundaries.

Keep one authority per concern. Share a mechanism only when its contract is at least as strong as the product requires. Remove redundant build and release paths rather than adding compensating switches. Prefer small explicit interfaces over hidden ambient state or assumptions about another repository's latest branch.

## Evidence and documentation

Automated geometry tests, application smoke tests, installer qualification and physical printer validation establish different claims. Unsupported or unverified behaviour must remain explicit.

Maintained documentation records current ownership, invariants, reasoning, failure/recovery and compatibility. Historical upstream build notes remain provenance; they do not override current release engineering. Comments must explain the non-obvious contract at a precise postgraduate engineering standard.

Public release tags and bytes are immutable. Qualification produces artifacts; publication promotes those exact bytes. Product version and upstream compatibility version have distinct owners and must not be conflated.
