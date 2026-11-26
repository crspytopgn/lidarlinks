cmake_minimum_required(VERSION 3.20)
project(OpenLinks2003 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  add_compile_options(/W4 /permissive-)
else()
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

enable_testing()

# The GDExtension is off by default: it needs the godot-cpp submodule and
# a Godot 4.7 build, and the `core` CI job must stay a fast C++ check.
# Build it with -DBUILD_GDEXTENSION=ON (see docs/gdextension.md). The web
# build never ships it: the GDScript port stays the fallback there.
# When it is on, the static libraries need position-independent code:
# the extension links them into a shared object. This must be set
# before libs/olcore is added, so its targets pick it up.
option(BUILD_GDEXTENSION "Build the Olcore GDExtension (needs godot-cpp)" OFF)
if(BUILD_GDEXTENSION)
  set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

add_subdirectory(libs/olcore)
add_subdirectory(tools/olarc)
add_subdirectory(tools/olcourse)
add_subdirectory(tools/olobj)
add_subdirectory(tools/oldump)
add_subdirectory(tools/olcalibrate)
add_subdirectory(tools/oltex)

if(BUILD_GDEXTENSION)
  add_subdirectory(extensions/olcore)
endif()
