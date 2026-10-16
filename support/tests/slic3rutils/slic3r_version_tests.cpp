#include <catch2/catch_test_macros.hpp>

#include "slic3r/Config/Version.hpp"
#include "libslic3r/libslic3r.h"

TEST_CASE("Product version preserves printer profile compatibility", "[Version]") {
    using namespace Slic3r;
    GUI::Config::Version profile;
    profile.min_slic3r_version = *Semver::parse("2.9.4-rc0");
    profile.max_slic3r_version = Semver::inf();
    REQUIRE(profile.is_current_slic3r_supported());
    REQUIRE_FALSE(profile.is_current_slic3r_downgrade());
    REQUIRE_FALSE(profile.is_slic3r_supported(*Semver::parse(SLIC3R_VERSION)));
    REQUIRE(SEMVER == *Semver::parse(SLIC3R_COMPATIBILITY_VERSION));
}


TEST_CASE("Check parsing and comparing of config versions", "[Version]") {
    using namespace Slic3r;

    GUI::Config::Version v;

    v.config_version     = *Semver::parse("1.1.2");
    v.min_slic3r_version = *Semver::parse("1.38.0");
    v.max_slic3r_version = Semver::inf();
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.38.0")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.38.0-alpha")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.37.0-alpha")));

    // Test the prerelease status.
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-rc2")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0")));

    v.config_version      = *Semver::parse("1.1.2-alpha");
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha1")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-beta")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-rc2")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0")));

    v.config_version      = *Semver::parse("1.1.2-alpha1");
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha1")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-beta")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-rc2")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0")));

    v.config_version      = *Semver::parse("1.1.2-beta");
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-rc")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0-rc2")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0")));

    v.config_version      = *Semver::parse("1.1.2-rc");
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-rc")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-rc2")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0")));

    v.config_version      = *Semver::parse("1.1.2-rc2");
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-alpha1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-beta1")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-rc")));
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.39.0-rc2")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.39.0")));

    // Test the upper boundary.
    v.config_version     = *Semver::parse("1.1.2");
    v.max_slic3r_version = *Semver::parse("1.39.3-beta1");
    REQUIRE(v.is_slic3r_supported(*Semver::parse("1.38.0")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.38.0-alpha")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.38.0-alpha1")));
    REQUIRE(! v.is_slic3r_supported(*Semver::parse("1.37.0-alpha")));
}
