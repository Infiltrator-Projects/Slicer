# SPDX-License-Identifier: AGPL-3.0-or-later
# Isolated native C++17 validator for Windows installer qualification.
cmake_minimum_required(VERSION 3.20)
project(SlicerFontVerify LANGUAGES CXX)
add_executable(slicer-font-verify ../../verify-fonts.cpp)
target_compile_features(slicer-font-verify PRIVATE cxx_std_17)
set_target_properties(slicer-font-verify PROPERTIES
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF)
