# Linux release staging and recovery

`build-deb.sh` builds the portable amd64 release, runs all native test suites,
stages the application and creates the Debian package. Application configuration
sets `CMAKE_POLICY_DEFAULT_CMP0087=NEW` because the inherited root CMake minimum
is 3.13 and the launcher install rules contain target generator expressions.
Without that policy the installed links contain a literal expression instead of
`prusa-slicer`. `verify-staging.py` reproduces the legacy failure and verifies the
production configuration using the actual root minimum and install rules.

CI retains the `build/` directory between runs, cleans untracked source outside
that directory, configures again for the exact checkout, and reruns compilation,
all tests and package qualification. A retained object is a compiler cache;
previous test success does not replace the current checks.

Use recovery only while the original workspace is idle and no other Verify run is active. Do not dispatch a separate Verify run during recovery. Maintainers may temporarily set:

- `SLICER_LINUX_REUSE_WORKSPACE`: an existing workspace on the same BigBedroom
  host whose CMake application cache records that exact source directory. CI
  verifies its repository, checks out the current source commit, cleans source
  outside `build/`, reruns the release driver and qualifies the produced DEB.
- `SLICER_REUSE_WINDOWS_RUN`: the original completed main-branch Verify run.
  CI requires successful source and Windows jobs, a complete ancestor comparison,
  and changes restricted to `support/linux/` and workflow files, including rename
  origins. It downloads the original Windows candidate, installs and qualifies
  those exact bytes again, and uploads them into the current qualification run.
  Any Windows product, resource, dependency or build-helper change rejects reuse.

Clear both variables after recovery. Normal runs build Windows using its pinned
hosted toolchain and dependency cache. Release publication continues to require
successful source, Linux and Windows qualification jobs from one current run.
