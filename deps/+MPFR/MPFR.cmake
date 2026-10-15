set(_srcdir ${CMAKE_CURRENT_LIST_DIR}/mpfr)
set(_dstdir ${${PROJECT_NAME}_DEP_INSTALL_PREFIX})

if (MSVC)
    set(_output  ${_dstdir}/include/mpfr.h
                 ${_dstdir}/include/mpf2mpfr.h
                 ${_dstdir}/lib/libmpfr-4.lib
                 ${_dstdir}/bin/libmpfr-4.dll)

    add_custom_command(
        OUTPUT  ${_output}
        COMMAND ${CMAKE_COMMAND} -E copy ${_srcdir}/include/mpfr.h ${_dstdir}/include/
        COMMAND ${CMAKE_COMMAND} -E copy ${_srcdir}/include/mpf2mpfr.h ${_dstdir}/include/
        COMMAND ${CMAKE_COMMAND} -E copy ${_srcdir}/lib/win${DEPS_BITS}/libmpfr-4.lib ${_dstdir}/lib/
        COMMAND ${CMAKE_COMMAND} -E copy ${_srcdir}/lib/win${DEPS_BITS}/libmpfr-4.dll ${_dstdir}/bin/
    )

    add_custom_target(dep_MPFR SOURCES ${_output})

else ()

    message(STATUS "${PROJECT_NAME}_DEP_INSTALL_PREFIX=${${PROJECT_NAME}_DEP_INSTALL_PREFIX}")

    slicer_vendor_archive(MPFR
        SHA256=b9df93635b20e4089c29623b19420c4ac848a1b29df1cfd59f26cab0d2666aa0
        _mpfr_archive)
    ExternalProject_Add(dep_MPFR
        EXCLUDE_FROM_ALL ON
        URL "${_mpfr_archive}"
        URL_HASH SHA256=b9df93635b20e4089c29623b19420c4ac848a1b29df1cfd59f26cab0d2666aa0
        DOWNLOAD_DIR ${${PROJECT_NAME}_DEP_DOWNLOAD_DIR}/MPFR
        BUILD_IN_SOURCE ON
        CONFIGURE_COMMAND
            ${CMAKE_COMMAND} -E env
                sh -c
                "autoreconf -f -i && \
                 CFLAGS='${_gmp_ccflags}' \
                 CXXFLAGS='${_gmp_ccflags}' \
                 ./configure ${_cross_compile_arg} \
                             --prefix='${${PROJECT_NAME}_DEP_INSTALL_PREFIX}' \
                             --enable-shared=no \
                             --enable-static=yes \
                             --with-gmp='${${PROJECT_NAME}_DEP_INSTALL_PREFIX}' \
                             ${_gmp_build_tgt}"
        BUILD_COMMAND make "-j${DEP_MAX_THREADS}"
        INSTALL_COMMAND make install
    )
endif ()

set(DEP_MPFR_DEPENDS GMP)
