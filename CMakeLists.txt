cmake_minimum_required(VERSION 3.16)

project(cern_disk_benchmark LANGUAGES NONE)

set(MOUNTPOINT "" CACHE STRING "Mount point to benchmark")
set(PARALLELISM "1" CACHE STRING "Number of parallel writers (default 1)")
set(STOP_PERCENT "99" CACHE STRING "Stop when filesystem usage reaches this percent (1-100)")

if(MOUNTPOINT STREQUAL "" OR PARALLELISM STREQUAL "" OR STOP_PERCENT STREQUAL "")
  message(STATUS "Configure with -DMOUNTPOINT=/path [-DPARALLELISM=N] [-DSTOP_PERCENT=P] before running the benchmark target (defaults: parallelism=1, stop=99%).")
endif()

find_package(Python3 COMPONENTS Interpreter REQUIRED)

add_custom_target(
  benchmark
  COMMAND
    ${CMAKE_COMMAND}
    -DMOUNTPOINT=${MOUNTPOINT}
    -DPARALLELISM=${PARALLELISM}
    -DSTOP_PERCENT=${STOP_PERCENT}
    -DPYTHON_EXECUTABLE=${Python3_EXECUTABLE}
    -DSOURCE_DIR=${CMAKE_SOURCE_DIR}
    -P ${CMAKE_SOURCE_DIR}/cmake/run-benchmark.cmake
  USES_TERMINAL
  COMMENT "Run write benchmark and plot results"
)

