# Product identity is owned by this repository, independently of upstream tags.
# support/VERSION is the single product-version authority.
set(SLIC3R_APP_NAME "Slicer")
set(SLIC3R_APP_KEY "InfiltratorSlicer")
file(READ "${CMAKE_CURRENT_LIST_DIR}/VERSION" SLIC3R_VERSION)
string(STRIP "${SLIC3R_VERSION}" SLIC3R_VERSION)
# Printer profile/schema compatibility follows the inherited slicing engine.
set(SLIC3R_COMPATIBILITY_VERSION "2.9.6")
set(SLIC3R_BUILD_ID "${SLIC3R_APP_NAME}-${SLIC3R_VERSION}")
set(SLIC3R_RC_VERSION_DOTS "${SLIC3R_VERSION}.0")
string(REPLACE "." "," SLIC3R_RC_VERSION "${SLIC3R_RC_VERSION_DOTS}")
