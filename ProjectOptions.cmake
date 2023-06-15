include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(dvdbrace_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(dvdbrace_setup_options)
  option(dvdbrace_ENABLE_HARDENING "Enable hardening" ON)
  option(dvdbrace_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    dvdbrace_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    dvdbrace_ENABLE_HARDENING
    OFF)

  dvdbrace_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR dvdbrace_PACKAGING_MAINTAINER_MODE)
    option(dvdbrace_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(dvdbrace_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(dvdbrace_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(dvdbrace_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(dvdbrace_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(dvdbrace_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(dvdbrace_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(dvdbrace_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(dvdbrace_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(dvdbrace_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(dvdbrace_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(dvdbrace_ENABLE_PCH "Enable precompiled headers" OFF)
    option(dvdbrace_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(dvdbrace_ENABLE_IPO "Enable IPO/LTO" ON)
    option(dvdbrace_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(dvdbrace_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(dvdbrace_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(dvdbrace_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(dvdbrace_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(dvdbrace_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(dvdbrace_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(dvdbrace_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(dvdbrace_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(dvdbrace_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(dvdbrace_ENABLE_PCH "Enable precompiled headers" OFF)
    option(dvdbrace_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      dvdbrace_ENABLE_IPO
      dvdbrace_WARNINGS_AS_ERRORS
      dvdbrace_ENABLE_USER_LINKER
      dvdbrace_ENABLE_SANITIZER_ADDRESS
      dvdbrace_ENABLE_SANITIZER_LEAK
      dvdbrace_ENABLE_SANITIZER_UNDEFINED
      dvdbrace_ENABLE_SANITIZER_THREAD
      dvdbrace_ENABLE_SANITIZER_MEMORY
      dvdbrace_ENABLE_UNITY_BUILD
      dvdbrace_ENABLE_CLANG_TIDY
      dvdbrace_ENABLE_CPPCHECK
      dvdbrace_ENABLE_COVERAGE
      dvdbrace_ENABLE_PCH
      dvdbrace_ENABLE_CACHE)
  endif()

  dvdbrace_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (dvdbrace_ENABLE_SANITIZER_ADDRESS OR dvdbrace_ENABLE_SANITIZER_THREAD OR dvdbrace_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(dvdbrace_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(dvdbrace_global_options)
  if(dvdbrace_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    dvdbrace_enable_ipo()
  endif()

  dvdbrace_supports_sanitizers()

  if(dvdbrace_ENABLE_HARDENING AND dvdbrace_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR dvdbrace_ENABLE_SANITIZER_UNDEFINED
       OR dvdbrace_ENABLE_SANITIZER_ADDRESS
       OR dvdbrace_ENABLE_SANITIZER_THREAD
       OR dvdbrace_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${dvdbrace_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${dvdbrace_ENABLE_SANITIZER_UNDEFINED}")
    dvdbrace_enable_hardening(dvdbrace_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(dvdbrace_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(dvdbrace_warnings INTERFACE)
  add_library(dvdbrace_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  dvdbrace_set_project_warnings(
    dvdbrace_warnings
    ${dvdbrace_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(dvdbrace_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(dvdbrace_options)
  endif()

  include(cmake/Sanitizers.cmake)
  dvdbrace_enable_sanitizers(
    dvdbrace_options
    ${dvdbrace_ENABLE_SANITIZER_ADDRESS}
    ${dvdbrace_ENABLE_SANITIZER_LEAK}
    ${dvdbrace_ENABLE_SANITIZER_UNDEFINED}
    ${dvdbrace_ENABLE_SANITIZER_THREAD}
    ${dvdbrace_ENABLE_SANITIZER_MEMORY})

  set_target_properties(dvdbrace_options PROPERTIES UNITY_BUILD ${dvdbrace_ENABLE_UNITY_BUILD})

  if(dvdbrace_ENABLE_PCH)
    target_precompile_headers(
      dvdbrace_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(dvdbrace_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    dvdbrace_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(dvdbrace_ENABLE_CLANG_TIDY)
    dvdbrace_enable_clang_tidy(dvdbrace_options ${dvdbrace_WARNINGS_AS_ERRORS})
  endif()

  if(dvdbrace_ENABLE_CPPCHECK)
    dvdbrace_enable_cppcheck(${dvdbrace_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(dvdbrace_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    dvdbrace_enable_coverage(dvdbrace_options)
  endif()

  if(dvdbrace_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(dvdbrace_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(dvdbrace_ENABLE_HARDENING AND NOT dvdbrace_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR dvdbrace_ENABLE_SANITIZER_UNDEFINED
       OR dvdbrace_ENABLE_SANITIZER_ADDRESS
       OR dvdbrace_ENABLE_SANITIZER_THREAD
       OR dvdbrace_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    dvdbrace_enable_hardening(dvdbrace_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
