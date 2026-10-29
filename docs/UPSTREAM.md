# Upstream maintenance

## Recorded baseline

The inherited engine and desktop implementation come from PrusaSlicer. This
repository imported its source snapshot at
`e115a02470477c35e735c7429d66c0cedbd2c885` (the initial Slicer commit).
That commit identifies the local import; its message does not record the exact
upstream commit or tag. The `2.9.6` value in `support/version.inc` is the inherited
printer-profile/schema compatibility version and does not establish that revision.

Before a broad upstream update, establish the upstream revision by comparing the
initial imported source with the authoritative
[PrusaSlicer repository](https://github.com/prusa3d/PrusaSlicer). Record the full
verified upstream commit, source URL, and any differences already present in the
import here. Preserve the local import commit as the comparison anchor. Do not
substitute a matching version label for source equivalence.

## Importing fixes

Review upstream releases and relevant correctness, file-format, printer-profile,
and security fixes. Assess each candidate against Slicer's engine, UI, persistence,
and distribution contracts before importing it.

For each selected change:

1. Record the upstream commit URL and the concrete defect or compatibility change
   in the change description. Explain any adaptation to Slicer's layout or behaviour.
2. Port a focused change with its relevant regression coverage. Preserve applicable
   copyright notices and licence texts. Keep product identity, release machinery,
   and optional provider integrations under their existing owners.
3. Validate the affected engine or UI contract using representative model and
   profile fixtures, and run the relevant existing suites. Record changed output
   and compatibility assumptions; a passing build alone does not establish them.
4. Qualify releases from the exact resulting source and artifact bytes using
   [Validation](VALIDATION.md). Keep physical-printer evidence distinct from software
   tests, and preserve published tags and assets.

Update this record when the verified upstream baseline changes. Product release
numbers remain owned by `support/VERSION`; change profile/schema compatibility
only when the implemented compatibility contract requires it.
