# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration. The Flutter plugin package is dxtr_box while
# the Rust crate/library intentionally keeps the stable rust_lib_dxtr_box name.
set(PROJECT_NAME "dxtr_box")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust rust_lib_dxtr_box "")

# List of absolute paths to libraries that should be bundled with the plugin.
set(dxtr_box_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
