# SPDX-License-Identifier: AGPL-3.0-or-later
# Unpack the exact official embeddable interpreter locally, without an
# installer, downloads, or registry changes.
cmake_minimum_required(VERSION 3.18.5)

if (NOT DEFINED SLICER_PYTHON_DESTINATION OR
    NOT IS_ABSOLUTE "${SLICER_PYTHON_DESTINATION}")
    message(FATAL_ERROR "SLICER_PYTHON_DESTINATION must be an absolute temporary directory.")
endif ()
get_filename_component(_repo "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
include("${_repo}/cmake/modules/VendoredSources.cmake")
slicer_vendor_archive(PythonWindowsARM64
    SHA256=790d097697a2020477549a6764d89d22194c88d6e42caebcb2db63791e004c94
    _python_archive)
file(MAKE_DIRECTORY "${SLICER_PYTHON_DESTINATION}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${_python_archive}"
    WORKING_DIRECTORY "${SLICER_PYTHON_DESTINATION}"
    RESULT_VARIABLE _extract_result
    ERROR_VARIABLE _extract_error
)
if (NOT _extract_result EQUAL 0 OR
    NOT EXISTS "${SLICER_PYTHON_DESTINATION}/python.exe" OR
    NOT EXISTS "${SLICER_PYTHON_DESTINATION}/python313._pth")
    message(FATAL_ERROR "Could not unpack the vendored Windows interpreter: ${_extract_error}")
endif ()

# The preparation probe reads generator helpers from this checked archive.
# Its temporary import path is removed again before publishing the runtime.
slicer_vendor_archive(z3 "${SLICER_VENDOR_z3_SHA256}" _z3_archive)
file(WRITE "${SLICER_PYTHON_DESTINATION}/.slicer-z3-archive" "${_z3_archive}")
