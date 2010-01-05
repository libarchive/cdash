# libarchive Common Dashboard Script
#
# This script contains basic dashboard driver code common to all
# clients.
#
# Put this script in a directory such as "~/Dashboards/Scripts" or
# "c:/Dashboards/Scripts".  Create a file next to this script, say
# 'libarchive_test.ctest', with code of the following form:
#
#   # Client maintainer: me@mydomain.net
#   set(CTEST_SITE "machine.site")
#   set(CTEST_BUILD_NAME "Platform-Compiler")
#   set(CTEST_BUILD_CONFIGURATION Debug)
#   set(CTEST_CMAKE_GENERATOR "Unix Makefiles")
#   include(${CTEST_SCRIPT_DIRECTORY}/libarchive_common.ctest)
#
# Then run a scheduled task (cron job) with a command line such as
#
#   ctest -S ~/Dashboards/Scripts/libarchive_test.ctest -V
#
# By default the source and build trees will be placed in the path
# "../My Tests/" relative to your script location.
#
# The following variables may be set before including this script
# to configure it:
#
#   dashboard_model       = Nightly | Experimental | Continuous
#   dashboard_cache       = Initial CMakeCache.txt file content
#   dashboard_do_coverage = True to enable coverage (ex: gcov)
#   dashboard_do_memcheck = True to enable memcheck (ex: valgrind)
#   CTEST_SVN_COMMAND     = path to svn command-line client
#   CTEST_BUILD_FLAGS     = build tool arguments (ex: -j2)
#   CTEST_DASHBOARD_ROOT  = Where to put source and build trees
#
# For Makefile generators the script may be executed from an
# environment already configured to use the desired compilers.
# Alternatively the environment may be set at the top of the script:
#
#   set(ENV{CC}  /path/to/cc)   # C compiler
#   set(ENV{CXX} /path/to/cxx)  # C++ compiler
#   set(ENV{FC}  /path/to/fc)   # Fortran compiler (optional)
#   set(ENV{LD_LIBRARY_PATH} /path/to/vendor/lib) # (if necessary)

cmake_minimum_required(VERSION 2.6.3 FATAL_ERROR)

set(CTEST_PROJECT_NAME libarchive)

# Select the top dashboard directory.
if(NOT DEFINED CTEST_DASHBOARD_ROOT)
  get_filename_component(CTEST_DASHBOARD_ROOT "${CTEST_SCRIPT_DIRECTORY}/../My Tests" ABSOLUTE)
endif()

# Select the model (Nightly, Experimental, Continuous).
if(NOT DEFINED dashboard_model)
  set(dashboard_model Nightly)
endif()
if(NOT "${dashboard_model}" MATCHES "^(Nightly|Experimental|Continuous)$")
  message(FATAL_ERROR "dashboard_model must be Nightly, Experimental, or Continuous")
endif()

# Default to a Debug build.
if(NOT DEFINED CTEST_BUILD_CONFIGURATION)
  set(CTEST_BUILD_CONFIGURATION Debug)
endif()

# Select svn source to use.
if(NOT DEFINED dashboard_url)
  set(dashboard_url "http://libarchive.googlecode.com/svn/trunk")
endif()

# Select a source directory name.
if(NOT DEFINED CTEST_SOURCE_DIRECTORY)
  set(CTEST_SOURCE_DIRECTORY "${CTEST_DASHBOARD_ROOT}/libarchive")
endif()

# Select a build directory name.
if(NOT DEFINED CTEST_BINARY_DIRECTORY)
  set(CTEST_BINARY_DIRECTORY ${CTEST_SOURCE_DIRECTORY}-${CTEST_BUILD_NAME})
endif()
make_directory(${CTEST_BINARY_DIRECTORY})

# Look for a Subversion command-line client.
if(NOT DEFINED CTEST_SVN_COMMAND)
  find_program(CTEST_SVN_COMMAND svn)
endif()

# Support initial checkout if necessary.
if(NOT EXISTS "${CTEST_SOURCE_DIRECTORY}"
    AND NOT DEFINED CTEST_CHECKOUT_COMMAND
    AND CTEST_SVN_COMMAND)
  get_filename_component(_name "${CTEST_SOURCE_DIRECTORY}" NAME)
  set(CTEST_CHECKOUT_COMMAND "\"${CTEST_SVN_COMMAND}\" co \"${dashboard_url}\" \"${_name}\"")
  # CTest delayed initialization is broken for non-Nightly modes so we
  # put the CTestConfig.cmake info here for use on first checkout.
  set(CTEST_NIGHTLY_START_TIME "01:00:00 UTC")
  set(CTEST_DROP_METHOD "http")
  set(CTEST_DROP_SITE "my.cdash.org")
  set(CTEST_DROP_LOCATION "/submit.php?project=libarchive")
  set(CTEST_DROP_SITE_CDASH TRUE)
endif()

#-----------------------------------------------------------------------------

# Send the main script as a note.
list(APPEND CTEST_NOTES_FILES
  "${CTEST_SCRIPT_DIRECTORY}/${CTEST_SCRIPT_NAME}"
  "${CMAKE_CURRENT_LIST_FILE}"
  )

# Check for required variables.
foreach(req
    CTEST_CMAKE_GENERATOR
    CTEST_SITE
    CTEST_BUILD_NAME
    )
  if(NOT DEFINED ${req})
    message(FATAL_ERROR "The containing script must set ${req}")
  endif()
endforeach(req)

# Print summary information.
foreach(v
    CTEST_SITE
    CTEST_BUILD_NAME
    CTEST_SOURCE_DIRECTORY
    CTEST_BINARY_DIRECTORY
    CTEST_CMAKE_GENERATOR
    CTEST_BUILD_CONFIGURATION
    CTEST_SVN_COMMAND
    CTEST_CHECKOUT_COMMAND
    CTEST_SCRIPT_DIRECTORY
    )
  set(vars "${vars}  ${v}=[${${v}}]\n")
endforeach(v)
message("Dashboard script configuration:\n${vars}\n")

# Avoid non-ascii characters in tool output.
set(ENV{LC_ALL} C)

# Helper macro to write the initial cache.
macro(write_cache)
  if(CTEST_CMAKE_GENERATOR MATCHES "Make")
    set(cache_build_type CMAKE_BUILD_TYPE:STRING=${CTEST_BUILD_CONFIGURATION})
  endif()
  file(WRITE ${CTEST_BINARY_DIRECTORY}/CMakeCache.txt "
SITE:STRING=${CTEST_SITE}
BUILDNAME:STRING=${CTEST_BUILD_NAME}
${cache_build_type}
${dashboard_cache}
")
endmacro(write_cache)

# Start with a fresh build tree.
message("Clearing build tree...")
ctest_empty_binary_directory(${CTEST_BINARY_DIRECTORY})

set(dashboard_continuous 0)
if("${dashboard_model}" STREQUAL "Continuous")
  set(dashboard_continuous 1)
endif()

set(dashboard_done 0)
while(NOT dashboard_done)
  if(dashboard_continuous)
    set(START_TIME ${CTEST_ELAPSED_TIME})
  endif()

  # Start a new submission.
  ctest_start(${dashboard_model})

  # Always build if the tree is fresh.
  set(dashboard_fresh 0)
  if(NOT EXISTS "${CTEST_BINARY_DIRECTORY}/CMakeCache.txt")
    set(dashboard_fresh 1)
    message("Starting fresh build...")
    write_cache()
  endif()

  # Look for updates.
  ctest_update(RETURN_VALUE count)
  message("Found ${count} changed files")
  if(dashboard_fresh OR NOT dashboard_continuous OR count GREATER 0)
    ctest_configure()
    ctest_read_custom_files(${CTEST_BINARY_DIRECTORY})
    ctest_build()
    ctest_test()
    if(dashboard_do_coverage)
      ctest_coverage()
    endif()
    if(dashboard_do_memcheck)
      ctest_memcheck()
    endif()
    ctest_submit()
  endif()

  if(dashboard_continuous)
    # Delay until at least 5 minutes past START_TIME
    ctest_sleep(${START_TIME} 300 ${CTEST_ELAPSED_TIME})
    if(${CTEST_ELAPSED_TIME} GREATER 43200)
      set(dashboard_done 1)
    endif()
  else()
    # Not continuous, so we are done.
    set(dashboard_done 1)
  endif()
endwhile()
