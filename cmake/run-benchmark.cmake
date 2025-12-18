cmake_minimum_required(VERSION 3.16)

# Determine the source directory even when invoked directly via `cmake -P`.
if(NOT DEFINED SOURCE_DIR OR SOURCE_DIR STREQUAL "")
  get_filename_component(_script_dir "${CMAKE_SCRIPT_MODE_FILE}" DIRECTORY)
  get_filename_component(SOURCE_DIR "${_script_dir}/.." ABSOLUTE)
endif()

# Accept arguments either from cache variables (preferred when invoked as a target)
# or as positional script arguments (cmake -P cmake/run-benchmark.cmake <mount> [parallel] [stop-percent]).
set(_mount "")
set(_parallel "1") # default parallelism
set(_stop "99")    # default stop threshold (percent)

if(DEFINED MOUNTPOINT AND NOT "${MOUNTPOINT}" STREQUAL "")
  set(_mount "${MOUNTPOINT}")
endif()
if(DEFINED PARALLELISM AND NOT "${PARALLELISM}" STREQUAL "")
  set(_parallel "${PARALLELISM}")
endif()
if(DEFINED STOP_PERCENT AND NOT "${STOP_PERCENT}" STREQUAL "")
  set(_stop "${STOP_PERCENT}")
endif()

if(_mount STREQUAL "" )
  if(CMAKE_ARGC GREATER 1)
    set(_mount "${CMAKE_ARGV1}")
    if(CMAKE_ARGC GREATER 2)
      set(_parallel "${CMAKE_ARGV2}")
      if(CMAKE_ARGC GREATER 3)
        set(_stop "${CMAKE_ARGV3}")
      endif()
    endif()
  endif()
endif()

if(_mount STREQUAL "" OR _parallel STREQUAL "" OR _stop STREQUAL "")
  message(FATAL_ERROR "Usage:\n  cmake -DMOUNTPOINT=/path [-DPARALLELISM=N] [-DSTOP_PERCENT=P] -P cmake/run-benchmark.cmake\n  cmake -P cmake/run-benchmark.cmake /path [N] [P]")
endif()

if(NOT _parallel MATCHES "^[0-9]+$")
  message(FATAL_ERROR "PARALLELISM must be a positive integer (got '${_parallel}').")
endif()
if(NOT _stop MATCHES "^[0-9]+$" OR _stop LESS 1 OR _stop GREATER 100)
  message(FATAL_ERROR "STOP_PERCENT must be an integer between 1 and 100 (got '${_stop}').")
endif()

# Locate python if it was not passed from the cache.
if(NOT DEFINED PYTHON_EXECUTABLE OR PYTHON_EXECUTABLE STREQUAL "")
  find_program(PYTHON_EXECUTABLE python3 REQUIRED)
endif()

# Prefer the wrapper script, fall back to the original .sh if needed.
set(_benchmark_script "${SOURCE_DIR}/write-benchmark")
if(NOT EXISTS "${_benchmark_script}")
  set(_benchmark_script "${SOURCE_DIR}/write-benchmark.sh")
endif()

message(STATUS "Running benchmark: ${_benchmark_script} ${_mount} ${_parallel}")
execute_process(
  COMMAND "${_benchmark_script}" "${_mount}" "${_parallel}" "${_stop}"
  WORKING_DIRECTORY "${SOURCE_DIR}"
  RESULT_VARIABLE _bench_result
)
if(NOT _bench_result EQUAL 0)
  message(FATAL_ERROR "write-benchmark failed with exit code ${_bench_result}.")
endif()

# Determine the device name for the log file (matches write-benchmark.sh logic).
execute_process(
  COMMAND df -P "${_mount}"
  OUTPUT_VARIABLE _df_output
  OUTPUT_STRIP_TRAILING_WHITESPACE
  RESULT_VARIABLE _df_result
)
if(NOT _df_result EQUAL 0)
  message(FATAL_ERROR "Failed to run df for mount '${_mount}'.")
endif()

string(REGEX REPLACE ".*\n" "" _df_line "${_df_output}")
string(REGEX MATCH "^([^ \t]+)" _match "${_df_line}")
if(NOT CMAKE_MATCH_1)
  message(FATAL_ERROR "Unable to parse device from df output:\n${_df_output}")
endif()
set(_target_dev "${CMAKE_MATCH_1}")
get_filename_component(_dev_basename "${_target_dev}" NAME)

set(_log_path "/var/tmp/write-benchmark-${_dev_basename}.log")
set(_output_path "${SOURCE_DIR}/write-speed-${_dev_basename}.jpg")

message(STATUS "Plotting results from ${_log_path} -> ${_output_path}")
execute_process(
  COMMAND "${PYTHON_EXECUTABLE}" "${SOURCE_DIR}/plot_benchmark.py" "${_log_path}" "${_output_path}"
  WORKING_DIRECTORY "${SOURCE_DIR}"
  RESULT_VARIABLE _plot_result
)
if(NOT _plot_result EQUAL 0)
  message(FATAL_ERROR "plot_benchmark.py failed with exit code ${_plot_result}.")
endif()

message(STATUS "Benchmark complete. Log: ${_log_path}, Plot: ${_output_path}")

