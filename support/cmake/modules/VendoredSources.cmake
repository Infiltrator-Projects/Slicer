# SPDX-License-Identifier: AGPL-3.0-or-later
# Dependency sources belong to the checkout. Remote URLs in the dependency
# definitions document provenance; builds must never use them as a fallback.
include_guard(GLOBAL)

get_filename_component(_SLICER_VENDOR_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../../deps/vendor" ABSOLUTE)
if (NOT EXISTS "${_SLICER_VENDOR_ROOT}/manifest.cmake")
    message(FATAL_ERROR "Missing vendored dependency manifest: ${_SLICER_VENDOR_ROOT}/manifest.cmake. Restore deps/vendor from the repository.")
endif ()
include("${_SLICER_VENDOR_ROOT}/manifest.cmake")

function(slicer_vendor_archive package expected_hash output_variable)
    string(REGEX REPLACE "^SHA256=" "" _expected_hash "${expected_hash}")
    string(TOLOWER "${_expected_hash}" _expected_hash)
    string(LENGTH "${_expected_hash}" _hash_length)
    if (NOT _hash_length EQUAL 64 OR NOT _expected_hash MATCHES "^[0-9a-f]+$")
        message(FATAL_ERROR "${package}: vendored dependency sources require a SHA256 pin.")
    endif ()

    set(_prefix "SLICER_VENDOR_${package}")
    foreach (_field FILE SHA256 PARTS)
        if (NOT DEFINED ${_prefix}_${_field} OR "${${_prefix}_${_field}}" STREQUAL "")
            message(FATAL_ERROR "${package}: incomplete vendored source manifest (${_field}). Restore deps/vendor from the repository.")
        endif ()
    endforeach ()
    string(TOLOWER "${${_prefix}_SHA256}" _manifest_hash)
    if (NOT _expected_hash STREQUAL _manifest_hash)
        message(FATAL_ERROR "${package}: dependency SHA256 pin does not match deps/vendor/manifest.cmake. Vendor the exact pinned source before building.")
    endif ()

    set(_file "${${_prefix}_FILE}")
    if (IS_ABSOLUTE "${_file}" OR _file MATCHES "(^|/)\\.\\.(/|$)")
        message(FATAL_ERROR "${package}: vendored archive path must be relative to deps/vendor.")
    endif ()
    set(_parts "")
    foreach (_part IN LISTS ${_prefix}_PARTS)
        if (IS_ABSOLUTE "${_part}" OR _part MATCHES "(^|/)\\.\\.(/|$)")
            message(FATAL_ERROR "${package}: vendored source part path must be relative to deps/vendor.")
        endif ()
        set(_path "${_SLICER_VENDOR_ROOT}/${_part}")
        if (NOT EXISTS "${_path}" OR IS_DIRECTORY "${_path}")
            message(FATAL_ERROR "${package}: missing vendored source ${_path}. Restore this file from the repository; no network fallback is permitted.")
        endif ()
        list(APPEND _parts "${_path}")
    endforeach ()
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${_SLICER_VENDOR_ROOT}/manifest.cmake" ${_parts})

    list(LENGTH _parts _part_count)
    if (_part_count EQUAL 1)
        list(GET _parts 0 _archive)
    else ()
        set(_archive "${CMAKE_CURRENT_BINARY_DIR}/vendor-archives/${_file}")
        get_filename_component(_archive_directory "${_archive}" DIRECTORY)
        file(MAKE_DIRECTORY "${_archive_directory}")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E cat ${_parts}
            OUTPUT_FILE "${_archive}.tmp"
            ERROR_VARIABLE _assembly_error
            RESULT_VARIABLE _assembly_result
        )
        if (NOT _assembly_result EQUAL 0)
            file(REMOVE "${_archive}.tmp")
            message(FATAL_ERROR "${package}: could not assemble vendored source: ${_assembly_error}")
        endif ()
        set(_archive "${_archive}.tmp")
    endif ()

    file(SHA256 "${_archive}" _actual_hash)
    if (NOT _actual_hash STREQUAL _expected_hash)
        if (_part_count GREATER 1)
            file(REMOVE "${_archive}")
        endif ()
        message(FATAL_ERROR "${package}: vendored source checksum mismatch. Expected ${_expected_hash}, got ${_actual_hash}. Restore deps/vendor from the repository; no network fallback is permitted.")
    endif ()
    if (_part_count GREATER 1)
        set(_destination "${CMAKE_CURRENT_BINARY_DIR}/vendor-archives/${_file}")
        file(RENAME "${_archive}" "${_destination}")
        set(_archive "${_destination}")
    endif ()
    set(${output_variable} "${_archive}" PARENT_SCOPE)
endfunction()
