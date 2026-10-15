///|/ Copyright (c) Prusa Research 2019 Vojtěch Král @vojtechkral
///|/
///|/ PrusaSlicer is released under the terms of the AGPLv3 or higher
///|/

#include "libslic3r/Semver.hpp"
#include "libslic3r_version.h"

namespace Slic3r {

// This value compares printer profile/schema versions, not product releases.
Semver SEMVER { SLIC3R_COMPATIBILITY_VERSION };

}
