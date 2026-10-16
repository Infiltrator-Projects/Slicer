<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Security

Security fixes target current `main` and, where appropriate, the latest published release. Older releases should not be assumed to receive backports.

## Reporting

Do not open a public issue for vulnerabilities that could expose users, local data, private models, printer or service credentials, package integrity or release infrastructure.

Use GitHub private vulnerability reporting when available. Otherwise contact `infiltratr@yandex.com` with the subject `Slicer security report`.

Include the affected version or commit, environment, privilege level, subsystem, impact and reliable reproduction. Remove unrelated private information.

## Boundaries

Models, archives, profiles, project files, G-code, network responses and printer or service endpoints are untrusted input. Parsing, extraction, geometry processing and external process invocation must preserve memory, path and execution boundaries.

Printer and service integrations have explicit network and credential boundaries. Do not expose secrets in logs, exports or error reports. An unavailable device or an unverified printer result must not be presented as a verified success.

The native build driver stages installation files without installing into the running system. The native installer requests administrative access only for explicitly selected prerequisite installation and final package installation, as documented in [Release engineering](doc/RELEASE_ENGINE.md).

Security-sensitive code includes external-input parsing, archive extraction, geometry processing, network and credential handling, durable writes and exports, native library interaction, package and release integrity, and memory safety. Fix defects at the underlying boundary and add regression coverage where practical.
