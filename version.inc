# Product identity is owned by this repository, independently of upstream tags.
# Release helpers verify SLIC3R_VERSION against support/VERSION before building.
set(SLIC3R_APP_NAME "Slicer")
set(SLIC3R_APP_KEY "InfiltratorSlicer")
set(SLIC3R_VERSION "0.0.3")
# Printer profile/schema compatibility follows the inherited slicing engine.
set(SLIC3R_COMPATIBILITY_VERSION "2.9.6")
set(SLIC3R_BUILD_ID "${SLIC3R_APP_NAME}-${SLIC3R_VERSION}")
set(SLIC3R_RC_VERSION_DOTS "${SLIC3R_VERSION}.0")
string(REPLACE "." "," SLIC3R_RC_VERSION "${SLIC3R_RC_VERSION_DOTS}")
