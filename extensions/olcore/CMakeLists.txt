# Olcore GDExtension — the C++ physics core (libs/olcore) exposed to Godot.
#
# Built only when -DBUILD_GDEXTENSION=ON. The default `core` CI job never
# pays for it, and the web build never ships it (see
# game/addons/olcore/olcore.gdextension: no web entry, and the GDScript
# port in game/scripts/physics/ stays the fallback there).
#
# godot-cpp comes from the submodule at extensions/godot-cpp, pinned to
# the commit in .gitmodules. There is no godot-4.7-stable godot-cpp
# release yet (latest tag is 4.5), so the pin is to master at a commit
# whose extension_api-4-7.json matches Godot 4.7; re-pin to the 4.7 tag
# when it lands.
cmake_minimum_required(VERSION 3.20)
project(olcore_gdext LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  add_compile_options(/W4 /permissive-)
else()
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# The snapshot core: no Godot headers, so it is unit-tested on its own.
add_library(olcore_snapshot STATIC src/olcore_snapshot.cpp)
target_include_directories(olcore_snapshot PUBLIC src)
target_link_libraries(olcore_snapshot PUBLIC olcore)

add_executable(olcore_snapshot_tests tests/test_snapshot.cpp)
target_link_libraries(olcore_snapshot_tests PRIVATE olcore_snapshot olcore)
add_test(NAME olcore_snapshot_tests COMMAND olcore_snapshot_tests)

# The Godot binding: needs the godot-cpp submodule checked out. The
# snapshot core and its tests build without it, so the C++ parity checks
# run even where godot-cpp is absent; the shared library is skipped with
# a warning in that case.
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp/CMakeLists.txt)
  message(WARNING "godot-cpp submodule is not checked out: the GDExtension "
                  "shared library will not be built; run "
                  "git submodule update --init --recursive to build it")
  return()
endif()
# godot-cpp's CMake needs to know which extension API to target.
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "" FORCE)
set(GODOTCPP_TARGET "template_release" CACHE STRING "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp ${CMAKE_CURRENT_BINARY_DIR}/godot-cpp)

add_library(olcore_gdext SHARED src/olcore_physics.cpp src/register_types.cpp)
target_link_libraries(olcore_gdext PRIVATE olcore_snapshot olcore godot-cpp)

# Binaries land where the .gdextension file expects them, named per
# platform (macOS needs both architectures for the universal export;
# build with -DCMAKE_OSX_ARCHITECTURES=arm64 and =x86_64 separately).
set_target_properties(olcore_gdext PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)
if(APPLE)
  if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
    set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "olcore.macos.arm64")
  else()
    set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "olcore.macos.x86_64")
  endif()
  set_target_properties(olcore_gdext PROPERTIES SUFFIX ".dylib")
elseif(WIN32)
  set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "libolcore.windows.x86_64" SUFFIX ".dll")
else()
  set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "olcore.linux.x86_64" SUFFIX ".so")
endif()
