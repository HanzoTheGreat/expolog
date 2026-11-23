cmake_minimum_required(VERSION 3.10)
cmake_policy(SET CMP0079 NEW)

# Project-level configuration.
set(PROJECT_NAME "rust_lib_expolog")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../rust rust_lib_expolog "")
target_link_libraries(${BINARY_NAME} PRIVATE "${${PROJECT_NAME}_cargokit_lib}")

# List of absolute paths to libraries that should be bundled with the plugin.
set(rust_lib_expolog_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)