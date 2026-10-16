# Configuration presets and updates

Slicer separates application releases from printer and material profile updates. Application packages come from [Slicer releases](https://github.com/Infiltrator-Projects/Slicer/releases/latest) or the [Infiltrator package repository](https://github.com/Infiltrator-Projects/Infiltrator-Repository). Profile compatibility has its own engine-owned version and provider boundaries.

## System and user presets

System presets come from vendor configuration bundles and provide read-only defaults. A user preset can inherit those defaults while recording explicit overrides.

When a parent profile changes, inherited settings can follow the new defaults while user overrides retain their chosen values. Preset loading and migration must preserve this distinction; updating a vendor bundle must not silently discard a user's overrides.

The settings UI distinguishes inherited values, user overrides and unsaved changes. Restoring an inherited value and reverting an unsaved edit are separate operations.

## Configuration snapshots

A snapshot records the configuration state needed for recovery. Snapshot and restore behaviour belongs to the configuration subsystem; the settings UI presents that contract.

Record the affected preset and bundle versions when reproducing an update or restore problem. Verify the recovered settings, inheritance and selected printer/material combination rather than assuming that a successful file operation proves a correct configuration.

## Profile updates

Printer-profile repositories remain optional compatibility integrations. Their update mechanism is separate from application package publication and must preserve the user's choice and configuration recovery boundary.

A profile download is not evidence of printer or firmware compatibility. [Validation](../VALIDATION.md) defines the model, profile, device and observed-result evidence required for such claims.

[Architecture](../ARCHITECTURE.md) defines ownership of configuration and compatibility. [Release engineering](../RELEASE_ENGINE.md) defines application packages and publication.

